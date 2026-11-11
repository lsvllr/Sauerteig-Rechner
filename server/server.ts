// Server des eigenständigen Sauerteig-Rechners: liefert die App aus (dist/), verwaltet Konten und Rezepte (db.ts)
// und schickt die Erinnerungen des Back-Timers per Web-Push, sobald „Backen beginnen“ getippt wurde.
//
// Konten nur mit Einladungscode vom Admin (ADMIN_PASSWORD, Seite /admin). Wie in der Haushalt-App hat jedes Konto
// höchstens einen Backlauf, und die Meldungen gehen an alle Geräte des Kontos. Fällig wird nach denselben Regeln
// wie im Browser (faellig() aus src/gemeinsam/timer.ts). Der Backlauf liegt in der Datenbank und übersteht so einen
// Neustart. Den Zeitplan bekommt der Server über den Abgleich der Geräte (/api/timer/stand, src/abgleich.ts);
// /api/timer (POST) und /api/timer/stop bleiben für ältere, noch zwischengespeicherte Versionen der App.
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join, normalize } from 'node:path';
import webpush from 'web-push';
import { BEGINN, VORLAUF_WAHL, faellig, type Lauf } from '../src/gemeinsam/timer';
import * as db from './db';
import { alsLauf, kern, kernText } from '../src/laufKern';

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

