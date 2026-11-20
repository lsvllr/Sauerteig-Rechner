// Server des eigenständigen Sauerteig-Rechners: liefert die App aus (dist/), verwaltet Konten (db.ts), gleicht ab
// zwei Geräten eines Kontos deren Daten ab und schickt die Erinnerungen des Back-Timers per Web-Push.
//
// Die Apps (Web und iOS) laufen ohne Server und ohne Konto; die Daten liegen auf dem Gerät. Ein Konto (nur mit
// Einladungscode vom Admin, ADMIN_PASSWORD, Seite /admin) braucht es nur, um Geräte zu verknüpfen. Der Abgleich
// (/api/sync/*, src/abgleich.ts, ios/Sauerteig/App/Abgleich.swift) ist ein Relais für Ende-zu-Ende verschlüsselte
// Änderungen: Er kennt nur Tabelle, uid und Zeit, nimmt nur an, solange das Konto mindestens zwei Geräte hat, und
// vergisst alles, sobald es wieder nur eins ist. Neues meldet er den anderen Geräten sofort: offene Apps über
// Server-Sent Events (/api/sync/live), geschlossene iOS-Apps per stillem APNs-Push.
// Push für die Web-App: Ab „Backen beginnen“ melden die Geräte den Zeitplan (/api/timer); den kennt der Server als
// bewusste Ausnahme, sonst könnte er bei geschlossener Seite nicht melden. Fällig wird nach denselben Regeln wie im
// Browser (faellig() aus src/gemeinsam/timer.ts). Dazu der Weckdienst der iOS-App (/api/wecker, server/wecker.ts).
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join, normalize } from 'node:path';
import webpush from 'web-push';
import { BEGINN, VORLAUF_WAHL, faellig, type Lauf } from '../src/gemeinsam/timer';
import * as apns from './apns';
import * as db from './db';
import * as wecker from './wecker';

const PORT = Number(process.env.PORT ?? 8080);
const DIST = process.env.DIST ?? join(process.cwd(), 'dist');
const APP_URL = (process.env.APP_URL ?? 'https://sauerteig.vollrath.app').replace(/\/$/, '');
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? '';
/** Nur diesem einen Header die Client-IP glauben (Add-on: cf-connecting-ip von Cloudflare), sonst dem Socket. */
const CLIENT_IP_HEADER = (process.env.CLIENT_IP_HEADER ?? '').toLowerCase();
const COOKIE_SECURE = process.env.COOKIE_SECURE === '1';
const TAKT = 10_000;
const MAX_BODY = 16_000;
const MAX_BODY_IMPORT = 400_000;
const SITZUNG = 'sd_sitzung';
const ADMIN = 'sd_admin';
const ADMIN_DAUER = 12 * 3600_000;

let schluessel = { publicKey: process.env.VAPID_PUBLIC_KEY ?? '', privateKey: process.env.VAPID_PRIVATE_KEY ?? '' };
if (!schluessel.publicKey || !schluessel.privateKey) {
  // Ohne Secret: Schlüssel nur bis zum Neustart; die App meldet sich dann mit neuem Abo an.
  schluessel = webpush.generateVAPIDKeys();
  console.warn('VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY fehlen: Schlüssel gelten nur bis zum Neustart.');
}
webpush.setVapidDetails(APP_URL, schluessel.publicKey, schluessel.privateKey);
if (!ADMIN_PASSWORD) console.warn('ADMIN_PASSWORD fehlt: /admin ist gesperrt, es lassen sich keine Einladungen erzeugen.');

/* ------------------------------------------------------------------ Prüfen */

const istText = (v: unknown, max: number): v is string => typeof v === 'string' && v.length <= max;
const istZahl = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

/** Nur die Push-Dienste der Browser (sonst ließe sich der Server an beliebige Adressen schicken). */
const PUSH_DIENSTE = /^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|([a-z0-9-]+\.)*push\.apple\.com|([a-z0-9-]+\.)*notify\.windows\.com)$/;

