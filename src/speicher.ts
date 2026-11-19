// Was die Web-App außer der Datenbank (datenbank.ts) im Browser hält: das Konto, falls dieses Gerät verknüpft ist
// („sauerteig-konto“, nur der Name; angemeldet ist es über das Sitzungs-Cookie).
//
// Übernahme älterer Stände in die lokale Datenbank (einmal beim Start):
//  - „sauerteigRezepte“: Rezepte aus der Zeit vor den Konten,
//  - „sauerteig-konto“ mit Rezepten: Kopie der Rezepte, als sie im Konto am Server lagen. Gleiche uid wie der Server
//    bei seiner Übernahme (server/db.ts, altRezeptUid), damit nichts doppelt ankommt.
import { db, speichereRezept } from './datenbank';

export interface Einstellungen {
    anstellgut: string;
    sauerteigTemp: string;
    gareTemp: string;
    brotGroesse: string;
    hydration: string;
    mehlMischung: string;
    customRoggen: string;
    customDinkel: string;
    customWeizen: string;
    customBuchweizen: string;
    teigTeilen?: boolean;
}

interface AltesRezept {
    id?: number;
    name: string;
    datum: string;
    einstellungen: Einstellungen;
}

export interface Konto {
    name: string;
}

const ALT = 'sauerteigRezepte';
const KONTO = 'sauerteig-konto';

export const altRezeptUid = (id: number) => `00000000-0000-4000-8000-${id.toString(16).padStart(12, '0')}`;

const liste = (x: unknown): AltesRezept[] =>
    Array.isArray(x) ? x.filter((r) => r && typeof r.name === 'string' && r.einstellungen && typeof r.einstellungen === 'object') : [];

export function leseKonto(): Konto | null {
    try {
        const k = JSON.parse(localStorage.getItem(KONTO) || 'null');
        return k && typeof k.name === 'string' ? { name: k.name } : null;
    } catch {
        return null;
    }
}

export function merkeKonto(k: Konto | null): void {
    try {
        if (k) localStorage.setItem(KONTO, JSON.stringify({ name: k.name }));
        else localStorage.removeItem(KONTO);
    } catch { /* ignorieren */ }
}

/** Ältere Stände einmal in die Datenbank. */
export function uebernimmAlteRezepte(): void {
    try {
        for (const r of liste(JSON.parse(localStorage.getItem(ALT) || '[]')))
            speichereRezept(r.name, String(r.datum ?? ''), r.einstellungen as unknown as Record<string, unknown>);
        localStorage.removeItem(ALT);
        const k = JSON.parse(localStorage.getItem(KONTO) || 'null');
        if (k && Array.isArray(k.rezepte)) {
            for (const r of liste(k.rezepte))
                if (typeof r.id === 'number' && !db.zeile('rezept', altRezeptUid(r.id)))
                    speichereRezept(r.name, String(r.datum ?? ''), r.einstellungen as unknown as Record<string, unknown>, altRezeptUid(r.id));
            merkeKonto(typeof k.name === 'string' ? { name: k.name } : null);
        }
    } catch { /* ignorieren */ }
}
