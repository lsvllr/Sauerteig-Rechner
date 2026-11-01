// Gleiches Speicherformat wie die bisherige JS-Version (Werte als Strings)
const SCHLUESSEL = 'sauerteigRezepte';

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

export function lese(): GespeichertesRezept[] {
    try { return JSON.parse(localStorage.getItem(SCHLUESSEL) || '[]'); } catch { return []; }
}

export function schreibe(r: GespeichertesRezept[]): boolean {
    try { localStorage.setItem(SCHLUESSEL, JSON.stringify(r)); return true; } catch { return false; }
}

export function loescheAlle(): void {
    try { localStorage.removeItem(SCHLUESSEL); } catch { /* ignorieren */ }
}