function pruefeAbo(v: unknown): db.Abo | null {
  const a = v as db.Abo | null;
  if (!a || !istText(a.endpoint, 1000)) return null;
  try {
    const u = new URL(a.endpoint);
    if (u.protocol !== 'https:' || !PUSH_DIENSTE.test(u.hostname)) return null;
  } catch {
    return null;
  }
  if (!a.keys || !istText(a.keys.p256dh, 200) || !istText(a.keys.auth, 100)) return null;
  return { endpoint: a.endpoint, keys: { p256dh: a.keys.p256dh, auth: a.keys.auth } };
}

/** Zeitplan ab „Backen beginnen“; Uhrzeiten höchstens 7 Tage weg. */
function pruefeLauf(v: unknown, jetzt: number): Lauf | null {
  const l = v as Lauf | null;
  if (!l || l.phase !== 'backen' || !Array.isArray(l.schritte) || l.schritte.length < 2 || l.schritte.length > 12)
    return null;
  if (!istZahl(l.vorlauf) || !VORLAUF_WAHL.includes(l.vorlauf)) return null;
  const schritte = [];
  for (const s of l.schritte) {
    if (!s || !istZahl(s.at) || !istText(s.titel, 80) || !istText(s.dauer, 40)) return null;
    if (Math.abs(s.at - jetzt) > 7 * 24 * 3600_000) return null;
    schritte.push({ at: s.at, titel: s.titel, dauer: s.dauer });
  }
  const start = schritte[0]!.at;
  return {
    phase: 'backen',
    start,
    reife: [start, start],
    // Jetzt gemeldet: Vergangenes nicht nachholen (Neustart, erneutes Öffnen der App).
    erstellt: jetzt,
    vorlauf: l.vorlauf,
    schritte,
    gemeldet: [],
  };
}

/** Name des Kontos: 1–40 Zeichen, keine Steuerzeichen. */
function pruefeName(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const n = v.normalize('NFC').replace(/\s+/g, ' ').trim();
  return n.length >= 1 && n.length <= 40 && !/[\u0000-\u001f\u007f]/.test(n) ? n : null;
}

/* --------------------------------------------------------------- Abgleich */

const TABELLEN = new Set(['rezept', 'profil', 'backlauf']);
const UID = /^[A-Za-z0-9-]{1,64}$/;
const ZEIT = /^(\d{13})-[0-9a-f]{4}-[A-Za-z0-9_]{8,64}$/;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
const SCHLUESSEL_ID = /^[0-9a-f]{16}$/;
const MAX_JE_SENDEN = 1000;

/* Offene Apps (Server-Sent Events) je Konto; Cloudflare schließt stille Verbindungen nach rund 100 s. */
const live = new Map<number, Set<{ res: ServerResponse; token: string }>>();
setInterval(() => {
  for (const s of live.values()) for (const l of s) l.res.write(': ping\n\n');
}, 25_000).unref();

/** Stiller Push je Gerät höchstens alle 10 s (mehrere Änderungen kurz hintereinander zusammen). */
const pushGeplant = new Map<string, ReturnType<typeof setTimeout>>();

/** Neues im Abgleich: den anderen Geräten des Kontos Bescheid geben (nicht dem, das gesendet hat). */
function benachrichtige(kontoId: number, vonToken: string): void {
  for (const l of live.get(kontoId) ?? []) if (l.token !== vonToken) l.res.write('event: neu\ndata: {}\n\n');
  if (!apns.aktiv()) return;
  for (const ziel of db.pushZiele(kontoId, vonToken)) {
    if (pushGeplant.has(ziel)) continue;
    pushGeplant.set(
      ziel,
      setTimeout(() => {
        pushGeplant.delete(ziel);
        void apns.sendeStill(ziel).then((r) => {
          if (r === 'gone') db.vergissPushZiel(ziel);
        });
      }, 2000),
    );
  }
}

