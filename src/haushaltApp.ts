// Geöffnet in der iOS-App von Haushalt (eigenes WebView): Der Back-Timer geht bei jeder Änderung an die App, die
// plant die Mitteilungen (Reifezeit lokal, ab „Backen beginnen“ Push über den Haushalt-Server). Das WebView hat
// keine Notification-API und keinen Push; damit der Rechner (src/gemeinsam, aus der Haushalt-App übernommen)
// trotzdem „Mitteilungen an“ zeigt, setzt diese Datei eine Attrappe ein, die nichts anzeigt.
// Außerhalb der App tut sie nichts.
import { VORLAUF_WAHL, beendeLauf, setzeFernPush, starteLauf, timerStore, type Lauf } from './gemeinsam/timer';

interface AppAntwort {
    ok?: boolean;
    push?: boolean;
    mitteilungen?: unknown;
    lauf?: unknown;
}

interface Bruecke {
    postMessage(n: { art: 'lauf'; lauf: Kern | null } | { art: 'stand' }): Promise<AppAntwort>;
}

declare global {
    interface Window {
        haushaltApp?: { backTimer?: boolean };
        webkit?: { messageHandlers?: { haushaltTimer?: Bruecke } };
    }
}

const app: Bruecke | undefined =
    typeof window !== 'undefined' && window.haushaltApp?.backTimer
        ? window.webkit?.messageHandlers?.haushaltTimer
        : undefined;

/** Läuft die Seite in der Haushalt-App? */
export const inHaushaltApp = !!app;

/** Lauf ohne die Felder, die nur diese Seite braucht (gemeldet, fern). */
type Kern = Omit<Lauf, 'gemeldet' | 'fern'>;

const kern = (l: Lauf | null): Kern | null =>
    l && {
        phase: l.phase,
        start: l.start,
        reife: [l.reife[0], l.reife[1]],
        erstellt: l.erstellt,
        vorlauf: l.vorlauf,
        schritte: l.schritte.map(({ at, titel, dauer }) => ({ at, titel, dauer })),
        ...(l.weiter === undefined ? {} : { weiter: l.weiter }),
    };

const zahl = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x);

/** Lauf aus der App prüfen; undefined = unbrauchbar. */
function alsLauf(x: unknown): Lauf | null | undefined {
    if (x === null) return null;
    const l = x as Partial<Lauf> | undefined;
    if (
        !l ||
        (l.phase !== 'reifen' && l.phase !== 'backen') ||
        !zahl(l.start) ||
        !zahl(l.erstellt) ||
        !zahl(l.vorlauf) ||
        !VORLAUF_WAHL.includes(l.vorlauf) ||
        !Array.isArray(l.reife) ||
        !zahl(l.reife[0]) ||
        !zahl(l.reife[1]) ||
        !Array.isArray(l.schritte) ||
        !l.schritte.every((s) => s && zahl(s.at) && typeof s.titel === 'string' && typeof s.dauer === 'string') ||
        (l.weiter !== undefined && !zahl(l.weiter))
    )
        return undefined;
    return { ...(kern(l as Lauf) as Kern), gemeldet: [] };
}

let mitteilungenAn = true;
let letzt = '';
/** Antwort auf das zuletzt Geschickte (auch noch unterwegs) */
let antwort: Promise<AppAntwort | null> = Promise.resolve(null);

/** An die App, wenn sich für sie etwas geändert hat; sonst die Antwort vom letzten Mal. */
function anApp(l: Lauf | null): Promise<AppAntwort | null> {
    const k = kern(l);
    const s = JSON.stringify(k);
    if (s === letzt) return antwort; // nur gemeldet/fern geändert, für die App dasselbe
    letzt = s;
    antwort = app!.postMessage({ art: 'lauf', lauf: k }).then(
        (r) => {
            if (typeof r?.mitteilungen === 'boolean') mitteilungenAn = r.mitteilungen;
            return r ?? null;
        },
        () => {
            if (letzt === s) letzt = ''; // beim nächsten Mal erneut versuchen
            return null;
        },
    );
    return antwort;
}

/** Stand der App übernehmen (z. B. dort abgehakt oder beendet, oder im eingebauten Rechner gestartet). */
async function holeStand(): Promise<void> {
    const vorher = letzt;
    let r: AppAntwort | undefined;
    try {
        r = await app!.postMessage({ art: 'stand' });
    } catch {
        return;
    }
    if (!r || !('lauf' in r) || letzt !== vorher) return; // keine Antwort, oder hier inzwischen geändert
    const neu = alsLauf(r.lauf);
    if (neu === undefined) return;
    const s = JSON.stringify(kern(neu));
    if (s === JSON.stringify(kern(timerStore.lauf()))) {
        letzt = s;
        return;
    }
    letzt = s; // kommt von der App, nicht zurückschicken
    antwort = Promise.resolve({ ok: true, push: true });
    if (neu) starteLauf(neu); // Vergangenes gilt dabei als gemeldet
    else beendeLauf();
}

/** Attrappe der Notification-API: zeigt nichts, die Mitteilungen kommen von der App. */
function attrappe(): void {
    if (typeof Notification !== 'undefined') return;
    class AppMitteilung {
        static get permission(): NotificationPermission {
            return mitteilungenAn ? 'granted' : 'denied';
        }
        static requestPermission(): Promise<NotificationPermission> {
            return Promise.resolve(AppMitteilung.permission);
        }
        close(): void {}
    }
    (window as unknown as { Notification: unknown }).Notification = AppMitteilung;
}

export async function installiereHaushaltApp(): Promise<void> {
    if (!app) return;
    attrappe();
    timerStore.abonniere(() => void anApp(timerStore.lauf()));
    // Erst den Stand der App, dann (setzeFernPush meldet den laufenden Timer sofort) die eigene Anbindung.
    await holeStand();
    // Statt Push vom eigenen Server: „fern“ heißt hier, die App bzw. der Haushalt-Server melden.
    setzeFernPush({
        async plane(l) {
            return !!(await anApp(l))?.push;
        },
        async stoppe() {
            /* das Beenden geht über das Abo oben (lauf: null) an die App */
        },
    });
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') void holeStand();
    });
}
