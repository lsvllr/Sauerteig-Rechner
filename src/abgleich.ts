// Abgleich der lokalen Datenbank (datenbank.ts) zwischen den Geräten eines Kontos, über den Server als Relais
// (server/server.ts, /api/sync/*). Gleiches Protokoll wie die iOS-App (ios/Sauerteig/App/Abgleich.swift).
//
// - Ohne Konto oder mit nur einem Gerät im Konto liegt nichts am Server; „ausstehend“ wird dann verworfen, weil beim
//   Einstieg in einen Abgleich ohnehin alles gesendet wird.
// - Ab zwei Geräten: holen (seitenweise ab dem eigenen Stand), dann einmal alles senden (Schnappschuss, je
//   Kennung), danach nur noch die ausstehenden Änderungen.
// - Neue Kennung (das Konto war zwischendurch nur ein Gerät, der Server hat geleert): von vorn.
// - Ende-zu-Ende verschlüsselt (schluessel.ts): Der Server sieht nur Tabelle, uid und Zeit. Ein Gerät ohne oder
//   mit falschem Schlüssel bekommt nichts und muss ihn mit einem Gerätecode eines anderen Geräts holen.
// Angestoßen beim Öffnen, sobald der Server „neu“ meldet (Server-Sent Events, /api/sync/live), bei jeder Rückkehr
// auf die Seite, kurz nach jeder eigenen Änderung und zur Sicherheit jede Minute.
import { db, type Aenderung } from './datenbank';
import { post, rufe } from './api';
import { entschluessele, leseSchluessel, merkeSchluessel, neuerSchluessel, schluesselId, verschluessele } from './schluessel';

const KEY = 'sauerteig-abgleich';
const TAKT = 60_000;
const SEITE = 500;

interface Zustand {
    kennung: string;
    /** Bis hier geholt und übernommen */
    ab: number;
    /** Für diese Kennung wurde schon alles gesendet */
    gesendet: string;
    geraete: number;
}

const leer = (): Zustand => ({ kennung: '', ab: 0, gesendet: '', geraete: 0 });

function lade(): Zustand {
    try {
        const z = JSON.parse(localStorage.getItem(KEY) || 'null') as Zustand | null;
        if (z && typeof z.kennung === 'string' && typeof z.ab === 'number') return { ...leer(), ...z };
    } catch {
        /* neu */
    }
    return leer();
}

let z = typeof window === 'undefined' ? leer() : lade();
let aktiv = false;
let laeuft = false;
let nochmal = false;
let ticker: ReturnType<typeof setInterval> | null = null;
let quelle: EventSource | null = null;
/** Das Konto hat einen Schlüssel, dieses Gerät nicht (oder einen anderen). */
let schluesselFehlt = false;
let verzoegert: ReturnType<typeof setTimeout> | null = null;
let abgemeldet: () => void = () => undefined;
const hoerer = new Set<() => void>();

function setzeSchluesselFehlt(f: boolean): void {
    if (f === schluesselFehlt) return;
    schluesselFehlt = f;
    hoerer.forEach((h) => h());
}

function merke(neu: Zustand): void {
    const geraeteAnders = neu.geraete !== z.geraete;
    z = neu;
    try {
        localStorage.setItem(KEY, JSON.stringify(z));
    } catch {
        /* nur bis zum Neuladen */
    }
    if (geraeteAnders) hoerer.forEach((f) => f());
}

/** Geräte im Konto beim letzten Abgleich (0 = noch nicht bekannt). */
export const geraete = () => z.geraete;
export const fehltSchluessel = () => schluesselFehlt;
export function abonniereGeraete(f: () => void): () => void {
    hoerer.add(f);
    return () => hoerer.delete(f);
}

