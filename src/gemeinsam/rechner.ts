/* Rechenkern des Sauerteig-Rechners. Quelle: Haushalt-App (frontend/src/sauerteig/rechner.ts); die eigenständige
 * App (github.com/lsvllr/Sauerteig-Rechner) übernimmt ihn mit scripts/sync-haushalt.sh. */
import { futterVon, type Anteile, type SauerteigArt, type Verhaeltnis } from './daten';

export interface Zeitplan {
    sauerteigZeit: string;
    gareZeit: string;
}

export interface Eingabe {
    sauerteigTemp: number;
    gareTemp: number;
    /** Gewünschtes Teiggewicht (g); daraus folgen alle Mengen, auch das Anstellgut */
    brotGroesse: number;
    /** Anstellgut : Mehl : Wasser; fehlt: normal (1 : 2 : 2) */
    verhaeltnis?: Verhaeltnis;
    hydration: number;
    anteile: Anteile;
    teigTeilen: boolean;
    /** Backtemperatur nach der Dampfphase (°C), Standard 220 */
    ofenTemp?: number;
    /** Anbacken mit Dampf (°C), bis 350; fehlt: 250 (nie unter der Ofentemperatur) */
    anbackTemp?: number;
    /** Mehl des Sauerteigs; fehlt: passend zum Brot (sauerteigArtFuer) */
    sauerteigArt?: SauerteigArt;
}

/** Sauerteig passend zum Brot: das Mehl mit dem größten Anteil (Buchweizen zählt nicht, er taugt nicht fürs
 * Anstellgut); bei Gleichstand Roggen vor Weizen vor Dinkel. Wie Rechner.sauerteigArt (iOS). */
export function sauerteigArtFuer(anteile: Anteile): SauerteigArt {
    if (anteile.roggen >= anteile.weizen && anteile.roggen >= anteile.dinkel) return 'roggen';
    return anteile.weizen >= anteile.dinkel ? 'weizen' : 'dinkel';
}

// Alle Mengen zählen das Anstellgut mit: Es ist halb Mehl, halb Wasser. Hydration, Versäuerung und Salz beziehen
// sich auf das ganze Mehl einschließlich des Anstellguts (wie in der Literatur).

/** Salz bezogen aufs ganze Mehl (wie bisher 14 g bei 660 g Mehl). */
const SALZ = 0.021;

/** Versäuerung: Anteil des ganzen Mehls, der im Sauerteig steckt (mit dem Mehl des Anstellguts). Reines
 * Roggenbrot (ab 90 % Roggen) traditionell 50 %, Roggen- und Mischteige 45 % (wie bisher). Weizenteig braucht
 * weniger (üblich 10-30 %), sonst wird er sauer und der Kleber weich. Wie Rechner.versaeuerung (iOS). */
export function versaeuerung(anteile: Anteile): number {
    return istWeizenTeig(anteile) ? 0.2 : anteile.roggen >= 90 ? 0.5 : 0.45;
}

/** Rezepte von vor dem einstellbaren Verhältnis: Anstellgut und „Brotgröße“ ergaben zusammen das Teiggewicht,
 * und die Hydration zählte das Anstellgut nicht mit. Gibt Teiggewicht (auf 100 g) und Hydration mit Anstellgut
 * zurück, damit der Teig gleich bleibt; dazu gehört das Verhältnis 1 : 2 : 2. Wie Rechner.alteWerte (iOS). */
export function alteWerte(anstellgut: number, brotGroesse: number, hydration: number): { brotGroesse: number; hydration: number } {
    const sMehl = anstellgut * 2; // Sauerteig 1 : 2 : 2, Wasser ebenso viel
    const skal = ((anstellgut * 5) / 600) * (brotGroesse / 1200);
    const hauptMehl = Math.round(360 * skal);
    const hauptWasser = Math.max(0, Math.round(((sMehl + hauptMehl) * hydration) / 100) - sMehl);
    const teig = anstellgut + 2 * sMehl + hauptMehl + hauptWasser + Math.round(14 * skal);
    return {
        brotGroesse: Math.min(2000, Math.max(600, Math.round(teig / 100) * 100)),
        hydration: Math.round(((anstellgut / 2 + sMehl + hauptWasser) / (anstellgut / 2 + sMehl + hauptMehl)) * 100)
    };
}

