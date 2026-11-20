// Datenbank des Sauerteig-Rechners (SQLite, in Node eingebaut). Liegt in DATA_DIR (Add-on: /data, in den
// HA-Backups), lokal in ./data.
//
// Die Daten der Nutzer (Rezepte, Füttern, Back-Timer) liegen auf den Geräten. Der Server speichert nur, was er
// braucht: Konten, Sitzungen, Codes, Push-Abos und den Zeitplan für Push/Weckdienst. Rezepte usw. kommen nur in
// den Abgleich (Tabelle `abgleich`), solange ein Konto mindestens zwei Geräte hat; fällt es auf eins zurück, ist
// alles davon wieder weg.
//
// Konten entstehen nur über einen Einladungscode des Admins (ein Code = ein Konto). Ohne Passwort: ein Gerät ist
// über ein Sitzungs-Cookie angemeldet; weitere Geräte kommen über einen kurzlebigen Gerätecode dazu, den das
// Konto selbst oder der Admin erzeugt. Codes und Sitzungen stehen nur als SHA-256 in der Datenbank.
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { Lauf } from '../src/gemeinsam/timer';

const DATA_DIR = process.env.DATA_DIR ?? join(process.cwd(), 'data');
mkdirSync(DATA_DIR, { recursive: true });

