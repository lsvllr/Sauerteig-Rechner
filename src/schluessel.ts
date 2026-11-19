// Ende-zu-Ende-Verschlüsselung des Abgleichs, gleiches Format wie ios/Sauerteig/Core/Verschluesselung.swift.
//
// - Ein Schlüssel je Konto (AES-256-GCM, 32 Byte), erzeugt auf einem Gerät, nie im Klartext beim Server. Der Server
//   kennt nur seine Kennung (SHA-256, erste 8 Byte hex), um Geräte mit falschem Schlüssel abzuweisen.
// - Änderung: `daten` wird zu {x: base64(nonce 12 ‖ Geheimtext ‖ Tag 16)}, Klartext = JSON von `daten`. Tabelle, uid
//   und Zeit bleiben lesbar (Server sortiert und verteilt) und sind als zusätzliche Daten an den Inhalt gebunden.
//   Löschen hat keinen Inhalt.
// - Gerätecode `AAAA-AAAA-GGGG-GGGG`: die erste Hälfte kennt der Server (Anmeldung), die zweite nie. Aus ihr
//   (PBKDF2-SHA256, 300 000 Runden, zufälliges Salz) entsteht der Schlüssel, mit dem der Kontoschlüssel verpackt
//   15 Minuten beim Server liegt: base64(salz 16 ‖ nonce 12 ‖ Geheimtext ‖ Tag 16).
import type { Aenderung, Wert } from './datenbank';

const KEY = 'sauerteig-schluessel';
const RUNDEN = 300_000;
const ZEICHEN = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const enc = new TextEncoder();

export const b64 = (b: Uint8Array): string => btoa(Array.from(b, (c) => String.fromCharCode(c)).join(''));
export const ausB64 = (s: string): Uint8Array => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export function leseSchluessel(): Uint8Array | null {
    try {
        const s = localStorage.getItem(KEY);
        const k = s ? ausB64(s) : null;
        return k && k.length === 32 ? k : null;
    } catch {
        return null;
    }
}

export function merkeSchluessel(k: Uint8Array | null): void {
    try {
        if (k) localStorage.setItem(KEY, b64(k));
        else localStorage.removeItem(KEY);
    } catch { /* ignorieren */ }
}

export const neuerSchluessel = (): Uint8Array => crypto.getRandomValues(new Uint8Array(32));

export async function schluesselId(k: Uint8Array): Promise<string> {
    const h = new Uint8Array(await crypto.subtle.digest('SHA-256', k as BufferSource));
    return Array.from(h.slice(0, 8), (b) => b.toString(16).padStart(2, '0')).join('');
}

const aes = (k: Uint8Array) => crypto.subtle.importKey('raw', k as BufferSource, 'AES-GCM', false, ['encrypt', 'decrypt']);

async function siegle(k: Uint8Array, klar: Uint8Array, zusatz: Uint8Array): Promise<Uint8Array> {
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: zusatz as BufferSource }, await aes(k), klar as BufferSource));
    const aus = new Uint8Array(12 + ct.length);
    aus.set(nonce);
    aus.set(ct, 12);
    return aus;
}

async function oeffne(k: Uint8Array, box: Uint8Array, zusatz: Uint8Array): Promise<Uint8Array> {
    return new Uint8Array(
        await crypto.subtle.decrypt({ name: 'AES-GCM', iv: box.slice(0, 12) as BufferSource, additionalData: zusatz as BufferSource }, await aes(k), box.slice(12) as BufferSource),
    );
}

const zusatz = (a: Aenderung) => enc.encode(`${a.tabelle}\n${a.uid}\n${a.zeit}`);

export async function verschluessele(k: Uint8Array, a: Aenderung): Promise<Aenderung> {
    if (a.geloescht) return { ...a, daten: {} };
    const box = await siegle(k, enc.encode(JSON.stringify(a.daten)), zusatz(a));
    return { ...a, daten: { x: b64(box) } };
}

/** null: nicht lesbar (anderer Schlüssel, verändert). Klartext nur, was der Server selbst beim Update aus seinem
 * Altbestand übernommen hat (Zeit endet auf „-server0000“). */
export async function entschluessele(k: Uint8Array, a: Aenderung): Promise<Aenderung | null> {
    if (a.geloescht) return { ...a, daten: {} };
    const x = a.daten.x;
    if (typeof x !== 'string') return a.zeit.endsWith('-server0000') ? a : null;
    try {
        const klar = await oeffne(k, ausB64(x), zusatz(a));
        const daten = JSON.parse(new TextDecoder().decode(klar)) as Record<string, Wert>;
        return daten && typeof daten === 'object' ? { ...a, daten } : null;
    } catch {
        return null;
    }
}

/* -------------------------------------------------------------- Gerätecode */

/** Geheimer Teil des Gerätecodes: 8 Zeichen ohne verwechselbare (gleiche wie der Server). */
export function neuesGeheimnis(): string {
    const z = crypto.getRandomValues(new Uint8Array(8));
    return Array.from(z, (b) => ZEICHEN[b % ZEICHEN.length]).join('');
}

/** Eingabe zerlegen: 16 Zeichen = Server-Teil + Geheimnis, 8 Zeichen = nur Server-Teil (Code vom Admin). */
export function zerlegeCode(eingabe: string): { server: string; geheim: string | null } {
    const s = eingabe.toUpperCase().replace(/[^A-Z0-9]/g, '');
    return s.length >= 16 ? { server: s.slice(0, 8), geheim: s.slice(8, 16) } : { server: s, geheim: null };
}

export const zeigeCode = (server: string, geheim: string): string =>
    (server.replace(/[^A-Z0-9]/gi, '') + geheim).toUpperCase().replace(/(.{4})(?=.)/g, '$1-');

async function packSchluessel(geheim: string, salz: Uint8Array): Promise<Uint8Array> {
    const basis = await crypto.subtle.importKey('raw', enc.encode(geheim) as BufferSource, 'PBKDF2', false, ['deriveBits']);
    return new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: salz as BufferSource, iterations: RUNDEN }, basis, 256));
}

const PACK_ZUSATZ = enc.encode('sauerteig-schluessel');

export async function verpacke(k: Uint8Array, geheim: string): Promise<string> {
    const salz = crypto.getRandomValues(new Uint8Array(16));
    const box = await siegle(await packSchluessel(geheim, salz), k, PACK_ZUSATZ);
    const aus = new Uint8Array(16 + box.length);
    aus.set(salz);
    aus.set(box, 16);
    return b64(aus);
}

export async function entpacke(blob: string, geheim: string): Promise<Uint8Array | null> {
    try {
        const d = ausB64(blob);
        const k = await oeffne(await packSchluessel(geheim, d.slice(0, 16)), d.slice(16), PACK_ZUSATZ);
        return k.length === 32 ? k : null;
    } catch {
        return null;
    }
}
