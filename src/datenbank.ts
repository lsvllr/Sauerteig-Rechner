// Lokale Datenbank der Web-App, gleiches Format und gleiche Regeln wie die iOS-App
// (ios/Sauerteig/Core/Datenbank.swift, ios/LOCAL-FIRST.md Abschnitt 3): Der Browser hat alle Daten, der Server
// sieht sie nur, solange das Konto mindestens zwei Geräte abgleicht (abgleich.ts).
//
// Jede Zeile hat eine uid, jedes Feld die Zeit seiner letzten Änderung (hybride logische Uhr). Jede Schreiboperation
// erzeugt eine Änderung {tabelle, uid, daten, geloescht, zeit} in „ausstehend“. Fremde Änderungen spielt wende()
// je Feld nach der späteren Zeit ein; gelöscht bleibt gelöscht. Gespeichert in localStorage („sauerteig-daten“).

export type Wert = string | number | boolean | null;

export interface Aenderung {
    tabelle: string;
    uid: string;
    daten: Record<string, Wert>;
    geloescht: boolean;
    zeit: string;
}

export interface Zeile {
    d: Record<string, Wert>;
    z: Record<string, string>;
}

interface Uhr {
    geraet: string;
    ms: number;
    zaehler: number;
}

interface Datei {
    tabellen: Record<string, Record<string, Zeile>>;
    aus: Aenderung[];
    uhr: Uhr;
}

const KEY = 'sauerteig-daten';
const LOESCH = '_geloescht';

const hex = (n: number) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, '0')).join('');

export const neueUid = (): string =>
    typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : `${hex(4)}-${hex(2)}-4${hex(2).slice(1)}-8${hex(2).slice(1)}-${hex(6)}`;

/** `<ms, 13-stellig>-<Zähler, 4 hex>-<Gerät>`; geht nie hinter die späteste gesehene Zeit zurück. */
function naechste(u: Uhr, jetzt = Date.now()): string {
    if (jetzt > u.ms) {
        u.ms = jetzt;
        u.zaehler = 0;
    } else u.zaehler++;
    return `${String(u.ms).padStart(13, '0')}-${u.zaehler.toString(16).padStart(4, '0')}-${u.geraet}`;
}

/** Millisekunden einer Zeit (0, wenn unlesbar). */
export const zeitMs = (zeit: string | undefined): number => Number(/^(\d{13})-/.exec(zeit ?? '')?.[1] ?? 0);

function sieh(u: Uhr, zeit: string): void {
    const m = /^(\d{13})-([0-9a-f]{4})-/.exec(zeit);
    if (!m) return;
    const ms = Number(m[1]);
    const c = parseInt(m[2]!, 16);
    if (ms > u.ms || (ms === u.ms && c > u.zaehler)) {
        u.ms = ms;
        u.zaehler = c;
    }
}

function lade(): Datei {
    try {
        const d = JSON.parse(localStorage.getItem(KEY) || 'null') as Datei | null;
        if (d && d.tabellen && Array.isArray(d.aus) && d.uhr?.geraet) return d;
    } catch {
        /* neu anfangen */
    }
    return { tabellen: {}, aus: [], uhr: { geraet: 'web' + hex(8), ms: 0, zaehler: 0 } };
}

let datei: Datei = typeof window === 'undefined' ? { tabellen: {}, aus: [], uhr: { geraet: 'webserver0', ms: 0, zaehler: 0 } } : lade();
/** `fremd`: kam aus dem Abgleich oder einem anderen Tab, nicht von hier. */
const hoerer = new Set<(fremd: boolean) => void>();
let stand = 0;

function speichere(fremd: boolean): void {
    stand++;
    try {
        localStorage.setItem(KEY, JSON.stringify(datei));
    } catch {
        /* voll oder gesperrt: bis zum Neuladen nur im Speicher */
    }
    hoerer.forEach((f) => f(fremd));
}

function wendeAn(a: Aenderung): void {
    const t = (datei.tabellen[a.tabelle] ??= {});
    const z = (t[a.uid] ??= { d: {}, z: {} });
    if (a.geloescht) {
        z.d[LOESCH] = true;
        if (!z.z[LOESCH] || z.z[LOESCH]! < a.zeit) z.z[LOESCH] = a.zeit;
        return;
    }
    for (const [k, v] of Object.entries(a.daten)) {
        if (k === LOESCH) continue;
        const alt = z.z[k];
        if (alt && alt >= a.zeit) continue;
        z.d[k] = v;
        z.z[k] = a.zeit;
    }
}

/** In „ausstehend“: spätere eigene Änderung desselben Felds ersetzt die frühere, Löschen alles davor. */
function merke(a: Aenderung): void {
    const gleich = (x: Aenderung) => x.tabelle === a.tabelle && x.uid === a.uid;
    if (a.geloescht) datei.aus = datei.aus.filter((x) => !gleich(x));
    else {
        for (const x of datei.aus) if (gleich(x) && !x.geloescht) for (const k of Object.keys(a.daten)) delete x.daten[k];
        datei.aus = datei.aus.filter((x) => x.geloescht || Object.keys(x.daten).length > 0);
    }
    datei.aus.push(a);
}

const istGeloescht = (z: Zeile) => z.d[LOESCH] === true;