/** Anbacken, wenn nichts gewählt ist. Fest, damit der Regler nicht mit der Ofentemperatur wandert. */
export const ANBACK_STANDARD = 250;

/** Anbacktemperatur: gewählt oder ANBACK_STANDARD, nie unter der Ofentemperatur. */
export function anbackTempAus(ofenTemp: number, gewaehlt?: number): number {
    return Math.max(ofenTemp, gewaehlt ?? ANBACK_STANDARD);
}

/** Dampfphase in Minuten: 15 (zwei Brote 10) bei 250 °C, heißer kürzer, kühler länger, wie bei Pizza. Die Hitze
 * wirkt mit dem Abstand zum Siedepunkt im Teig (T − 100), überproportional (hoch 1,5): 350 °C → 7 Min,
 * 300 °C → 10 Min, 230 °C → 19 Min. Die Zeit danach ändert sich nicht. Wie Rechner.dampfMinuten (iOS). */
export function dampfMinuten(anbackTemp: number, teigTeilen: boolean): number {
    const basis = teigTeilen ? 10 : 15;
    return Math.max(3, Math.round(basis * Math.pow(150 / Math.max(anbackTemp - 100, 50), 1.5)));
}

/** Hauptteig mischen und kneten, danach beginnt die erste Gare. */
const HAUPTTEIG_DAUER = '10 Min';

/** Weizenteig: vorformen und entspannen lassen, bevor straff geformt wird (Minuten, vor der Stückgare). */
export const VORFORMEN_MIN = 20;

/** Weizenteig: Weizen und Dinkel ab 70 %. Bildet ein Klebergerüst, wird also geknetet, in der ersten Gare
 * gedehnt und gefaltet, vorgeformt und straff geformt. Darunter gilt der Ablauf für Roggen- und Mischteige
 * (nur mischen, mit feuchten Händen formen). Wie Rechner.weizenTeig (iOS). */
export function istWeizenTeig(anteile: Anteile): boolean {
    return anteile.weizen + anteile.dinkel >= 70;
}

/** Titel der ersten Gare eines Weizenteigs; darin erinnert der Timer ans Dehnen und Falten (faltZeiten). */
export const GARE_FALTEN = 'Erste Gare, dehnen und falten';

/** Dehnen und Falten: Minuten nach Beginn der ersten Gare, alle 30 Min. 3 Mal, ab 3½ h Stockgare 4 Mal; danach
 * ruht der Teig noch mindestens eine Stunde. Wie Rechner.faltZeiten (iOS). */
export function faltZeiten(ersteGare: string): number[] {
    const [a, b] = spanne(ersteGare);
    return (a + b) / 2 >= 210 ? [30, 60, 90, 120] : [30, 60, 90];
}

/** Vorheizen auf die Anbacktemperatur: heißer dauert länger (Stein oder Topf heizen mit). */
export function vorheizDauer(anbackTemp: number): string {
    return anbackTemp <= 250 ? '30-40 Min' : anbackTemp <= 300 ? '40-50 Min' : '50-60 Min';
}

/** Erste Gare (Stockgare) eines Weizenteigs mit 20 % Versäuerung: länger als bei Roggen und abhängig von der
 * Gare-Temperatur (warm um 28 °C 2-3 h, bei Raumtemperatur 4-6 h). */
export function stockgareWeizen(gareTemp: number): string {
    return gareTemp >= 28 ? '2-3h' : gareTemp >= 24 ? '3-4h' : '4-6h';
}

export type SchrittArt = 'ansetzen' | 'autolyse' | 'mischen' | 'gare' | 'formen' | 'ofen' | 'backen' | 'auskuehlen';

/** [Minuten ab T, Titel, Dauer-Text, Art (für Zutaten und Anleitung im Ablauf)] */
export type Schritt = [number, string, string, SchrittArt?];