/** Änderungen eines Geräts prüfen; Zeiten über 10 Minuten vor der Uhr des Servers lehnt er ab. */
function pruefeAenderungen(v: unknown, jetzt: number): db.Aenderung[] | null {
  if (!Array.isArray(v) || v.length > MAX_JE_SENDEN) return null;
  const aus: db.Aenderung[] = [];
  for (const a of v as Partial<db.Aenderung>[]) {
    if (!a || !istText(a.tabelle, 20) || !TABELLEN.has(a.tabelle) || !istText(a.uid, 64) || !UID.test(a.uid)) return null;
    const z = istText(a.zeit, 90) ? ZEIT.exec(a.zeit) : null;
    if (!z || Number(z[1]) > jetzt + 10 * 60_000) return null;
    if (typeof a.geloescht !== 'boolean' || !a.daten || typeof a.daten !== 'object' || Array.isArray(a.daten)) return null;
    // Inhalt nur verschlüsselt: {x: base64}; Löschen ohne Inhalt
    const x = (a.daten as { x?: unknown }).x;
    if (!a.geloescht && (Object.keys(a.daten).length !== 1 || !istText(x, 60_000) || !BASE64.test(x))) return null;
    aus.push({ tabelle: a.tabelle, uid: a.uid, zeit: a.zeit!, geloescht: a.geloescht, daten: a.geloescht ? {} : { x } });
  }
  return aus;
}

/* ------------------------------------------------------------------ Melden */

function offen(l: Lauf): boolean {
  return l.schritte.some((_, i) => i >= BEGINN && !l.gemeldet.includes(`${i}:jetzt`));
}

async function tick(): Promise<void> {
  const jetzt = Date.now();
  for (const { kontoId, lauf } of db.backlaeufe()) {
    const vorher = lauf.gemeldet.length;
    const meldungen = faellig(lauf, jetzt);
    for (const m of meldungen) {
      for (const abo of db.abos(kontoId)) {
        try {
          await webpush.sendNotification(
            abo,
            JSON.stringify({ title: m.titel, body: m.text, url: '/', tag: 'sauerteig' }),
            { TTL: m.key.endsWith(':bald') ? lauf.vorlauf * 60 : 1800 },
          );
          console.log(`Push ${m.key} an Konto ${kontoId}: ${m.titel}`);
        } catch (err) {
          const status = (err as { statusCode?: number }).statusCode;
          if (status === 404 || status === 410) {
            console.log(`Push ${m.key}: Abo abgelaufen (${status}), entfernt`);
            db.vergissAbo(abo.endpoint);
          } else console.warn(`Push ${m.key} fehlgeschlagen:`, status ?? err);
        }
      }
    }
    if (!offen(lauf)) db.aktualisiereBacklauf(kontoId, lauf, true);
    else if (lauf.gemeldet.length !== vorher) db.aktualisiereBacklauf(kontoId, lauf, false);
  }
}

setInterval(() => db.raeumeSitzungenAuf(), 24 * 3600_000);
setInterval(() => {
  tick().catch((err) => console.warn('Back-Timer:', err));
  wecker.tick().catch((err) => console.warn('Wecker:', err));
}, TAKT);
console.log(apns.aktiv() ? `APNs aktiv (${apns.TOPIC})` : 'APNs aus: Live-Aktivitäten der iOS-App schalten nur bei offener App weiter.');

/* -------------------------------------------------------- Schutz vor Raten */

/** Fehlversuche je IP (Codes, Admin-Passwort): höchstens 10 in 15 Minuten. */
const versuche = new Map<string, { n: number; bis: number }>();
const SPERRE = 15 * 60_000;
function gesperrt(ip: string): boolean {
  const v = versuche.get(ip);
  return !!v && v.bis > Date.now() && v.n >= 10;
}
function fehlversuch(ip: string): void {
  const v = versuche.get(ip);
  if (!v || v.bis < Date.now()) versuche.set(ip, { n: 1, bis: Date.now() + SPERRE });
  else v.n++;
  if (versuche.size > 10_000) versuche.clear();
}

