// Versand an Apple Push Notification service (APNs) für die iOS-App: Live-Aktivität des Back-Timers weiterschalten
// und stiller Push „es gibt Neues“ für den Abgleich (weckt die App kurz, nichts sichtbar). Mitteilungen plant die
// App selbst (lokal), Web-Push läuft weiter über web-push.
//
// Einrichtung (developer.apple.com > Keys > „Apple Push Notifications service“):
//   APNS_KEY_ID    Key ID des Schlüssels
//   APNS_TEAM_ID   Team ID
//   APNS_TOPIC     Bundle-ID der App (Standard de.eliasvollrath.sauerteig)
//   APNS_KEY       Inhalt der .p8-Datei (oder nur der Base64-Teil); sonst Datei APNS_KEY_FILE (Standard DATA_DIR/apns.p8)
// Ohne diese Werte bleibt APNs aus: Die Aktivität schaltet dann nur weiter, wenn die App läuft.
//
// Versand über HTTP/2 (node:http2) mit Anbieter-Token (JWT, ES256), keine weitere Abhängigkeit. Fehler werden
// geloggt und geschluckt.
import { createPrivateKey, sign, type KeyObject } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { connect, type ClientHttp2Session } from 'node:http2';
import { join } from 'node:path';

const KEY_ID = (process.env.APNS_KEY_ID ?? '').trim();
const TEAM_ID = (process.env.APNS_TEAM_ID ?? '').trim();
export const TOPIC = (process.env.APNS_TOPIC ?? '').trim() || 'de.eliasvollrath.sauerteig';
const DATA_DIR = process.env.DATA_DIR ?? join(process.cwd(), 'data');
const KEY_FILE = (process.env.APNS_KEY_FILE ?? '').trim() || join(DATA_DIR, 'apns.p8');

const HOSTS = { prod: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' } as const;
/** Apple: Token höchstens 60 Minuten alt, frühestens alle 20 Minuten neu. */
const JWT_MAX_ALTER = 50 * 60_000;
const TOKEN = /^[0-9a-f]{32,200}$/;

export type Ergebnis = 'ok' | 'gone' | 'error';

/** `apns:<hex>` (Release) bzw. `apns-sandbox:<hex>` (Debug-Build aus Xcode) → Token und Server; sonst null. */
export function zerlege(endpoint: string): { token: string; sandbox: boolean } | null {
  const sandbox = endpoint.startsWith('apns-sandbox:');
  if (!sandbox && !endpoint.startsWith('apns:')) return null;
  const token = endpoint.slice(sandbox ? 13 : 5).toLowerCase();
  return TOKEN.test(token) ? { token, sandbox } : null;
}

let schluessel: KeyObject | null | undefined;
function ladeSchluessel(): KeyObject | null {
  if (schluessel !== undefined) return schluessel;
  let pem = (process.env.APNS_KEY ?? '').trim();
  if (!pem && existsSync(KEY_FILE)) pem = readFileSync(KEY_FILE, 'utf8').trim();
  if (!pem) return (schluessel = null);
  pem = pem.replace(/\\n/g, '\n');
  if (!pem.includes('BEGIN')) pem = `-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----\n`;
  try {
    schluessel = createPrivateKey(pem);
  } catch (err) {
    console.warn('APNs-Schlüssel nicht lesbar:', String(err));
    schluessel = null;
  }
  return schluessel;
}

export function aktiv(): boolean {
  return !!(KEY_ID && TEAM_ID && TOPIC) && ladeSchluessel() !== null;
}

const b64 = (b: Buffer | string) => Buffer.from(b).toString('base64url');

let jwt = { token: '', erstellt: 0 };
function anbieterToken(): string | null {
  const jetzt = Date.now();
  if (jwt.token && jetzt - jwt.erstellt < JWT_MAX_ALTER) return jwt.token;
  const key = ladeSchluessel();
  if (!key) return null;
  const kopf = b64(JSON.stringify({ alg: 'ES256', kid: KEY_ID }));
  const inhalt = b64(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(jetzt / 1000) }));
  const sig = sign('sha256', Buffer.from(`${kopf}.${inhalt}`), { key, dsaEncoding: 'ieee-p1363' });
  jwt = { token: `${kopf}.${inhalt}.${b64(sig)}`, erstellt: jetzt };
  return jwt.token;
}