export interface Rezept {
    anstellgut: number;
    sauerteigMehl: number;
    sauerteigWasser: number;
    sauerteigGesamt: number;
    gesamtMehl: number;
    mehl: Anteile;
    hauptteigWasser: number;
    salz: number;
    teiggewicht: number;
    einzelGewicht: number;
    hydration: number;
    zeitplan: Zeitplan;
    verhaeltnis: Verhaeltnis;
    /** Prozent des Mehls im Sauerteig */
    versaeuerung: number;
    sauerteigArt: SauerteigArt;
    /** Warnung, wenn der Sauerteig nicht zum Brot passt (viel Roggen, aber kein Roggensauerteig); sonst leer */
    sauerteigHinweis: string;
    ersteGare: string;
    /** Weizenteig: Minuten nach Beginn der ersten Gare zum Dehnen und Falten; sonst leer */
    faltZeiten: number[];
    stueckgare: string;
    vorheizen: string;
    backZeit: string;
    dampfMin: number;
    ofenTemp: number;
    /** Vorheizen und Dampfphase (°C) */
    anbackTemp: number;
    autolyseZeit: string;
    mitAutolyse: boolean;
    /** Weizen und Dinkel ab 70 % (istWeizenTeig): Kneten, Dehnen und Falten, Vorformen */
    weizenTeig: boolean;
    tempHinweis: string;
    eigenschaften: { krume: string; geschmack: string; haltbarkeit: string };
    schritte: Schritt[];
    gesamtDauer: number;
}

export function berechneOptimaleHydration(anteile: Anteile): number {
    // Vollkorn: Weizen nimmt viel Wasser auf und hält es im Kleber; Dinkel nimmt weniger auf, sein Kleber ist
    // schwächer, zu nass wird er klebrig und läuft breit. Wie Rechner.optimaleHydration (iOS).
    // Mit dem Anstellgut gerechnet; Roggen und Buchweizen deshalb 2 % mehr als früher ohne, damit der Teig gleich bleibt.
    const hydrationWerte: Anteile = { roggen: 77, dinkel: 72, weizen: 77, buchweizen: 87 };
    return Math.round((anteile.roggen * hydrationWerte.roggen + anteile.dinkel * hydrationWerte.dinkel + anteile.weizen * hydrationWerte.weizen + anteile.buchweizen * hydrationWerte.buchweizen) / 100);
}

/** Skaliert die Anteile auf 100 % in 5er-Schritten; null, wenn alle 0 sind. */
export function normalisiere(werte: Anteile): Anteile | null {
    const summe = werte.roggen + werte.dinkel + werte.weizen + werte.buchweizen;
    if (summe === 0) return null;
    const norm: Anteile = {
        roggen: Math.round((werte.roggen / summe) * 20) * 5,
        dinkel: Math.round((werte.dinkel / summe) * 20) * 5,
        weizen: Math.round((werte.weizen / summe) * 20) * 5,
        buchweizen: Math.round((werte.buchweizen / summe) * 20) * 5
    };
    const neueSumme = norm.roggen + norm.dinkel + norm.weizen + norm.buchweizen;
    if (neueSumme !== 100) {
        const max = (Object.keys(norm) as (keyof Anteile)[]).reduce((a, b) => norm[a] >= norm[b] ? a : b);
        norm[max] += 100 - neueSumme;
    }
    return norm;
}

/** Reifezeit des Sauerteigs je Sauerteig, Verhältnis und Temperatur (bis 20, bis 24, bis 28, darüber °C).
 * 1 : 2 : 2 wie bisher; 1 : 1 : 1 reift etwa ein Drittel schneller, 1 : 5 : 5 rund die Hälfte länger. Weizen- und
 * Dinkelsauerteig sind schneller als Roggensauerteig. Wie Rechner.reife (iOS). */