/** Weckdienst ohne Anmeldung: höchstens 120 Anfragen je IP in 15 Minuten. */
const weckerAnfragen = new Map<string, { n: number; bis: number }>();
function weckerZuViel(ip: string): boolean {
  const v = weckerAnfragen.get(ip);
  if (!v || v.bis < Date.now()) {
    if (weckerAnfragen.size > 10_000) weckerAnfragen.clear();
    weckerAnfragen.set(ip, { n: 1, bis: Date.now() + SPERRE });
    return false;
  }
  return ++v.n > 120;
}

function clientIp(req: IncomingMessage): string {
  const h = CLIENT_IP_HEADER ? req.headers[CLIENT_IP_HEADER] : undefined;
  return (Array.isArray(h) ? h[0] : h) || req.socket.remoteAddress || '?';
}

/* ------------------------------------------------------------------- Admin */

const adminSitzungen = new Map<string, number>();

function istAdmin(req: IncomingMessage): boolean {
  const t = cookies(req)[ADMIN];
  const bis = t ? adminSitzungen.get(t) : undefined;
  return !!bis && bis > Date.now();
}

function passwortStimmt(p: unknown): boolean {
  if (!ADMIN_PASSWORD || typeof p !== 'string') return false;
  const a = Buffer.from(db.hash(p));
  const b = Buffer.from(db.hash(ADMIN_PASSWORD));
  return timingSafeEqual(a, b);
}

/* ------------------------------------------------------------------- HTTP */

const TYPEN: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function json(res: ServerResponse, status: number, daten: unknown, kopf: Record<string, string | string[]> = {}): void {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...kopf });
  res.end(JSON.stringify(daten));
}
const fehler = (res: ServerResponse, status: number, text: string) => json(res, status, { ok: false, error: text });

async function lies(req: IncomingMessage, max = MAX_BODY): Promise<Record<string, unknown>> {
  let text = '';
  for await (const teil of req) {
    text += teil;
    if (text.length > max) throw new Error('zu groß');
  }
  const d = JSON.parse(text || '{}');
  return d && typeof d === 'object' ? d : {};
}

function cookies(req: IncomingMessage): Record<string, string> {
  const aus: Record<string, string> = {};
  for (const teil of (req.headers.cookie ?? '').split(';')) {
    const i = teil.indexOf('=');
    if (i > 0) aus[teil.slice(0, i).trim()] = decodeURIComponent(teil.slice(i + 1).trim());
  }
  return aus;
}

function cookie(name: string, wert: string, maxAlterS: number, pfad = '/'): string {
  return `${name}=${wert}; Path=${pfad}; Max-Age=${maxAlterS}; HttpOnly; SameSite=Lax${COOKIE_SECURE ? '; Secure' : ''}`;
}
/** 400 Tage: Höchstwert der Browser. */
const sitzungsCookie = (token: string) => cookie(SITZUNG, token, 400 * 24 * 3600);

/** Schreibende Anfragen nur von der eigenen Seite (zusätzlich zu SameSite=Lax und JSON). */
function eigeneHerkunft(req: IncomingMessage): boolean {
  const o = req.headers.origin;
  if (!o) return true;
  return o === new URL(APP_URL).origin || o === `http://${req.headers.host}` || o === `https://${req.headers.host}`;
}

/** Wie bisher nginx.conf: Assets lange cachen, sw.js/Manifest/Seiten nie, unbekannte Pfade → index.html. */
function datei(req: IncomingMessage, res: ServerResponse): void {
  const pfad = decodeURIComponent(new URL(req.url ?? '/', 'http://x').pathname);
  let ziel = normalize(join(DIST, pfad));
  if (!ziel.startsWith(DIST) || !existsSync(ziel) || !statSync(ziel).isFile()) ziel = join(DIST, 'index.html');
  const cache = pfad.startsWith('/assets/') ? 'public, max-age=31536000, immutable' : 'no-cache';
  res.writeHead(200, { 'Content-Type': TYPEN[extname(ziel)] ?? 'application/octet-stream', 'Cache-Control': cache });
  createReadStream(ziel).pipe(res);
}

