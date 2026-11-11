// Back-Timer zwischen den Geräten des Kontos abgleichen. Jede Änderung (Ansetzen, Abhaken, Vorwarnung, Beenden) geht
// mit ihrem Zeitpunkt an den Server (/api/timer/stand); beim Öffnen, bei jeder Rückkehr auf die Seite und alle
// 30 Sekunden holt die Seite den Stand des Kontos (/api/timer). Es gilt der neueste Stand. Was offline geändert
// wurde, geht beim nächsten Abgleich nach. Ab „Backen beginnen“ pusht der Server aus diesem Stand (server.ts).
import { beendeLauf, starteLauf, timerStore, type Lauf } from './gemeinsam/timer';
import { alsLauf, kern, kernText } from './laufKern';
import { post, rufe, type Antwort } from './api';

const KEY = 'sauerteig-timer-abgleich';
const TAKT = 30_000;

interface Zustand {
    /** Zeitpunkt der letzten Änderung des Timers auf diesem Gerät oder des übernommenen Stands */
    geaendert: number;
    /** Änderung noch nicht beim Server */
    offen: boolean;
}

function lade(): Zustand {
    try {
        const z = JSON.parse(localStorage.getItem(KEY) || 'null') as Zustand | null;
        if (z && typeof z.geaendert === 'number') return { geaendert: z.geaendert, offen: !!z.offen };
    } catch {
        /* neu anfangen */
    }
    // Timer von vor dem Abgleich: gilt als Änderung von damals
    const l = timerStore.lauf();
    return l ? { geaendert: l.erstellt, offen: true } : { geaendert: 0, offen: false };
}

let z: Zustand = typeof window === 'undefined' ? { geaendert: 0, offen: false } : lade();
let bekannt = kernText(timerStore.lauf());
let uebernehmen = false;
let aktiv = false;
let reihe: Promise<unknown> = Promise.resolve();
let ticker: ReturnType<typeof setInterval> | null = null;

function merke(neu: Zustand): void {
    z = neu;
    try {
        localStorage.setItem(KEY, JSON.stringify(z));
    } catch {
        /* dann nur bis zum Neuladen */
    }
}

/** Zeitpunkt des aktuellen Stands auf diesem Gerät */
export const geaendert = (): number => z.geaendert;

/** Stand von außen setzen (Server oder Haushalt-App), ohne ihn als eigene Änderung zu zählen. ``offen``: noch an
 * den Server schicken (aus der App übernommen). */
export function uebernimm(l: Lauf | null, wann: number, offen: boolean): void {
    uebernehmen = true;
    try {
        if (l) starteLauf(l); // Vergangenes gilt dabei als gemeldet
        else beendeLauf();
    } finally {
        uebernehmen = false;
    }
    bekannt = kernText(timerStore.lauf());
    merke({ geaendert: wann, offen });
    if (offen) void sende();
}

/** Antwort des Servers: ist sein Stand neuer, übernehmen. */
function verarbeite(r: Antwort): void {
    const g = Number(r.geaendert);
    if (!Number.isFinite(g) || g <= z.geaendert || z.offen) return;
    const l = alsLauf(r.lauf ?? null);
    if (l === undefined) return;
    if (kernText(l) === kernText(timerStore.lauf())) merke({ geaendert: g, offen: false });
    else uebernimm(l, g, false);
}

function sende(): Promise<unknown> {
    reihe = reihe.then(async () => {
        if (!aktiv || !z.offen) return;
        const g = z.geaendert;
        try {
            const r = await post('/api/timer/stand', { lauf: kern(timerStore.lauf()), geaendert: g });
            if (!r.ok) return;
            if (z.geaendert === g) merke({ geaendert: g, offen: false });
            verarbeite(r);
        } catch {
            /* offline: beim nächsten Abgleich */
        }
    });
    return reihe;
}

async function hole(): Promise<void> {
    if (!aktiv || (typeof document !== 'undefined' && document.visibilityState === 'hidden')) return;
    if (z.offen) {
        await sende(); // eigene Änderung zuerst; ist der Server neuer, kommt sein Stand mit der Antwort
        return;
    }
    try {
        const r = await rufe('/api/timer');
        if (r.ok) verarbeite(r);
    } catch {
        /* offline */
    }
}

/** Ist der aktuelle Stand beim Server? (Dann pusht er ab „Backen beginnen“.) */
export async function synchron(): Promise<boolean> {
    await sende();
    return aktiv && !z.offen;
}

if (typeof window !== 'undefined') {
    timerStore.abonniere(() => {
        const s = kernText(timerStore.lauf());
        if (s === bekannt) return; // nur Meldungen geändert
        bekannt = s;
        if (uebernehmen) return;
        merke({ geaendert: Math.max(Date.now(), z.geaendert + 1), offen: true });
        void sende();
    });
    // Anderer Tab hat geändert oder abgeglichen
    window.addEventListener('storage', (e) => {
        if (e.key === KEY) z = lade();
        if (e.key === KEY || e.key === 'sauerteig-timer') bekannt = kernText(timerStore.lauf());
    });
}

const sichtbar = () => void hole();

/** Angemeldet: abgleichen. */
export function starteAbgleich(): void {
    if (aktiv) return;
    aktiv = true;
    void hole();
    document.addEventListener('visibilitychange', sichtbar);
    ticker = setInterval(sichtbar, TAKT);
}

/** Abgemeldet: Timer nur auf diesem Gerät beenden, das Konto behält ihn. */
export function trenneAbgleich(): void {
    aktiv = false;
    document.removeEventListener('visibilitychange', sichtbar);
    if (ticker) clearInterval(ticker);
    ticker = null;
    uebernimm(null, 0, false);
}