const EINSTELLUNGEN = /^[a-zA-Z]{1,30}$/;
function pruefeRezept(v: unknown): Omit<db.RezeptZeile, 'id'> | null {
  const r = v as { name?: unknown; datum?: unknown; einstellungen?: unknown } | null;
  if (!r || !istText(r.name, 80) || !r.name.trim() || !istText(r.datum, 20)) return null;
  const e = r.einstellungen;
  if (!e || typeof e !== 'object' || Array.isArray(e)) return null;
  const aus: Record<string, string | number | boolean> = {};
  const eintraege = Object.entries(e);
  if (eintraege.length > 30) return null;
  for (const [k, w] of eintraege) {
    if (!EINSTELLUNGEN.test(k)) return null;
    if (typeof w === 'boolean' || istZahl(w) || istText(w, 40)) aus[k] = w;
    else return null;
  }
  return { name: r.name.trim(), datum: r.datum, einstellungen: aus };
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

setInterval(() => {
  tick().catch((err) => console.warn('Back-Timer:', err));
}, TAKT);

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

/** Altbestand aus dem Browser (vor den Konten) ins Konto übernehmen. */
function importiere(kontoId: number, v: unknown): number {
  if (!Array.isArray(v)) return 0;
  let n = 0;
  for (const r of v.slice(0, 200)) {
    const ok = pruefeRezept(r);
    if (!ok || db.anzahlRezepte(kontoId) >= db.MAX_REZEPTE) continue;
    db.fuegeRezeptHinzu(kontoId, ok);
    n++;
  }
  return n;
}

async function api(req: IncomingMessage, res: ServerResponse, pfad: string): Promise<void> {
  const m = req.method ?? 'GET';
  if (m !== 'GET' && !eigeneHerkunft(req)) return fehler(res, 403, 'Fremde Herkunft');
  if (m === 'POST' && !(req.headers['content-type'] ?? '').startsWith('application/json'))
    return fehler(res, 415, 'Nur JSON');
  const ip = clientIp(req);

  /* ---------- ohne Anmeldung ---------- */
  if (pfad === '/api/push-key' && m === 'GET') return json(res, 200, { key: schluessel.publicKey });

  if (pfad === '/api/registrieren' && m === 'POST') {
    if (gesperrt(ip)) return fehler(res, 429, 'Zu viele Versuche, bitte später noch einmal');
    const d = await lies(req, MAX_BODY_IMPORT);
    const name = pruefeName(d.name);
    if (!name) return fehler(res, 400, 'Bitte einen Namen mit 1–40 Zeichen wählen');
    if (!istText(d.code, 40)) return fehler(res, 400, 'Einladungscode fehlt');
    const r = db.registriere(d.code, name);
    if (!r.ok) {
      if (r.fehler.startsWith('Einladungscode')) fehlversuch(ip);
      return fehler(res, 400, r.fehler);
    }
    const uebernommen = importiere(r.wert.id, d.rezepte);
    console.log(`Neues Konto „${name}“ (${uebernommen} Rezepte übernommen)`);
    const token = db.neueSitzung(r.wert.id, geraet(req));
    return json(res, 200, { ok: true, name, uebernommen }, { 'Set-Cookie': sitzungsCookie(token) });
  }

  if (pfad === '/api/anmelden' && m === 'POST') {
    if (gesperrt(ip)) return fehler(res, 429, 'Zu viele Versuche, bitte später noch einmal');
    const d = await lies(req, MAX_BODY_IMPORT);
    const k = istText(d.code, 40) ? db.loeseGeraetecode(d.code) : null;
    if (!k) {
      fehlversuch(ip);
      return fehler(res, 400, 'Gerätecode ungültig oder abgelaufen');
    }
    const uebernommen = importiere(k.id, d.rezepte);
    const token = db.neueSitzung(k.id, geraet(req));
    return json(res, 200, { ok: true, name: k.name, uebernommen }, { 'Set-Cookie': sitzungsCookie(token) });
  }

  /* ---------- Admin ---------- */
  if (pfad.startsWith('/api/admin/')) return admin(req, res, pfad, ip);

  /* ---------- mit Anmeldung ---------- */
  const token = cookies(req)[SITZUNG];
  const konto = token ? db.kontoZuSitzung(token) : null;
  if (!konto) return fehler(res, 401, 'Nicht angemeldet');

  if (pfad === '/api/ich' && m === 'GET') return json(res, 200, { ok: true, name: konto.name });

  if (pfad === '/api/abmelden' && m === 'POST') {
    db.beendeSitzung(token!);
    const d = await lies(req);
    if (istText(d.endpoint, 1000)) db.vergissAbo(d.endpoint);
    return json(res, 200, { ok: true }, { 'Set-Cookie': cookie(SITZUNG, '', 0) });
  }

  if (pfad === '/api/geraetecode' && m === 'POST') return json(res, 200, { ok: true, ...db.neuerGeraetecode(konto.id) });

  if (pfad === '/api/rezepte' && m === 'GET') return json(res, 200, { ok: true, rezepte: db.rezepte(konto.id) });
  if (pfad === '/api/rezepte' && m === 'POST') {
    const r = pruefeRezept(await lies(req));
    if (!r) return fehler(res, 400, 'Rezept nicht lesbar');
    if (db.anzahlRezepte(konto.id) >= db.MAX_REZEPTE) return fehler(res, 400, 'Zu viele Rezepte');
    const id = db.fuegeRezeptHinzu(konto.id, r);
    return json(res, 200, { ok: true, id });
  }
  const rz = /^\/api\/rezepte\/(\d+)$/.exec(pfad);
  if (rz && m === 'DELETE') {
    return db.loescheRezept(konto.id, Number(rz[1])) ? json(res, 200, { ok: true }) : fehler(res, 404, 'Nicht gefunden');
  }

  if (pfad === '/api/timer' && m === 'POST') {
    const d = await lies(req);
    const abo = pruefeAbo(d.abo);
    const lauf = pruefeLauf(d.lauf, Date.now());
    if (!abo || !lauf) return fehler(res, 400, 'Zeitplan oder Abo nicht lesbar');
    db.merkeAbo(konto.id, abo);
    faellig(lauf, Date.now()); // schon Vergangenes als gemeldet merken
    db.setzeBacklauf(konto.id, lauf);
    return json(res, 200, { ok: true });
  }
  // Abgleich des Back-Timers zwischen den Geräten (src/abgleich.ts): es gilt die neueste Änderung.
  if (pfad === '/api/timer' && m === 'GET') return json(res, 200, { ok: true, ...db.timerStand(konto.id) });
  if (pfad === '/api/timer/stand' && m === 'POST') {
    const d = await lies(req);
    const jetzt = Date.now();
    const lauf = alsLauf(d.lauf ?? null);
    if (lauf === undefined || !istZahl(d.geaendert) || d.geaendert <= 0) return fehler(res, 400, 'Timer nicht lesbar');
    if (lauf && lauf.schritte.some((s) => Math.abs(s.at - jetzt) > 7 * 24 * 3600_000))
      return fehler(res, 400, 'Timer nicht lesbar');
    const geaendert = Math.min(d.geaendert, jetzt + 60_000); // vorgehende Uhr des Geräts gewinnt nicht ewig
    const alt = db.timerStand(konto.id);
    if (geaendert <= alt.geaendert) return json(res, 200, { ok: true, ...alt }); // anderes Gerät war neuer
    db.setzeTimerStand(konto.id, kern(lauf), geaendert);
    // Push nur neu planen, wenn sich der Zeitplan geändert hat (sonst kämen Meldungen doppelt oder gar nicht)
    const vorher = alsLauf(alt.lauf);
    if (kernText(lauf) !== kernText(vorher ?? null)) {
      const push = lauf?.phase === 'backen' ? pruefeLauf(lauf, jetzt) : null;
      if (push) {
        faellig(push, jetzt); // schon Vergangenes als gemeldet merken
        db.setzeBacklauf(konto.id, push);
      } else db.loescheBacklauf(konto.id);
    }
    return json(res, 200, { ok: true, lauf: kern(lauf), geaendert });
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