function geraet(req: IncomingMessage): string {
  const ua = req.headers['user-agent'] ?? '';
  const os = /iPhone|iPad|Android|Mac OS X|Windows|Linux/.exec(ua)?.[0] ?? '';
  const browser = /Edg|Firefox|Chrome|Safari/.exec(ua)?.[0] ?? '';
  return [os.replace('Mac OS X', 'Mac'), browser.replace('Edg', 'Edge')].filter(Boolean).join(', ');
}

async function api(req: IncomingMessage, res: ServerResponse, pfad: string): Promise<void> {
  const m = req.method ?? 'GET';
  if (m !== 'GET' && !eigeneHerkunft(req)) return fehler(res, 403, 'Fremde Herkunft');
  if (m === 'POST' && !(req.headers['content-type'] ?? '').startsWith('application/json'))
    return fehler(res, 415, 'Nur JSON');
  const ip = clientIp(req);

  /* ---------- ohne Anmeldung ---------- */
  if (pfad === '/api/push-key' && m === 'GET') return json(res, 200, { key: schluessel.publicKey });

  // Weckdienst der iOS-App: kennt nur Token und Zeitpunkte, daher ohne Konto.
  if ((pfad === '/api/wecker' || pfad === '/api/wecker/stop') && m === 'POST') {
    if (weckerZuViel(ip)) return fehler(res, 429, 'Zu viele Anfragen');
    const d = await lies(req);
    if (pfad === '/api/wecker/stop') {
      const t = typeof d.token === 'string' ? d.token.toLowerCase() : '';
      if (!apns.zerlege(t)) return fehler(res, 400, 'Token fehlt');
      await wecker.stoppen(t);
      return json(res, 200, { ok: true });
    }
    const w = wecker.pruefe(d, Date.now());
    if (!w) return fehler(res, 400, 'Ungültig');
    if (!wecker.anmelden(w.token, w.zeiten, Date.now())) return fehler(res, 503, 'Voll');
    return json(res, 200, { ok: true, apns: apns.aktiv() });
  }

  // Neues Konto (Einladungscode) oder weiteres Gerät (Gerätecode). Die Daten bleiben auf dem Gerät; die iOS-App
  // (``app: true``) bekommt den Sitzungs-Schlüssel in der Antwort und schickt ihn als Bearer-Token mit.
  if ((pfad === '/api/registrieren' || pfad === '/api/anmelden') && m === 'POST') {
    if (gesperrt(ip)) return fehler(res, 429, 'Zu viele Versuche, bitte später noch einmal');
    const d = await lies(req);
    let k: (db.Konto & { schluessel?: string | null }) | null;
    if (pfad === '/api/registrieren') {
      const name = pruefeName(d.name);
      if (!name) return fehler(res, 400, 'Bitte einen Namen mit 1–40 Zeichen wählen');
      if (!istText(d.code, 40)) return fehler(res, 400, 'Einladungscode fehlt');
      const r = db.registriere(d.code, name);
      if (!r.ok) {
        if (r.fehler.startsWith('Einladungscode')) fehlversuch(ip);
        return fehler(res, 400, r.fehler);
      }
      k = r.wert;
      console.log(`Neues Konto „${name}“`);
    } else {
      k = istText(d.code, 40) ? db.loeseGeraetecode(d.code) : null;
      if (!k) {
        fehlversuch(ip);
        return fehler(res, 400, 'Gerätecode ungültig oder abgelaufen');
      }
    }
    const token = db.neueSitzung(k.id, istText(d.geraet, 60) && d.geraet ? d.geraet : geraet(req));
    const schluessel = 'schluessel' in k ? k.schluessel : null;
    return json(res, 200, { ok: true, name: k.name, schluessel, ...(d.app === true ? { token } : {}) }, {
      'Set-Cookie': sitzungsCookie(token),
    });
  }

  /* ---------- Admin ---------- */
  if (pfad.startsWith('/api/admin/')) return admin(req, res, pfad, ip);

  /* ---------- mit Anmeldung (Cookie der Web-App oder Bearer-Token der iOS-App) ---------- */
  const bearer = /^Bearer (\S{20,200})$/.exec(req.headers.authorization ?? '')?.[1];
  const token = bearer ?? cookies(req)[SITZUNG];
  const konto = token ? db.kontoZuSitzung(token) : null;
  if (!konto) return fehler(res, 401, 'Nicht angemeldet');

  if (pfad === '/api/ich' && m === 'GET') return json(res, 200, { ok: true, name: konto.name, geraete: db.geraete(konto.id) });

  if (pfad === '/api/abmelden' && m === 'POST') {
    db.beendeSitzung(token!);
    const d = await lies(req);
    if (istText(d.endpoint, 1000)) db.vergissAbo(d.endpoint);
    return json(res, 200, { ok: true }, { 'Set-Cookie': cookie(SITZUNG, '', 0) });
  }

  // Verknüpfte Geräte des eigenen Kontos ansehen und einzelne entfernen (z. B. ein verlorenes Gerät)
  if (pfad === '/api/sitzungen' && m === 'GET') return json(res, 200, { ok: true, sitzungen: db.sitzungenVon(konto.id, token!) });
  const eigene = /^\/api\/sitzungen\/(\d+)$/.exec(pfad);
  if (eigene && m === 'DELETE') {
    if (!db.entferneSitzung(konto.id, Number(eigene[1]))) return fehler(res, 404, 'Gerät nicht gefunden');
    return json(res, 200, { ok: true });
  }

  // Gerätecode, optional mit dem verpackten Schlüssel des Kontos (verpackt mit dem geheimen Teil des Codes)
  if (pfad === '/api/geraetecode' && m === 'POST') {
    const d = await lies(req);
    const schluessel = istText(d.schluessel, 400) && BASE64.test(d.schluessel) ? d.schluessel : null;
    return json(res, 200, { ok: true, ...db.neuerGeraetecode(konto.id, schluessel) });
  }
  // Schlüssel auf ein schon angemeldetes Gerät holen (Gerätecode eines anderen Geräts desselben Kontos)
  if (pfad === '/api/schluessel' && m === 'POST') {
    if (gesperrt(ip)) return fehler(res, 429, 'Zu viele Versuche, bitte später noch einmal');
    const d = await lies(req);
    const k = istText(d.code, 40) ? db.loeseGeraetecode(d.code, konto.id) : null;
    if (!k?.schluessel) {
      fehlversuch(ip);
      return fehler(res, 400, 'Gerätecode ungültig oder abgelaufen');
    }
    return json(res, 200, { ok: true, schluessel: k.schluessel });
  }

  // Abgleich: nur ab zwei Geräten. ``ab`` ist der Stand, bis zu dem das Gerät geholt und übernommen hat.
  // ``schluessel``: Kennung des Schlüssels des Geräts. Das erste Gerät legt sie fest; ein Gerät mit anderem oder
  // ohne Schlüssel bekommt nichts (``schluesselDa``: das Konto hat schon einen).
  if (pfad === '/api/sync/holen' && m === 'GET') {
    const q = new URL(req.url ?? '/', 'http://x').searchParams;
    const k = db.kennung(konto.id);
    const ab = q.get('kennung') === k ? Math.max(0, Number(q.get('ab')) || 0) : 0;
    const geraete = db.geraete(konto.id);
    const mein = q.get('schluessel') ?? '';
    const sid = SCHLUESSEL_ID.test(mein) ? db.beanspruche(konto.id, mein) : db.schluesselId(konto.id);
    if (sid !== mein)
      return json(res, 200, { ok: true, kennung: k, geraete, schluessel: false, schluesselDa: !!sid, aenderungen: [], bis: ab, mehr: false });
    if (geraete < 2 && ab > 0) db.bestaetige(konto.id, ab);
    return json(res, 200, { ok: true, kennung: k, geraete, schluessel: true, ...db.holeAenderungen(konto.id, ab) });
  }
  // Offene App: „neu“, sobald ein anderes Gerät etwas gesendet hat
  if (pfad === '/api/sync/live' && m === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-store',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.write('retry: 5000\n: hallo\n\n');
    const eintrag = { res, token: token! };
    const s = live.get(konto.id) ?? new Set();
    s.add(eintrag);
    live.set(konto.id, s);
    req.on('close', () => {
      s.delete(eintrag);
      if (!s.size) live.delete(konto.id);
    });
    return;
  }
  // iOS-App: Push-Token für den stillen Push (apns:<hex>, Debug-Builds apns-sandbox:<hex>)
  if (pfad === '/api/sync/push' && m === 'POST') {
    const d = await lies(req);
    const push = istText(d.push, 220) ? d.push.toLowerCase() : '';
    if (push && !apns.zerlege(push)) return fehler(res, 400, 'Token nicht lesbar');
    db.setzePush(token!, push || null);
    return json(res, 200, { ok: true });
  }
  if (pfad === '/api/sync/senden' && m === 'POST') {
    const d = await lies(req, MAX_BODY_IMPORT);
    const jetzt = Date.now();
    const k = db.kennung(konto.id);
    const geraete = db.geraete(konto.id);
    // Andere Kennung: das Gerät kennt den Stand nicht (geleert) und muss erst holen und dann alles senden.
    if (d.kennung !== k || geraete < 2 || !istText(d.schluessel, 20) || d.schluessel !== db.schluesselId(konto.id))
      return json(res, 200, { ok: true, kennung: k, geraete, angenommen: false });
    const liste = pruefeAenderungen(d.aenderungen, jetzt);
    if (!liste) return fehler(res, 400, 'Änderungen nicht lesbar');
    const r = db.nimmAenderungen(konto.id, liste);
    if (!r.ok) return fehler(res, 413, r.fehler);
    if (r.wert > 0) benachrichtige(konto.id, token!);
    return json(res, 200, { ok: true, kennung: k, geraete, angenommen: true });
  }

  // Push für die Web-App: Zeitplan ab „Backen beginnen“ (mit dem Abo dieses Browsers, oder ohne von einem
  // anderen Gerät des Kontos, z. B. der iOS-App; ohne Abo im Konto merkt der Server sich nichts); Beenden.
  if (pfad === '/api/timer' && m === 'POST') {
    const d = await lies(req);
    const abo = d.abo === undefined ? undefined : pruefeAbo(d.abo);
    const lauf = pruefeLauf(d.lauf, Date.now());
    if (abo === null || !lauf) return fehler(res, 400, 'Zeitplan oder Abo nicht lesbar');
    if (abo) db.merkeAbo(konto.id, abo);
    if (!db.abos(konto.id).length) return json(res, 200, { ok: true, gemerkt: false });
    faellig(lauf, Date.now()); // schon Vergangenes als gemeldet merken
    db.setzeBacklauf(konto.id, lauf);
    return json(res, 200, { ok: true });
  }
  if (pfad === '/api/push-abo' && m === 'POST') {
    const abo = pruefeAbo((await lies(req)).abo);
    if (!abo) return fehler(res, 400, 'Abo nicht lesbar');
    db.merkeAbo(konto.id, abo);
    return json(res, 200, { ok: true });
  }
  if (pfad === '/api/timer/stop' && m === 'POST') {
    db.loescheBacklauf(konto.id);
    return json(res, 200, { ok: true });
  }

  return fehler(res, 404, 'Unbekannt');
}