const sitzungen = new Map<string, ClientHttp2Session>();
function sitzung(host: string): ClientHttp2Session {
  const alt = sitzungen.get(host);
  if (alt && !alt.closed && !alt.destroyed) return alt;
  const s = connect(host);
  s.on('error', () => sitzungen.delete(host));
  s.on('close', () => sitzungen.delete(host));
  // Ohne laufende Anfragen soll die Verbindung den Prozess nicht wach halten.
  s.unref();
  sitzungen.set(host, s);
  return s;
}

function post(endpoint: string, kopf: Record<string, string>, nutzlast: unknown): Promise<Ergebnis> {
  const z = zerlege(endpoint);
  if (!z) return Promise.resolve('gone');
  const token = aktiv() ? anbieterToken() : null;
  if (!token) return Promise.resolve('error');
  const host = z.sandbox ? HOSTS.sandbox : HOSTS.prod;
  return new Promise((fertig) => {
    let s: ClientHttp2Session;
    try {
      s = sitzung(host);
    } catch (err) {
      console.warn('APNs nicht erreichbar:', String(err));
      return fertig('error');
    }
    const req = s.request({
      ':method': 'POST',
      ':path': `/3/device/${z.token}`,
      authorization: `bearer ${token}`,
      'content-type': 'application/json',
      ...kopf,
    });
    req.setTimeout(10_000, () => req.close());
    let status = 0;
    let text = '';
    req.on('response', (h) => (status = Number(h[':status'] ?? 0)));
    req.setEncoding('utf8');
    req.on('data', (d: string) => (text += d));
    req.on('error', (err) => {
      console.warn('APNs:', String(err));
      fertig('error');
    });
    req.on('close', () => {
      if (status === 200) return fertig('ok');
      let grund = '';
      try {
        grund = (JSON.parse(text) as { reason?: string }).reason ?? '';
      } catch {
        /* kein JSON */
      }
      if (status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic', 'ExpiredToken'].includes(grund))
        return fertig('gone');
      if (status === 403 && (grund === 'ExpiredProviderToken' || grund === 'InvalidProviderToken'))
        jwt = { token: '', erstellt: 0 };
      if (status) console.warn(`APNs ${status}: ${grund || text.slice(0, 200)}`);
      fertig('error');
    });
    req.end(JSON.stringify(nutzlast));
  });
}

/** Live-Aktivität weiterschalten (`update`) oder beenden (`end`). Zeiten `stale`/`dismissal` in Sekunden. */
export function sendeAktivitaet(
  endpoint: string,
  event: 'update' | 'end',
  state: unknown,
  stale?: number,
  dismissal?: number,
): Promise<Ergebnis> {
  const jetzt = Math.floor(Date.now() / 1000);
  const aps: Record<string, unknown> = { timestamp: jetzt, event, 'content-state': state };
  if (stale !== undefined) aps['stale-date'] = Math.floor(stale);
  if (event === 'end' && dismissal !== undefined) aps['dismissal-date'] = Math.floor(dismissal);
  return post(
    endpoint,
    {
      'apns-topic': `${TOPIC}.push-type.liveactivity`,
      'apns-push-type': 'liveactivity',
      'apns-priority': '10',
      'apns-expiration': String(jetzt + 3600),
    },
    { aps },
  );
}

/** Stiller Push: weckt die App im Hintergrund, damit sie Änderungen der anderen Geräte holt. Ohne Inhalt. */
export function sendeStill(endpoint: string): Promise<Ergebnis> {
  const jetzt = Math.floor(Date.now() / 1000);
  return post(
    endpoint,
    {
      'apns-topic': TOPIC,
      'apns-push-type': 'background',
      'apns-priority': '5',
      'apns-expiration': String(jetzt + 6 * 3600),
      'apns-collapse-id': 'abgleich',
    },
    { aps: { 'content-available': 1 } },
  );
}
