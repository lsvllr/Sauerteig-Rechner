// Back-Timer im Austauschformat: ohne die Felder, die nur das einzelne Gerät braucht (gemeldet, fern). So geht er
// an den Server (Abgleich zwischen den Geräten des Kontos, abgleich.ts) und an die Haushalt-App (haushaltApp.ts).
// Auch der Server prüft damit, was ankommt.
import { VORLAUF_WAHL, type Lauf } from './gemeinsam/timer';

export type Kern = Omit<Lauf, 'gemeldet' | 'fern'>;

export const kern = (l: Lauf | null): Kern | null =>
    l && {
        phase: l.phase,
        start: l.start,
        reife: [l.reife[0], l.reife[1]],
        erstellt: l.erstellt,
        vorlauf: l.vorlauf,
        schritte: l.schritte.map(({ at, titel, dauer }) => ({ at, titel, dauer })),
        ...(l.weiter === undefined ? {} : { weiter: l.weiter }),
    };

/** Zum Vergleichen: gleich, wenn für den Austausch dasselbe (Meldungen egal). */
export const kernText = (l: Lauf | null): string => JSON.stringify(kern(l));

const zahl = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x);
const text = (x: unknown, max: number): x is string => typeof x === 'string' && x.length <= max;

/** Lauf von außen prüfen: null = kein Timer, undefined = unbrauchbar. */
export function alsLauf(x: unknown): Lauf | null | undefined {
    if (x === null) return null;
    const l = x as Partial<Lauf> | undefined;
    if (
        !l ||
        typeof l !== 'object' ||
        (l.phase !== 'reifen' && l.phase !== 'backen') ||
        !zahl(l.start) ||
        !zahl(l.erstellt) ||
        !zahl(l.vorlauf) ||
        !VORLAUF_WAHL.includes(l.vorlauf) ||
        !Array.isArray(l.reife) ||
        !zahl(l.reife[0]) ||
        !zahl(l.reife[1]) ||
        !Array.isArray(l.schritte) ||
        l.schritte.length < 2 ||
        l.schritte.length > 12 ||
        !l.schritte.every((s) => s && zahl(s.at) && text(s.titel, 80) && text(s.dauer, 40)) ||
        (l.weiter !== undefined && (!Number.isInteger(l.weiter) || l.weiter < 0 || l.weiter > l.schritte.length))
    )
        return undefined;
    return { ...(kern(l as Lauf) as Kern), gemeldet: [] };
}