export const db = {
    /** Für useSyncExternalStore: ändert sich bei jeder Änderung. */
    stand: () => stand,

    abonniere(f: (fremd: boolean) => void): () => void {
        hoerer.add(f);
        return () => hoerer.delete(f);
    },

    zeile(tabelle: string, uid: string): Zeile | null {
        const z = datei.tabellen[tabelle]?.[uid];
        return z && !istGeloescht(z) ? z : null;
    },

    zeilen(tabelle: string): { uid: string; zeile: Zeile }[] {
        return Object.entries(datei.tabellen[tabelle] ?? {})
            .filter(([, z]) => !istGeloescht(z))
            .map(([uid, zeile]) => ({ uid, zeile }))
            .sort((a, b) => (a.uid < b.uid ? -1 : 1));
    },

    /** Felder setzen; gleicher Wert zählt nicht, gelöschte Zeile bleibt gelöscht. */
    schreibe(tabelle: string, uid: string, felder: Record<string, Wert>, jetzt = Date.now()): Aenderung | null {
        const alt = datei.tabellen[tabelle]?.[uid];
        if (alt && istGeloescht(alt)) return null;
        const daten: Record<string, Wert> = {};
        for (const [k, v] of Object.entries(felder)) if (k !== LOESCH && (!alt || alt.d[k] !== v)) daten[k] = v;
        if (!Object.keys(daten).length) return null;
        const a: Aenderung = { tabelle, uid, daten, geloescht: false, zeit: naechste(datei.uhr, jetzt) };
        wendeAn(a);
        merke(a);
        speichere(false);
        return a;
    },

    loesche(tabelle: string, uid: string, jetzt = Date.now()): Aenderung | null {
        const alt = datei.tabellen[tabelle]?.[uid];
        if (!alt || istGeloescht(alt)) return null;
        const a: Aenderung = { tabelle, uid, daten: {}, geloescht: true, zeit: naechste(datei.uhr, jetzt) };
        wendeAn(a);
        merke(a);
        speichere(false);
        return a;
    },

    /** Fremde Änderungen einspielen (Abgleich). */
    wende(fremd: Aenderung[]): void {
        if (!fremd.length) return;
        for (const a of fremd) {
            sieh(datei.uhr, a.zeit);
            wendeAn(a);
        }
        speichere(true);
    },

    ausstehend: (): Aenderung[] => datei.aus.map((a) => ({ ...a, daten: { ...a.daten } })),

    /** Beim Server angekommen (oder nicht mehr nötig): aus „ausstehend“ nehmen. */
    quittiere(zeiten: Set<string>): void {
        const vorher = datei.aus.length;
        datei.aus = datei.aus.filter((a) => !zeiten.has(a.zeit));
        if (datei.aus.length !== vorher) speichere(false);
    },

    /** Alles als Änderungen, je Zeile gruppiert nach Feldzeit (damit die Zeiten erhalten bleiben). Für den Einstieg
     * in einen Abgleich: Das andere Gerät kennt noch nichts von hier. */
    schnappschuss(): Aenderung[] {
        const aus: Aenderung[] = [];
        for (const [tabelle, zeilen] of Object.entries(datei.tabellen))
            for (const [uid, z] of Object.entries(zeilen)) {
                if (istGeloescht(z)) {
                    aus.push({ tabelle, uid, daten: {}, geloescht: true, zeit: z.z[LOESCH] ?? naechste(datei.uhr) });
                    continue;
                }
                const jeZeit = new Map<string, Record<string, Wert>>();
                for (const [k, v] of Object.entries(z.d)) {
                    const t = z.z[k];
                    if (!t) continue;
                    if (!jeZeit.has(t)) jeZeit.set(t, {});
                    jeZeit.get(t)![k] = v;
                }
                for (const [zeit, daten] of jeZeit) aus.push({ tabelle, uid, daten, geloescht: false, zeit });
            }
        return aus.sort((a, b) => (a.zeit < b.zeit ? -1 : 1));
    },
};

// Anderer Tab hat geschrieben
if (typeof window !== 'undefined')
    window.addEventListener('storage', (e) => {
        if (e.key !== KEY) return;
        datei = lade();
        stand++;
        hoerer.forEach((f) => f(true));
    });

/* ----------------------------------------------------------------- Rezepte */

export interface LokalesRezept {
    uid: string;
    name: string;
    datum: string;
    einstellungen: Record<string, unknown>;
    /** Zeit der Anlage (Sortierung) */
    erstellt: string;
}

const json = (v: Wert | undefined): unknown => {
    try {
        return typeof v === 'string' ? JSON.parse(v) : undefined;
    } catch {
        return undefined;
    }
};

export function rezepte(): LokalesRezept[] {
    return db
        .zeilen('rezept')
        .flatMap(({ uid, zeile: z }) => {
            if (typeof z.d.name !== 'string') return [];
            const e = json(z.d.einstellungen);
            return [{
                uid,
                name: z.d.name,
                datum: typeof z.d.datum === 'string' ? z.d.datum : '',
                einstellungen: e && typeof e === 'object' ? (e as Record<string, unknown>) : {},
                erstellt: z.z.name ?? '',
            }];
        })
        .sort((a, b) => (a.erstellt < b.erstellt ? -1 : 1));
}

/** Einstellungen als ein JSON-Feld mit sortierten Schlüsseln (wie iOS), sonst zählt dieselbe Fassung als Änderung. */
export const sortiertesJson = (v: unknown): string =>
    JSON.stringify(v, (_, x) =>
        x && typeof x === 'object' && !Array.isArray(x)
            ? Object.fromEntries(Object.entries(x as Record<string, unknown>).sort(([a], [b]) => (a < b ? -1 : 1)))
            : x,
    );

export function speichereRezept(name: string, datum: string, einstellungen: Record<string, unknown>, uid = neueUid()): void {
    db.schreibe('rezept', uid, { name: name.trim().slice(0, 80), datum, einstellungen: sortiertesJson(einstellungen) });
}