const db = new DatabaseSync(join(DATA_DIR, 'sauerteig.db'));
db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;
  PRAGMA busy_timeout = 5000;

  CREATE TABLE IF NOT EXISTS konten (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    erstellt INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS einladungen (
    id INTEGER PRIMARY KEY,
    code_hash TEXT NOT NULL UNIQUE,
    notiz TEXT NOT NULL DEFAULT '',
    erstellt INTEGER NOT NULL,
    gueltig_bis INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS geraetecodes (
    code_hash TEXT PRIMARY KEY,
    konto_id INTEGER NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
    gueltig_bis INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS sitzungen (
    token_hash TEXT PRIMARY KEY,
    konto_id INTEGER NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
    erstellt INTEGER NOT NULL,
    zuletzt INTEGER NOT NULL,
    geraet TEXT NOT NULL DEFAULT ''
  );
  CREATE TABLE IF NOT EXISTS push_abos (
    endpoint TEXT PRIMARY KEY,
    konto_id INTEGER NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
    p256dh TEXT NOT NULL,
    auth TEXT NOT NULL,
    erstellt INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS backlaeufe (
    konto_id INTEGER PRIMARY KEY REFERENCES konten(id) ON DELETE CASCADE,
    lauf TEXT NOT NULL
  );
  -- Weckdienst der iOS-App: Push-Token einer Live-Aktivität, Zeiten der Back-Schritte (JSON, ms), zuletzt
  -- gemeldeter Schritt. Kein Konto, keine Rezeptdaten (server/wecker.ts).
  CREATE TABLE IF NOT EXISTS wecker (
    token TEXT PRIMARY KEY,
    zeiten TEXT NOT NULL,
    gesendet INTEGER NOT NULL,
    erstellt INTEGER NOT NULL
  );
  -- Abgleich zwischen den Geräten eines Kontos (nur ab zwei Geräten): Änderungen {tabelle, uid, daten, geloescht,
  -- zeit} wie auf den Geräten, nr wächst nur (auch nach Löschen). Kennung je Konto: neu, wenn geleert.
  CREATE TABLE IF NOT EXISTS abgleich (
    nr INTEGER PRIMARY KEY AUTOINCREMENT,
    konto_id INTEGER NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
    tabelle TEXT NOT NULL,
    uid TEXT NOT NULL,
    zeit TEXT NOT NULL,
    daten TEXT NOT NULL,
    geloescht INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS abgleich_konto ON abgleich(konto_id, nr);
  CREATE UNIQUE INDEX IF NOT EXISTS abgleich_zeile ON abgleich(konto_id, tabelle, uid, zeit);
  CREATE TABLE IF NOT EXISTS abgleich_kennung (
    konto_id INTEGER PRIMARY KEY REFERENCES konten(id) ON DELETE CASCADE,
    kennung TEXT NOT NULL
  );
`);

/** Spalten, die später dazukamen. */
function spalte(tabelle: string, name: string, typ: string): void {
  const da = (db.prepare(`PRAGMA table_info(${tabelle})`).all() as { name: string }[]).some((c) => c.name === name);
  if (!da) db.exec(`ALTER TABLE ${tabelle} ADD COLUMN ${name} ${typ}`);
}
// Kennung des Schlüssels, mit dem die Geräte des Kontos verschlüsseln (SHA-256 des Schlüssels, gekürzt). Der
// Schlüssel selbst kommt nie an den Server.
spalte('abgleich_kennung', 'schluessel', 'TEXT');
// Gerätecode: Schlüssel des Kontos, verpackt mit dem geheimen Teil des Codes, den der Server nie sieht.
spalte('geraetecodes', 'schluessel', 'TEXT');
// Push-Token der iOS-App für den stillen Push „es gibt Neues“ (apns:<hex>).
spalte('sitzungen', 'push', 'TEXT');

/** Beim Beenden: WAL zurückschreiben, damit die Sicherung nur sauerteig.db braucht. */
export function schliesse(): void {
  try {
    db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    db.close();
  } catch {
    /* schon zu */
  }
}

/* ------------------------------------------------------------------ Hilfen */

export const hash = (s: string) => createHash('sha256').update(s).digest('hex');

/** Ohne leicht verwechselbare Zeichen (0/O, 1/I/L). */
const ZEICHEN = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function code(laenge: number): string {
  let s = '';
  for (let i = 0; i < laenge; i++) s += ZEICHEN[randomInt(ZEICHEN.length)];
  return s.replace(/(.{4})(?=.)/g, '$1-');
}
/** Eingabe vereinheitlichen: Groß, ohne Leerzeichen und Bindestriche, dann wie erzeugt gruppieren. */
export function normiereCode(s: string): string {
  return s.toUpperCase().replace(/[^A-Z0-9]/g, '').replace(/(.{4})(?=.)/g, '$1-');
}

const TAG = 24 * 3600_000;
export const EINLADUNG_GUELTIG = 14 * TAG;
export const GERAETECODE_GUELTIG = 15 * 60_000;

const alle = <T>(sql: string, ...p: (string | number | null)[]) => db.prepare(sql).all(...p) as T[];
const eine = <T>(sql: string, ...p: (string | number | null)[]) => db.prepare(sql).get(...p) as T | undefined;
const tue = (sql: string, ...p: (string | number | null)[]) => db.prepare(sql).run(...p);

function inTransaktion<T>(f: () => T): T {
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = f();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

/* ------------------------------------------------------------------ Konten */

export interface Konto {
  id: number;
  name: string;
}

export function neueSitzung(kontoId: number, geraet: string): string {
  const token = randomBytes(32).toString('base64url');
  const jetzt = Date.now();
  tue('INSERT INTO sitzungen (token_hash, konto_id, erstellt, zuletzt, geraet) VALUES (?, ?, ?, ?, ?)', hash(token), kontoId, jetzt, jetzt, geraet.slice(0, 120));
  return token;
}

export function kontoZuSitzung(token: string): Konto | null {
  const h = hash(token);
  const k = eine<Konto & { zuletzt: number }>(
    'SELECT k.id, k.name, s.zuletzt FROM sitzungen s JOIN konten k ON k.id = s.konto_id WHERE s.token_hash = ?',
    h,
  );
  if (!k) return null;
  // „Zuletzt gesehen“ höchstens einmal pro Stunde schreiben
  if (Date.now() - k.zuletzt > 3600_000) tue('UPDATE sitzungen SET zuletzt = ? WHERE token_hash = ?', Date.now(), h);
  return { id: k.id, name: k.name };
}

/** Gerät abmelden. Bleibt danach nur ein Gerät, braucht das Konto keinen Abgleich mehr. */
export function beendeSitzung(token: string): void {
  const s = eine<{ konto_id: number }>('SELECT konto_id FROM sitzungen WHERE token_hash = ?', hash(token));
  tue('DELETE FROM sitzungen WHERE token_hash = ?', hash(token));
  if (s && geraete(s.konto_id) < 2) leereAbgleich(s.konto_id);
}

/** Sitzungen, die ein halbes Jahr nicht mehr kamen (Gerät weg, App gelöscht), zählen nicht mehr als Gerät. */
export function raeumeSitzungenAuf(jetzt = Date.now()): void {
  const alt = alle<{ konto_id: number }>('SELECT DISTINCT konto_id FROM sitzungen WHERE zuletzt < ?', jetzt - 180 * TAG);
  tue('DELETE FROM sitzungen WHERE zuletzt < ?', jetzt - 180 * TAG);
  for (const { konto_id } of alt) if (geraete(konto_id) < 2) leereAbgleich(konto_id);
}

export interface Sitzung { id: number; geraet: string; erstellt: number; zuletzt: number; push: number; diese: number }

/** Sitzungen (= verknüpfte Geräte) eines Kontos, für den Admin und für das Konto selbst. id = rowid, der Token-Hash
 * bleibt im Server; `diese`: die Sitzung zu `token` (das fragende Gerät). `zuletzt` höchstens stündlich genau. */
export function sitzungenVon(kontoId: number, token = ''): Sitzung[] {
  return alle<Sitzung>(
    `SELECT rowid AS id, geraet, erstellt, zuletzt, (push IS NOT NULL) AS push, (token_hash = ?) AS diese
       FROM sitzungen WHERE konto_id = ? ORDER BY zuletzt DESC`,
    token ? hash(token) : '',
    kontoId,
  );
}

/** Eine Sitzung entfernen (Admin oder ein anderes Gerät des Kontos): das Gerät ist abgemeldet und muss neu verknüpft werden. */
export function entferneSitzung(kontoId: number, id: number): boolean {
  const n = tue('DELETE FROM sitzungen WHERE rowid = ? AND konto_id = ?', id, kontoId).changes;
  if (n && geraete(kontoId) < 2) leereAbgleich(kontoId);
  return n > 0;
}

export function geraete(kontoId: number): number {
  return eine<{ n: number }>('SELECT COUNT(*) AS n FROM sitzungen WHERE konto_id = ?', kontoId)!.n;
}

export type Ergebnis<T> = { ok: true; wert: T } | { ok: false; fehler: string };

/** Einladung einlösen: legt genau ein Konto an und verbraucht den Code. */
export function registriere(codeEingabe: string, name: string): Ergebnis<Konto> {
  const h = hash(normiereCode(codeEingabe));
  return inTransaktion(() => {
    const e = eine<{ id: number; gueltig_bis: number }>('SELECT id, gueltig_bis FROM einladungen WHERE code_hash = ?', h);
    if (!e || e.gueltig_bis < Date.now()) return { ok: false, fehler: 'Einladungscode ungültig oder abgelaufen' };
    if (eine('SELECT 1 FROM konten WHERE name = ?', name)) return { ok: false, fehler: 'Name schon vergeben' };
    const r = tue('INSERT INTO konten (name, erstellt) VALUES (?, ?)', name, Date.now());
    tue('DELETE FROM einladungen WHERE id = ?', e.id);
    return { ok: true, wert: { id: Number(r.lastInsertRowid), name } };
  });
}

/** Gerätecode einlösen (einmalig). `nurKonto`: nur für dieses Konto (Schlüssel holen auf einem angemeldeten Gerät). */
export function loeseGeraetecode(codeEingabe: string, nurKonto?: number): (Konto & { schluessel: string | null }) | null {
  const h = hash(normiereCode(codeEingabe));
  return inTransaktion(() => {
    const k = eine<Konto & { gueltig_bis: number; schluessel: string | null }>(
      'SELECT k.id, k.name, g.gueltig_bis, g.schluessel FROM geraetecodes g JOIN konten k ON k.id = g.konto_id WHERE g.code_hash = ?',
      h,
    );
    if (!k || (nurKonto !== undefined && k.id !== nurKonto)) return null;
    tue('DELETE FROM geraetecodes WHERE code_hash = ?', h);
    return k.gueltig_bis >= Date.now() ? { id: k.id, name: k.name, schluessel: k.schluessel } : null;
  });
}

export function neuerGeraetecode(kontoId: number, schluessel: string | null = null): { code: string; gueltigBis: number } {
  const c = code(8);
  const gueltigBis = Date.now() + GERAETECODE_GUELTIG;
  tue('DELETE FROM geraetecodes WHERE gueltig_bis < ?', Date.now());
  tue('INSERT INTO geraetecodes (code_hash, konto_id, gueltig_bis, schluessel) VALUES (?, ?, ?, ?)', hash(c), kontoId, gueltigBis, schluessel);
  return { code: c, gueltigBis };
}

/* -------------------------------------------------- stiller Push (iOS-App) */

export function setzePush(token: string, push: string | null): void {
  tue('UPDATE sitzungen SET push = NULL WHERE push = ?', push);
  tue('UPDATE sitzungen SET push = ? WHERE token_hash = ?', push, hash(token));
}

/** Push-Ziele der anderen Geräte des Kontos. */
export function pushZiele(kontoId: number, ausserToken: string): string[] {
  return alle<{ push: string }>(
    'SELECT push FROM sitzungen WHERE konto_id = ? AND token_hash != ? AND push IS NOT NULL',
    kontoId,
    hash(ausserToken),
  ).map((z) => z.push);
}

export function vergissPushZiel(push: string): void {
  tue('UPDATE sitzungen SET push = NULL WHERE push = ?', push);
}

/* ---------------------------------------------------------------- Abgleich */

export interface Aenderung {
  tabelle: string;
  uid: string;
  daten: Record<string, unknown>;
  geloescht: boolean;
  zeit: string;
}

export const MAX_ABGLEICH = 20_000;

export function kennung(kontoId: number): string {
  const k = eine<{ kennung: string }>('SELECT kennung FROM abgleich_kennung WHERE konto_id = ?', kontoId);
  if (k) return k.kennung;
  const neu = randomBytes(9).toString('base64url');
  tue('INSERT INTO abgleich_kennung (konto_id, kennung) VALUES (?, ?)', kontoId, neu);
  return neu;
}

/** Kennung des Schlüssels; null, solange kein Gerät einen angemeldet hat. */
export function schluesselId(kontoId: number): string | null {
  kennung(kontoId);
  return eine<{ schluessel: string | null }>('SELECT schluessel FROM abgleich_kennung WHERE konto_id = ?', kontoId)!.schluessel;
}

/** Erstes Gerät mit Schlüssel legt ihn für das Konto fest; danach nur noch vergleichen. */
export function beanspruche(kontoId: number, id: string): string {
  kennung(kontoId);
  tue('UPDATE abgleich_kennung SET schluessel = ? WHERE konto_id = ? AND schluessel IS NULL', id, kontoId);
  return schluesselId(kontoId)!;
}

/** Alles vergessen und neue Kennung (auch der Schlüssel gilt dann neu): Die Geräte merken daran, dass sie beim nächsten Mal alles senden müssen. */
export function leereAbgleich(kontoId: number): void {
  tue('DELETE FROM abgleich WHERE konto_id = ?', kontoId);
  tue('DELETE FROM abgleich_kennung WHERE konto_id = ?', kontoId);
}

/** Änderungen nach `ab`, höchstens `max`. */
export function holeAenderungen(kontoId: number, ab: number, max = 500) {
  const z = alle<{ nr: number; tabelle: string; uid: string; zeit: string; daten: string; geloescht: number }>(
    'SELECT nr, tabelle, uid, zeit, daten, geloescht FROM abgleich WHERE konto_id = ? AND nr > ? ORDER BY nr LIMIT ?',
    kontoId,
    ab,
    max + 1,
  );
  const mehr = z.length > max;
  const seite = z.slice(0, max);
  const letzte = eine<{ n: number | null }>('SELECT MAX(nr) AS n FROM abgleich WHERE konto_id = ?', kontoId)!.n ?? 0;
  return {
    aenderungen: seite.map((a) => ({
      nr: a.nr,
      tabelle: a.tabelle,
      uid: a.uid,
      zeit: a.zeit,
      daten: JSON.parse(a.daten) as Record<string, unknown>,
      geloescht: a.geloescht === 1,
    })),
    bis: seite.length ? seite[seite.length - 1]!.nr : Math.max(ab, 0),
    letzte,
    mehr,
  };
}

/** Eigene Änderungen eines Geräts aufnehmen. Gleiche Zeile mit gleicher Zeit nur einmal (Wiederholung, oder ein
 * Gerät schickt beim Einstieg alles); Löschen ersetzt alles davor. */
export function nimmAenderungen(kontoId: number, liste: Aenderung[]): Ergebnis<number> {
  return inTransaktion(() => {
    const n = eine<{ n: number }>('SELECT COUNT(*) AS n FROM abgleich WHERE konto_id = ?', kontoId)!.n;
    if (n + liste.length > MAX_ABGLEICH) return { ok: false, fehler: 'Zu viele Daten im Abgleich' };
    let neu = 0;
    for (const a of liste) {
      const tot = eine(
        'SELECT 1 FROM abgleich WHERE konto_id = ? AND tabelle = ? AND uid = ? AND geloescht = 1',
        kontoId,
        a.tabelle,
        a.uid,
      );
      if (tot) continue;
      if (a.geloescht) tue('DELETE FROM abgleich WHERE konto_id = ? AND tabelle = ? AND uid = ?', kontoId, a.tabelle, a.uid);
      neu += Number(
        tue(
          'INSERT OR IGNORE INTO abgleich (konto_id, tabelle, uid, zeit, daten, geloescht) VALUES (?, ?, ?, ?, ?, ?)',
          kontoId,
          a.tabelle,
          a.uid,
          a.zeit,
          JSON.stringify(a.geloescht ? {} : a.daten),
          a.geloescht ? 1 : 0,
        ).changes,
      );
    }
    return { ok: true, wert: neu };
  });
}

/** Nur ein Gerät: Was es bis `bis` geholt hat, braucht der Server nicht mehr (z. B. übernommene alte Rezepte). */
export function bestaetige(kontoId: number, bis: number): void {
  tue('DELETE FROM abgleich WHERE konto_id = ? AND nr <= ?', kontoId, bis);
}

/** Einmalig: Rezepte und Timer-Stand aus der Zeit, als sie am Server lagen, in den Abgleich; dort holt sie das
 * nächste Gerät des Kontos ab, danach sind sie am Server weg (bestaetige). Gleiche uid wie in src/speicher.ts. */
function uebernimmAltbestand(): void {
  const da = (t: string) => !!eine("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", t);
  if (da('rezepte')) {
    inTransaktion(() => {
      const r = alle<{ id: number; konto_id: number; name: string; datum: string; einstellungen: string; erstellt: number }>(
        'SELECT id, konto_id, name, datum, einstellungen, erstellt FROM rezepte',
      );
      for (const z of r) {
        const zeit = `${String(z.erstellt).padStart(13, '0')}-0000-server0000`;
        tue(
          'INSERT OR IGNORE INTO abgleich (konto_id, tabelle, uid, zeit, daten, geloescht) VALUES (?, ?, ?, ?, ?, 0)',
          z.konto_id,
          'rezept',
          altRezeptUid(z.id),
          zeit,
          JSON.stringify({ name: z.name, datum: z.datum, einstellungen: z.einstellungen }),
        );
      }
      db.exec('DROP TABLE rezepte');
      if (r.length) console.log(`${r.length} Rezepte vom Server in den Abgleich übernommen`);
    });
  }
  if (da('timer_staende')) db.exec('DROP TABLE timer_staende');
}

/** uid eines Rezepts, das früher am Server lag (Zahl-ID): auf allen Geräten gleich, damit nichts doppelt kommt. */
export const altRezeptUid = (id: number) => `00000000-0000-4000-8000-${id.toString(16).padStart(12, '0')}`;

uebernimmAltbestand();
raeumeSitzungenAuf();

/* -------------------------------------------------------- Push und Backlauf */

export interface Abo {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export function merkeAbo(kontoId: number, a: Abo): void {
  // Ein Gerät gehört immer zum zuletzt angemeldeten Konto
  tue(
    `INSERT INTO push_abos VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(endpoint) DO UPDATE SET konto_id = excluded.konto_id, p256dh = excluded.p256dh, auth = excluded.auth`,
    a.endpoint,
    kontoId,
    a.keys.p256dh,
    a.keys.auth,
    Date.now(),
  );
}

export function abos(kontoId: number): Abo[] {
  return alle<{ endpoint: string; p256dh: string; auth: string }>(
    'SELECT endpoint, p256dh, auth FROM push_abos WHERE konto_id = ?',
    kontoId,
  ).map((a) => ({ endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth } }));
}

export function vergissAbo(endpoint: string): void {
  tue('DELETE FROM push_abos WHERE endpoint = ?', endpoint);
}

export function setzeBacklauf(kontoId: number, l: Lauf): void {
  tue(
    'INSERT INTO backlaeufe VALUES (?, ?) ON CONFLICT(konto_id) DO UPDATE SET lauf = excluded.lauf',
    kontoId,
    JSON.stringify(l),
  );
}

/** Für den Ticker: nur ändern, solange inzwischen kein neuer Zeitplan gekommen ist (gleiches „erstellt“). */
export function aktualisiereBacklauf(kontoId: number, l: Lauf, fertig: boolean): void {
  const wo = "konto_id = ? AND json_extract(lauf, '$.erstellt') = ?";
  if (fertig) tue(`DELETE FROM backlaeufe WHERE ${wo}`, kontoId, l.erstellt);
  else tue(`UPDATE backlaeufe SET lauf = ? WHERE ${wo}`, JSON.stringify(l), kontoId, l.erstellt);
}

export function loescheBacklauf(kontoId: number): void {
  tue('DELETE FROM backlaeufe WHERE konto_id = ?', kontoId);
}

export function backlaeufe(): { kontoId: number; lauf: Lauf }[] {
  return alle<{ konto_id: number; lauf: string }>('SELECT konto_id, lauf FROM backlaeufe').map((b) => ({
    kontoId: b.konto_id,
    lauf: JSON.parse(b.lauf),
  }));
}

export function anzahlBacklaeufe(): number {
  return eine<{ n: number }>('SELECT COUNT(*) AS n FROM backlaeufe')!.n;
}

/* ---------------------------------------------------------------- Wecker */

export interface WeckerZeile {
  token: string;
  zeiten: number[];
  gesendet: number;
}

/** Gleicher Token erneut: ersetzt Zeiten und Stand. */
export function setzeWecker(w: WeckerZeile): void {
  tue(
    `INSERT INTO wecker VALUES (?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET zeiten = excluded.zeiten, gesendet = excluded.gesendet`,
    w.token,
    JSON.stringify(w.zeiten),
    w.gesendet,
    Date.now(),
  );
}

export function setzeWeckerGesendet(token: string, zeiten: number[], gesendet: number): void {
  // Nur, solange inzwischen keine neuen Zeiten gemeldet wurden.
  tue('UPDATE wecker SET gesendet = ? WHERE token = ? AND zeiten = ?', gesendet, token, JSON.stringify(zeiten));
}

export function loescheWecker(token: string): void {
  tue('DELETE FROM wecker WHERE token = ?', token);
}

export function wecker(): WeckerZeile[] {
  return alle<{ token: string; zeiten: string; gesendet: number }>('SELECT token, zeiten, gesendet FROM wecker').map(
    (w) => ({ token: w.token, zeiten: JSON.parse(w.zeiten), gesendet: w.gesendet }),
  );
}

export function anzahlWecker(): number {
  return eine<{ n: number }>('SELECT COUNT(*) AS n FROM wecker')!.n;
}

/* ------------------------------------------------------------------- Admin */

export function neueEinladung(notiz: string): { id: number; code: string; gueltigBis: number } {
  const c = code(12);
  const gueltigBis = Date.now() + EINLADUNG_GUELTIG;
  const r = tue(
    'INSERT INTO einladungen (code_hash, notiz, erstellt, gueltig_bis) VALUES (?, ?, ?, ?)',
    hash(c),
    notiz.slice(0, 80),
    Date.now(),
    gueltigBis,
  );
  return { id: Number(r.lastInsertRowid), code: c, gueltigBis };
}

export function loescheEinladung(id: number): void {
  tue('DELETE FROM einladungen WHERE id = ?', id);
}

export function loescheKonto(id: number): void {
  tue('DELETE FROM konten WHERE id = ?', id);
}

export function kontoExistiert(id: number): boolean {
  return !!eine('SELECT 1 FROM konten WHERE id = ?', id);
}

export function uebersicht() {
  tue('DELETE FROM einladungen WHERE gueltig_bis < ?', Date.now());
  return {
    einladungen: alle<{ id: number; notiz: string; erstellt: number; gueltigBis: number }>(
      'SELECT id, notiz, erstellt, gueltig_bis AS gueltigBis FROM einladungen ORDER BY erstellt DESC',
    ),
    konten: alle<{ id: number; name: string; erstellt: number; abgleich: number; geraete: number; zuletzt: number | null }>(
      `SELECT k.id, k.name, k.erstellt,
         (SELECT COUNT(*) FROM abgleich a WHERE a.konto_id = k.id) AS abgleich,
         (SELECT COUNT(*) FROM sitzungen s WHERE s.konto_id = k.id) AS geraete,
         (SELECT MAX(zuletzt) FROM sitzungen s WHERE s.konto_id = k.id) AS zuletzt
       FROM konten k ORDER BY k.name`,
    ).map((k) => ({ ...k, sitzungen: sitzungenVon(k.id) })),
  };
}
