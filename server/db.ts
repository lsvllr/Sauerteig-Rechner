// Datenbank des Sauerteig-Rechners (SQLite, in Node eingebaut). Liegt in DATA_DIR (Add-on: /data, in den
// HA-Backups), lokal in ./data.
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
  CREATE TABLE IF NOT EXISTS rezepte (
    id INTEGER PRIMARY KEY,
    konto_id INTEGER NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    datum TEXT NOT NULL,
    einstellungen TEXT NOT NULL,
    erstellt INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS rezepte_konto ON rezepte(konto_id);
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
`);

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
  tue('INSERT INTO sitzungen VALUES (?, ?, ?, ?, ?)', hash(token), kontoId, jetzt, jetzt, geraet.slice(0, 120));
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

export function beendeSitzung(token: string): void {
  tue('DELETE FROM sitzungen WHERE token_hash = ?', hash(token));
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

/** Gerätecode einlösen (einmalig). */
export function loeseGeraetecode(codeEingabe: string): Konto | null {
  const h = hash(normiereCode(codeEingabe));
  return inTransaktion(() => {
    const k = eine<Konto & { gueltig_bis: number }>(
      'SELECT k.id, k.name, g.gueltig_bis FROM geraetecodes g JOIN konten k ON k.id = g.konto_id WHERE g.code_hash = ?',
      h,
    );
    tue('DELETE FROM geraetecodes WHERE code_hash = ?', h);
    return k && k.gueltig_bis >= Date.now() ? { id: k.id, name: k.name } : null;
  });
}

export function neuerGeraetecode(kontoId: number): { code: string; gueltigBis: number } {
  const c = code(8);
  const gueltigBis = Date.now() + GERAETECODE_GUELTIG;
  tue('DELETE FROM geraetecodes WHERE gueltig_bis < ?', Date.now());
  tue('INSERT INTO geraetecodes VALUES (?, ?, ?)', hash(c), kontoId, gueltigBis);
  return { code: c, gueltigBis };
}

/* ----------------------------------------------------------------- Rezepte */

export interface RezeptZeile {
  id: number;
  name: string;
  datum: string;
  einstellungen: Record<string, unknown>;
}

export const MAX_REZEPTE = 500;

export function rezepte(kontoId: number): RezeptZeile[] {
  return alle<{ id: number; name: string; datum: string; einstellungen: string }>(
    'SELECT id, name, datum, einstellungen FROM rezepte WHERE konto_id = ? ORDER BY erstellt, id',
    kontoId,
  ).map((r) => ({ ...r, einstellungen: JSON.parse(r.einstellungen) }));
}

export function anzahlRezepte(kontoId: number): number {
  return eine<{ n: number }>('SELECT COUNT(*) AS n FROM rezepte WHERE konto_id = ?', kontoId)!.n;
}

export function fuegeRezeptHinzu(kontoId: number, r: Omit<RezeptZeile, 'id'>): number {
  const z = tue(
    'INSERT INTO rezepte (konto_id, name, datum, einstellungen, erstellt) VALUES (?, ?, ?, ?, ?)',
    kontoId,
    r.name,
    r.datum,
    JSON.stringify(r.einstellungen),
    Date.now(),
  );
  return Number(z.lastInsertRowid);
}

export function loescheRezept(kontoId: number, id: number): boolean {
  return tue('DELETE FROM rezepte WHERE id = ? AND konto_id = ?', id, kontoId).changes > 0;
}

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
    konten: alle<{ id: number; name: string; erstellt: number; rezepte: number; geraete: number; zuletzt: number | null }>(
      `SELECT k.id, k.name, k.erstellt,
         (SELECT COUNT(*) FROM rezepte r WHERE r.konto_id = k.id) AS rezepte,
         (SELECT COUNT(*) FROM sitzungen s WHERE s.konto_id = k.id) AS geraete,
         (SELECT MAX(zuletzt) FROM sitzungen s WHERE s.konto_id = k.id) AS zuletzt
       FROM konten k ORDER BY k.name`,
    ),
  };
}