const REIFE: Record<'roggen' | 'weizen', Record<Verhaeltnis, readonly [string, string, string, string]>> = {
    roggen: {
        kraeftig: ["7-9h", "5-7h", "4-5h", "3-4h"],
        normal: ["10-12h", "8-10h", "6-8h", "4-6h"],
        mild: ["14-16h", "11-14h", "8-10h", "6-8h"]
    },
    weizen: {
        kraeftig: ["5-7h", "4-5h", "3-4h", "2-3h"],
        normal: ["8-10h", "6-8h", "4-6h", "3-5h"],
        mild: ["11-14h", "8-10h", "6-8h", "5-6h"]
    }
};

/** Reifezeit des Sauerteigs und Gare nach Temperatur. */
export function berechneZeitplan(temp: number, art: SauerteigArt = 'roggen', verhaeltnis: Verhaeltnis = 'normal'): Zeitplan {
    const stufe = temp <= 20 ? 0 : temp <= 24 ? 1 : temp <= 28 ? 2 : 3;
    const gareZeit = ["90-120 Min", "90-120 Min", "70-90 Min", "50-70 Min"][stufe]!;
    return { sauerteigZeit: REIFE[art === 'roggen' ? 'roggen' : 'weizen'][verhaeltnis][stufe], gareZeit };
}

export function berechneBrotEigenschaften(anteile: Anteile): Rezept['eigenschaften'] {
    const r = anteile.roggen, b = anteile.buchweizen, w = anteile.weizen;
    let krume: string, geschmack: string, haltbarkeit: string;
    if (r >= 80) {
        krume = "Sehr kompakt, dichte Krume";
        geschmack = "Kräftig-säuerlich, traditionell";
        haltbarkeit = "5-7 Tage";
    } else if (r >= 60) {
        krume = "Kompakt, mitteldichte Krume";
        geschmack = "Mittel-kräftig, ausgewogen";
        haltbarkeit = "4-5 Tage";
    } else if (r >= 40) {
        krume = "Ausgewogen, mittel-locker";
        geschmack = "Mild-kräftig, harmonisch";
        haltbarkeit = "3-4 Tage";
    } else {
        krume = "Locker, luftige Krume";
        geschmack = "Mild, leicht säuerlich";
        haltbarkeit = "2-3 Tage";
    }
    if (b > 10) {
        krume += ", erdige Note";
        geschmack += ", nussig-erdig";
    }
    if (w > 25) krume = krume.replace("kompakt", "lockerer");
    return { krume, geschmack, haltbarkeit };
}

/** Geschmack nach dem Verhältnis beim Ansetzen. */
function mitSaeure(e: Rezept['eigenschaften'], v: Verhaeltnis): Rezept['eigenschaften'] {
    const zusatz = v === 'mild' ? ', milde Säure' : v === 'kraeftig' ? ', kräftigere Säure' : '';
    return { ...e, geschmack: e.geschmack + zusatz };
}

/** "8-10h" / "45-60 Min" / "10 Min" → [min, max] in Minuten (Einzelwert: min = max) */
export function spanne(t: string): [number, number] {
    const m = t.match(/(\d+)(?:-(\d+))?\s*(h|Min)/);
    if (!m) throw new Error(`Keine Zeitspanne: ${t}`);
    const f = m[3] === 'h' ? 60 : 1;
    return [Number(m[1]) * f, Number(m[2] ?? m[1]) * f];
}

const mitte = (r: [number, number]) => Math.round((r[0] + r[1]) / 2);

/** Minuten → "h:mm", auf 5 Minuten gerundet */
export function hm(x: number): string {
    const min = Math.round(x / 5) * 5;
    return Math.floor(min / 60) + ':' + String(min % 60).padStart(2, '0');
}