async function admin(req: IncomingMessage, res: ServerResponse, pfad: string, ip: string): Promise<void> {
  const m = req.method ?? 'GET';
  if (pfad === '/api/admin/anmelden' && m === 'POST') {
    if (!ADMIN_PASSWORD) return fehler(res, 403, 'Kein Admin-Passwort eingestellt (Add-on: admin_password)');
    if (gesperrt(ip)) return fehler(res, 429, 'Zu viele Versuche, bitte später noch einmal');
    const d = await lies(req);
    if (!passwortStimmt(d.passwort)) {
      fehlversuch(ip);
      return fehler(res, 400, 'Passwort falsch');
    }
    const t = randomBytes(32).toString('base64url');
    adminSitzungen.set(t, Date.now() + ADMIN_DAUER);
    return json(res, 200, { ok: true }, { 'Set-Cookie': cookie(ADMIN, t, ADMIN_DAUER / 1000, '/api/admin') });
  }
  if (!istAdmin(req)) return fehler(res, 401, 'Nicht als Admin angemeldet');

  if (pfad === '/api/admin/abmelden' && m === 'POST') {
    adminSitzungen.delete(cookies(req)[ADMIN]!);
    return json(res, 200, { ok: true }, { 'Set-Cookie': cookie(ADMIN, '', 0, '/api/admin') });
  }
  if (pfad === '/api/admin/uebersicht' && m === 'GET')
    return json(res, 200, { ok: true, ...db.uebersicht(), backlaeufe: db.anzahlBacklaeufe() });
  if (pfad === '/api/admin/einladungen' && m === 'POST') {
    const d = await lies(req);
    const notiz = istText(d.notiz, 80) ? d.notiz.trim() : '';
    return json(res, 200, { ok: true, ...db.neueEinladung(notiz) });
  }
  const ei = /^\/api\/admin\/einladungen\/(\d+)$/.exec(pfad);
  if (ei && m === 'DELETE') {
    db.loescheEinladung(Number(ei[1]));
    return json(res, 200, { ok: true });
  }
  const gc = /^\/api\/admin\/konten\/(\d+)\/geraetecode$/.exec(pfad);
  if (gc && m === 'POST') {
    if (!db.kontoExistiert(Number(gc[1]))) return fehler(res, 404, 'Konto nicht gefunden');
    return json(res, 200, { ok: true, ...db.neuerGeraetecode(Number(gc[1])) });
  }
  const si = /^\/api\/admin\/konten\/(\d+)\/sitzungen\/(\d+)$/.exec(pfad);
  if (si && m === 'DELETE') {
    if (!db.entferneSitzung(Number(si[1]), Number(si[2]))) return fehler(res, 404, 'Sitzung nicht gefunden');
    return json(res, 200, { ok: true });
  }
  const ko = /^\/api\/admin\/konten\/(\d+)$/.exec(pfad);
  if (ko && m === 'DELETE') {
    db.loescheKonto(Number(ko[1]));
    return json(res, 200, { ok: true });
  }
  return fehler(res, 404, 'Unbekannt');
}

createServer(async (req, res) => {
  const pfad = (req.url ?? '/').split('?')[0]!;
  try {
    if (pfad === '/healthz') return json(res, 200, { ok: true });
    if (pfad.startsWith('/api/')) return await api(req, res, pfad);
    if (req.method !== 'GET' && req.method !== 'HEAD') return fehler(res, 405, 'Nicht erlaubt');
    datei(req, res);
  } catch (err) {
    if (!res.headersSent) fehler(res, 400, 'Anfrage nicht lesbar');
    if (!(err instanceof SyntaxError) && String(err).indexOf('zu groß') < 0) console.warn('Fehler:', err);
  }
}).listen(PORT, () => console.log(`Sauerteig-Rechner auf Port ${PORT}`));

// Als PID 1 im Container beendet Node sich ohne Handler nicht bei SIGTERM (HA-Stopp, kaltes Backup)
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    db.schliesse();
    process.exit(0);
  });
}