async function einmal(): Promise<void> {
    let k = leseSchluessel();
    const id = k ? await schluesselId(k) : '';
    // Holen bis zum Ende
    for (;;) {
        const r = await rufe(`/api/sync/holen?kennung=${encodeURIComponent(z.kennung)}&ab=${z.ab}&schluessel=${id}`);
        if (r.status === 401) return abgemeldet();
        if (!r.ok) return;
        if (r.schluessel !== true) {
            // Konto ohne Schlüssel (älteres Konto): dieses Gerät erzeugt ihn und legt ihn beim nächsten Holen fest
            if (!k && r.schluesselDa !== true) {
                merkeSchluessel(neuerSchluessel());
                nochmal = true;
            } else setzeSchluesselFehlt(true);
            merke({ ...z, geraete: Number(r.geraete) || 0 });
            return;
        }
        setzeSchluesselFehlt(false);
        const kennung = String(r.kennung);
        const neueKennung = kennung !== z.kennung;
        const fremd = await Promise.all(((r.aenderungen as Aenderung[]) ?? []).map((a) => entschluessele(k!, a)));
        db.wende(fremd.filter((a): a is Aenderung => !!a));
        merke({ ...z, kennung, ab: Number(r.bis) || 0, geraete: Number(r.geraete) || 0, gesendet: neueKennung ? '' : z.gesendet });
        if (!r.mehr) break;
    }
    // Allein im Konto: nichts senden, nichts aufheben
    if (z.geraete < 2) {
        const aus = db.ausstehend();
        if (aus.length) db.quittiere(new Set(aus.map((a) => a.zeit)));
        return;
    }
    const alles = z.gesendet !== z.kennung;
    const aus = db.ausstehend();
    const liste = alles ? db.schnappschuss() : aus;
    k = k!;
    for (let i = 0; i < liste.length || (alles && i === 0); i += SEITE) {
        const teil = liste.slice(i, i + SEITE);
        const geheim = await Promise.all(teil.map((a) => verschluessele(k!, a)));
        const r = await post('/api/sync/senden', { kennung: z.kennung, schluessel: id, aenderungen: geheim });
        if (r.status === 401) return abgemeldet();
        if (!r.ok || r.angenommen !== true) return; // Kennung neu oder allein: beim nächsten Mal von vorn
        db.quittiere(new Set((alles ? aus : teil).map((a) => a.zeit)));
    }
    if (alles) merke({ ...z, gesendet: z.kennung });
}

/** Jetzt abgleichen (läuft schon einer: danach noch einmal). */
export async function gleicheAb(): Promise<void> {
    if (!aktiv) return;
    if (laeuft) {
        nochmal = true;
        return;
    }
    laeuft = true;
    try {
        do {
            nochmal = false;
            await einmal();
        } while (nochmal && aktiv);
    } catch {
        /* offline: beim nächsten Anstoß */
    } finally {
        laeuft = false;
    }
}

const sichtbar = () => {
    if (document.visibilityState === 'visible') void gleicheAb();
};

/** Angemeldet: abgleichen. ``beiAbmeldung``: der Server kennt die Sitzung nicht mehr (Konto gelöscht). */
export function starteAbgleich(beiAbmeldung: () => void): void {
    abgemeldet = beiAbmeldung;
    if (aktiv) return;
    aktiv = true;
    void gleicheAb();
    document.addEventListener('visibilitychange', sichtbar);
    ticker = setInterval(sichtbar, TAKT);
    // Der Browser verbindet von selbst neu (retry vom Server)
    if (typeof EventSource !== 'undefined') {
        quelle = new EventSource('/api/sync/live');
        quelle.addEventListener('neu', () => void gleicheAb());
    }
}

// Kurz nach einer eigenen Änderung senden (mehrere schnell hintereinander zusammen)
if (typeof window !== 'undefined')
    db.abonniere((fremd) => {
        if (fremd || !aktiv) return;
        if (verzoegert) clearTimeout(verzoegert);
        verzoegert = setTimeout(() => void gleicheAb(), 1500);
    });

/** Abgemeldet: Daten bleiben auf diesem Gerät, der Stand des Abgleichs ist vergessen. */
export function trenneAbgleich(): void {
    aktiv = false;
    document.removeEventListener('visibilitychange', sichtbar);
    if (ticker) clearInterval(ticker);
    ticker = null;
    quelle?.close();
    quelle = null;
    merke(leer());
    setzeSchluesselFehlt(false);
}