/** Minuten → „3h 15m“ (bzw. „3h“ / „45m“), auf 5 Minuten gerundet. */
export function hmKurz(x: number): string {
    const min = Math.round(x / 5) * 5;
    const h = Math.floor(min / 60), m = min % 60;
    if (h === 0) return `${m}m`;
    return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function berechneRezept(e: Eingabe): Rezept {
    const { anteile, teigTeilen } = e;
    const verhaeltnis = e.verhaeltnis ?? 'normal';

    // Ganzes Mehl aus dem Teiggewicht: Teig = Mehl × (1 + Hydration + Salz). Im Sauerteig steckt der Anteil v
    // davon, als Anstellgut (halb Mehl) und Futter (je Teil Anstellgut `futter` Teile Mehl und Wasser):
    // Mehl im Sauerteig = Anstellgut × (futter + ½) = v × Mehl.
    const v = versaeuerung(anteile);
    const futter = futterVon(verhaeltnis);
    const mehlGanz = Math.round(e.brotGroesse / (1 + e.hydration / 100 + SALZ));
    const anstellgut = Math.round((v * mehlGanz) / (futter + 0.5));
    const imAnstellgut = Math.round(anstellgut / 2); // Mehl bzw. Wasser im Anstellgut
    const sauerteigMehl = anstellgut * futter;
    const sauerteigWasser = sauerteigMehl;
    const sauerteigGesamt = anstellgut + sauerteigMehl + sauerteigWasser;

    const gesamtMehl = Math.max(0, mehlGanz - imAnstellgut - sauerteigMehl);
    const mehl: Anteile = {
        roggen: Math.round((gesamtMehl * anteile.roggen) / 100),
        dinkel: Math.round((gesamtMehl * anteile.dinkel) / 100),
        weizen: Math.round((gesamtMehl * anteile.weizen) / 100),
        buchweizen: Math.round((gesamtMehl * anteile.buchweizen) / 100)
    };

    const gesamtWasserZiel = Math.round((mehlGanz * e.hydration) / 100);
    const hauptteigWasser = Math.max(0, gesamtWasserZiel - imAnstellgut - sauerteigWasser);

    const salz = Math.round(mehlGanz * SALZ);

    const teiggewicht = Math.round(sauerteigGesamt + gesamtMehl + hauptteigWasser + salz);
    const hydration = Math.round(((imAnstellgut + sauerteigWasser + hauptteigWasser) / mehlGanz) * 100);

    const sauerteigArt = e.sauerteigArt ?? sauerteigArtFuer(anteile);
    const zeitplan = berechneZeitplan(e.sauerteigTemp, sauerteigArt, verhaeltnis);
    const sauerteigHinweis = sauerteigArt !== 'roggen' && anteile.roggen >= 50
        ? "Viel Roggen im Teig: Für den Sauerteig besser Roggenmehl nehmen, sonst wird die Krume klebrig."
        : "";
    const weizenTeig = istWeizenTeig(anteile);
    // Roggen- und Mischteige: feste erste Gare. Reines Roggenbrot nur eine kurze Teigruhe (das Mehl quillt, gehen
    // soll es in der Stückgare). Weizenteige brauchen länger (Kleber reift, Dehnen und Falten).
    const ersteGare = weizenTeig ? stockgareWeizen(e.gareTemp) : anteile.roggen >= 90 ? "30-45 Min" : "90-120 Min";

    const einzelGewicht = teigTeilen ? teiggewicht / 2 : teiggewicht;
    // Backzeit bei 220 °C nach Gewicht; je 10 °C heißer rund 7 % kürzer, kühler entsprechend länger.
    const ofenTemp = e.ofenTemp ?? 220;
    const anbackTemp = anbackTempAus(ofenTemp, e.anbackTemp);
    const basis: [number, number] = einzelGewicht <= 900 ? [22, 26] : einzelGewicht <= 1500 ? [28, 32] : [33, 38];
    const faktor = 1 + (220 - ofenTemp) * 0.007;
    const backZeit = Math.round(basis[0] * faktor) + "-" + Math.round(basis[1] * faktor) + " Min";
    const dampfMin = dampfMinuten(anbackTemp, teigTeilen);

    // Stückgare nach Brotart und Temperatur (Basis bei 24-27 °C). Reines Roggenbrot bis zu Rissen in der
    // Oberfläche (bei 25 °C etwa 1-1½ h), Weizenteig mit 20 % Versäuerung 1¼-1¾ h.
    const stueckgareBase = weizenTeig ? 75 : anteile.roggen >= 60 ? 60 : 90;
    const stueckgareFaktor = e.gareTemp >= 28 ? 0.75 : e.gareTemp >= 24 ? 1.0 : 1.15;
    const stueckgareMin = Math.round(stueckgareBase * stueckgareFaktor);
    const stueckgareMax = Math.round((stueckgareBase + 30) * stueckgareFaktor);
    const stueckgare = stueckgareMin + "-" + stueckgareMax + " Min";

    const tempHinweis = e.sauerteigTemp < 20 ? "Kühl: längere Reifezeit" : e.sauerteigTemp > 28 ? "Warm: Vorsicht vor Überreife" : "";

    // Dinkel verträgt keine lange Autolyse (der Kleber wird weich), Weizen braucht länger.
    const autolyseZeit = anteile.roggen >= 80 ? "— (entfällt bei Roggen)" : anteile.dinkel >= 70 ? "30-45 Min" : anteile.weizen >= 30 ? "60-90 Min" : "45-60 Min";
    const mitAutolyse = anteile.roggen < 80;

    // Ablauf (Mittelwerte der Spannen)
    const bz = spanne(backZeit);
    const tMischen = mitte(spanne(zeitplan.sauerteigZeit));
    const tGare = tMischen + mitte(spanne(HAUPTTEIG_DAUER));
    const tFormen = tGare + mitte(spanne(ersteGare));
    // Der Ofen heizt während der Stückgare vor. Ist die kürzer als das Vorheizen, wartet das Backen auf den Ofen
    // (die Stückgare wird etwas länger, bleibt aber in ihrer Spanne).
    const vorheizen = vorheizDauer(anbackTemp);
    const vh = mitte(spanne(vorheizen));
    const tStueckEnde = tFormen + (weizenTeig ? VORFORMEN_MIN : 0) + mitte([stueckgareMin, stueckgareMax]);
    const tOfen = Math.max(tFormen, tStueckEnde - vh);
    const tBacken = Math.max(tStueckEnde, tOfen + vh);
    const tAus = tBacken + dampfMin + mitte(bz);
    const schritte: Schritt[] = [[0, 'Sauerteig ansetzen', zeitplan.sauerteigZeit, 'ansetzen']];
    if (mitAutolyse) {
        schritte.push([tMischen - mitte(spanne(autolyseZeit)), 'Autolyse ansetzen (vor Sauerteig-Reife)', autolyseZeit, 'autolyse']);
    }
    // Roggen kommt erst nach der Autolyse dazu (bringt dort nichts); was genau, steht in der Anleitung des Schritts.
    schritte.push(
        [tMischen, 'Hauptteig', HAUPTTEIG_DAUER, 'mischen'],
        [tGare, weizenTeig ? GARE_FALTEN : 'Erste Gare', ersteGare, 'gare'],
        [tFormen, 'Formen, Stückgare', stueckgare, 'formen'],
        [tOfen, `Ofen auf ${anbackTemp} °C vorheizen`, vorheizen, 'ofen'],
        [tBacken, 'Backen', (bz[0] + dampfMin) + '-' + (bz[1] + dampfMin) + ' Min', 'backen'],
        [tAus, 'Auskühlen', 'min. 2h', 'auskuehlen']
    );

    return {
        anstellgut, sauerteigMehl, sauerteigWasser, sauerteigGesamt,
        gesamtMehl, mehl, hauptteigWasser, salz,
        teiggewicht, einzelGewicht, hydration,
        zeitplan, verhaeltnis, versaeuerung: Math.round(v * 100), sauerteigArt, sauerteigHinweis, ersteGare, faltZeiten: weizenTeig ? faltZeiten(ersteGare) : [], stueckgare, vorheizen, backZeit, dampfMin, ofenTemp, anbackTemp,
        autolyseZeit, mitAutolyse, weizenTeig, tempHinweis,
        eigenschaften: mitSaeure(berechneBrotEigenschaften(anteile), verhaeltnis),
        schritte, gesamtDauer: tAus
    };
}
