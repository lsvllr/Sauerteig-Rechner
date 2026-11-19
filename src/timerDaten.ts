// Back-Timer in der lokalen Datenbank (Tabelle `backlauf`, gleiches Format wie iOS: ios/Sauerteig/Core/BackLauf.swift).
// Der Timer selbst (src/gemeinsam/timer.ts, aus der Haushalt-App) hält seinen Stand in localStorage; diese Datei
// spiegelt jede Änderung als Zeile in die Datenbank und übernimmt Änderungen aus dem Abgleich zurück.
//
// Je „Sauerteig angesetzt“ eine neue Zeile (neue uid), erkannt am Startzeitpunkt; der laufende Lauf ist die jüngste
// nicht gelöschte Zeile; Beenden = Löschmarke. Der Zeitplan steht als ein JSON-Feld, sonst mischte der Abgleich pro
// Feld Schritte aus zwei Fassungen.
import { beendeLauf, starteLauf, timerStore, type Lauf } from './gemeinsam/timer';
import { alsLauf, kernText } from './laufKern';
import { db, sortiertesJson, zeitMs, neueUid, type Wert, type Zeile } from './datenbank';

const TABELLE = 'backlauf';

function felder(l: Lauf): Record<string, Wert> {
    return {
        phase: l.phase,
        start: Math.round(l.start),
        reife: JSON.stringify(l.reife.map(Math.round)),
        vorlauf: l.vorlauf,
        weiter: l.weiter ?? null,
        schritte: sortiertesJson(l.schritte.map((s) => ({ at: Math.round(s.at), titel: s.titel, dauer: s.dauer }))),
    };
}

const json = (v: Wert | undefined): unknown => {
    try {
        return typeof v === 'string' ? JSON.parse(v) : undefined;
    } catch {
        return undefined;
    }
};

function alsLaufAusZeile(z: Zeile): Lauf | null {
    const start = Number(z.d.start);
    const reife = json(z.d.reife);
    const l = alsLauf({
        phase: z.d.phase,
        start,
        reife: Array.isArray(reife) && reife.length === 2 ? reife : [start, start],
        // Zeit der letzten Änderung: was davor fällig war, meldet sich nicht nach
        erstellt: Math.max(0, ...Object.values(z.z).map(zeitMs)),
        vorlauf: typeof z.d.vorlauf === 'number' ? z.d.vorlauf : 10,
        schritte: json(z.d.schritte),
        ...(typeof z.d.weiter === 'number' ? { weiter: z.d.weiter } : {}),
    });
    return l ?? null;
}

/** Jüngste nicht gelöschte Zeile (nach der Zeit ihres Starts). */
function aktuelleZeile(): { uid: string; zeile: Zeile } | null {
    let best: { uid: string; zeile: Zeile } | null = null;
    for (const x of db.zeilen(TABELLE))
        if (!best || (x.zeile.z.start ?? '') > (best.zeile.z.start ?? '')) best = x;
    return best;
}

function schreibe(l: Lauf | null): void {
    const alt = aktuelleZeile();
    if (!l) {
        for (const { uid } of db.zeilen(TABELLE)) db.loesche(TABELLE, uid);
        return;
    }
    if (alt && Number(alt.zeile.d.start) === Math.round(l.start)) {
        db.schreibe(TABELLE, alt.uid, felder(l));
        return;
    }
    for (const { uid } of db.zeilen(TABELLE)) db.loesche(TABELLE, uid);
    db.schreibe(TABELLE, neueUid(), felder(l));
}

let uebernehmen = false;
let bekannt = typeof window === 'undefined' ? '' : kernText(timerStore.lauf());

/** Zeitpunkt (ms) der letzten Änderung des laufenden Timers, 0 ohne. */
export function geaendert(): number {
    const z = aktuelleZeile();
    return z ? Math.max(0, ...Object.values(z.zeile.z).map(zeitMs)) : 0;
}

/** Stand von außen setzen (Abgleich oder Haushalt-App). ``eigen``: als eigene Änderung in die Datenbank (kommt aus
 * der Haushalt-App, die anderen Geräte sollen ihn auch bekommen). */
export function uebernimm(l: Lauf | null, _wann: number, eigen: boolean): void {
    uebernehmen = true;
    try {
        if (l) starteLauf(l); // Vergangenes gilt dabei als gemeldet
        else beendeLauf();
    } finally {
        uebernehmen = false;
    }
    bekannt = kernText(timerStore.lauf());
    if (eigen) schreibe(timerStore.lauf());
}

/** Datenbank geändert (Abgleich, anderer Tab): Timer nachziehen, wenn er dort anders aussieht. */
function ausDatenbank(): void {
    const z = aktuelleZeile();
    const l = z ? alsLaufAusZeile(z.zeile) : null;
    const lokal = timerStore.lauf();
    // Vergleich ohne „erstellt“ (zählt nur für die Meldungen dieses Geräts)
    const ohne = (x: Lauf | null) => kernText(x && { ...x, erstellt: 0 });
    if (ohne(l) === ohne(lokal)) return;
    uebernimm(l, 0, false);
}

export function installiereTimerDaten(): void {
    // Timer von vor der Datenbank: einmal übernehmen
    if (timerStore.lauf() && !aktuelleZeile()) schreibe(timerStore.lauf());
    else ausDatenbank();
    timerStore.abonniere(() => {
        const s = kernText(timerStore.lauf());
        if (s === bekannt) return; // nur Meldungen geändert
        bekannt = s;
        if (!uebernehmen) schreibe(timerStore.lauf());
    });
    db.abonniere((fremd) => {
        if (fremd) ausDatenbank();
    });
}
