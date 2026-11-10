// Rezepte liegen im Konto auf dem Server. Im Browser bleiben nur
//  - eine Kopie für den Offline-Betrieb (Name des Kontos und Rezepte, „sauerteig-konto“),
//  - der Altbestand aus der Zeit vor den Konten („sauerteigRezepte“), der beim Anmelden ins Konto wandert.

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

export interface GespeichertesRezept {
    name: string;
    datum: string;
    einstellungen: Einstellungen;
}

export interface KontoRezept extends GespeichertesRezept {
    id: number;
}

export interface KontoStand {
    name: string;
    rezepte: KontoRezept[];
}

const ALT = 'sauerteigRezepte';
const KONTO = 'sauerteig-konto';

/** Rezepte aus der Zeit vor den Konten (nur in diesem Browser). */
export function altRezepte(): GespeichertesRezept[] {
    try {
        const r = JSON.parse(localStorage.getItem(ALT) || '[]');
        return Array.isArray(r) ? r : [];
    } catch {
        return [];
    }
}

export function vergissAltRezepte(): void {
    try { localStorage.removeItem(ALT); } catch { /* ignorieren */ }
}

export function leseKonto(): KontoStand | null {
    try {
        const k = JSON.parse(localStorage.getItem(KONTO) || 'null');
        return k && typeof k.name === 'string' && Array.isArray(k.rezepte) ? k : null;
    } catch {
        return null;
    }
}

export function merkeKonto(k: KontoStand | null): void {
    try {
        if (k) localStorage.setItem(KONTO, JSON.stringify(k));
        else localStorage.removeItem(KONTO);
    } catch { /* ignorieren */ }
}
