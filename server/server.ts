// Server des eigenständigen Sauerteig-Rechners: liefert die App aus (dist/) und schickt die Erinnerungen des
// Back-Timers per Web-Push, sobald „Backen beginnen“ getippt wurde. Ohne Konten: jedes Gerät meldet sein Push-Abo
// mit dem Zeitplan an und bekommt nur selbst Nachrichten. Fällig wird nach denselben Regeln wie im Browser
// (faellig() aus src/gemeinsam/timer.ts).
//
// Läuft als Home-Assistant-Add-on dauerhaft. Die Zeitpläne liegen nur im Speicher:
// Nach einem Neustart meldet die App sie beim nächsten Öffnen erneut (setzeFernPush in timer.ts).
import { createHash } from 'node:crypto';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join, normalize } from 'node:path';
import webpush, { type PushSubscription } from 'web-push';
import { BEGINN, VORLAUF_WAHL, faellig, type Lauf } from '../src/gemeinsam/timer';

const PORT = Number(process.env.PORT ?? 8080);
const DIST = process.env.DIST ?? join(process.cwd(), 'dist');
const APP_URL = (process.env.APP_URL ?? 'https://sauerteig.vollrath.app').replace(/\/$/, '');
const TAKT = 10_000;
const MAX_TIMER = 500;
const MAX_BODY = 16_000;

let schluessel = { publicKey: process.env.VAPID_PUBLIC_KEY ?? '', privateKey: process.env.VAPID_PRIVATE_KEY ?? '' };
if (!schluessel.publicKey || !schluessel.privateKey) {
  // Ohne Secret: Schlüssel nur bis zum Neustart; die App meldet sich dann mit neuem Abo an.
  schluessel = webpush.generateVAPIDKeys();
  console.warn('VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY fehlen: Schlüssel gelten nur bis zum Neustart.');
}
webpush.setVapidDetails(APP_URL, schluessel.publicKey, schluessel.privateKey);

interface Eintrag {
  abo: PushSubscription;
  lauf: Lauf;
}
const timer = new Map<string, Eintrag>();
const id = (endpoint: string) => createHash('sha256').update(endpoint).digest('hex');

/* ------------------------------------------------------------------ Prüfen */

const istText = (v: unknown, max: number): v is string => typeof v === 'string' && v.length <= max;
const istZahl = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

/** Nur die Push-Dienste der Browser (sonst ließe sich der Server an beliebige Adressen schicken). */
const PUSH_DIENSTE = /^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|([a-z0-9-]+\.)*push\.apple\.com|([a-z0-9-]+\.)*notify\.windows\.com)$/;

function pruefeAbo(v: unknown): PushSubscription | null {
  const a = v as PushSubscription | null;
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

/* ------------------------------------------------------------------ Melden */

function offen(l: Lauf): boolean {
  return l.schritte.some((_, i) => i >= BEGINN && !l.gemeldet.includes(`${i}:jetzt`));
}

async function tick(): Promise<void> {
  const jetzt = Date.now();
  for (const [k, e] of timer) {
    for (const m of faellig(e.lauf, jetzt)) {
      try {
        await webpush.sendNotification(
          e.abo,
          JSON.stringify({ title: m.titel, body: m.text, url: '/', tag: 'sauerteig' }),
          { TTL: m.key.endsWith(':bald') ? e.lauf.vorlauf * 60 : 1800 },
        );
        console.log(`Push ${m.key}: ${m.titel}`);
      } catch (err) {
        const status = (err as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          console.log(`Push ${m.key}: Abo abgelaufen (${status}), Timer entfernt`);
          timer.delete(k);
        } else console.warn(`Push ${m.key} fehlgeschlagen:`, status ?? err);
      }
    }
    if (!offen(e.lauf)) timer.delete(k);
  }
}

setInterval(() => {
  tick().catch((err) => console.warn('Back-Timer:', err));
}, TAKT);

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

function json(res: ServerResponse, status: number, daten: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(daten));
}

async function lies(req: IncomingMessage): Promise<unknown> {
  let text = '';
  for await (const teil of req) {
    text += teil;
    if (text.length > MAX_BODY) throw new Error('zu groß');
  }
  return JSON.parse(text || '{}');
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

createServer(async (req, res) => {
  const pfad = (req.url ?? '/').split('?')[0];
  try {
    if (pfad === '/healthz') return json(res, 200, { ok: true });
    if (pfad === '/api/push-key' && req.method === 'GET') return json(res, 200, { key: schluessel.publicKey });
    if (pfad === '/api/timer' && req.method === 'POST') {
      const d = (await lies(req)) as { abo?: unknown; lauf?: unknown };
      const abo = pruefeAbo(d.abo);
      const lauf = pruefeLauf(d.lauf, Date.now());
      if (!abo || !lauf) return json(res, 400, { ok: false, error: 'Zeitplan oder Abo nicht lesbar' });
      const k = id(abo.endpoint);
      if (!timer.has(k) && timer.size >= MAX_TIMER) return json(res, 503, { ok: false, error: 'voll' });
      faellig(lauf, Date.now()); // schon Vergangenes als gemeldet merken
      timer.set(k, { abo, lauf });
      return json(res, 200, { ok: true });
    }
    if (pfad === '/api/timer/stop' && req.method === 'POST') {
      const d = (await lies(req)) as { endpoint?: unknown };
      if (typeof d.endpoint === 'string') timer.delete(id(d.endpoint));
      return json(res, 200, { ok: true });
    }
    if (pfad.startsWith('/api/')) return json(res, 404, { ok: false });
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { ok: false });
    datei(req, res);
  } catch {
    json(res, 400, { ok: false });
  }
}).listen(PORT, () => console.log(`Sauerteig-Rechner auf Port ${PORT}`));
