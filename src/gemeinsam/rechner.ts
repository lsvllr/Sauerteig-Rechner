/* Rechenkern des Sauerteig-Rechners. Quelle: Haushalt-App (frontend/src/sauerteig/rechner.ts); die eigenständige
 * App (github.com/lsvllr/Sauerteig-Rechner) übernimmt ihn mit scripts/sync-haushalt.sh. */
import type { Anteile } from './daten';

export interface Zeitplan {
    sauerteigZeit: string;
    gareZeit: string;
}

export interface Eingabe {
    anstellgut: number;
    sauerteigTemp: number;
    gareTemp: number;
    brotGroesse: number;
    hydration: number;
    anteile: Anteile;
    teigTeilen: boolean;
}

/** [Minuten ab T, Titel, Dauer-Text] */
export type Schritt = [number, string, string];

export interface Rezept {
    anstellgut: number;
    sauerteigMehl: number;
    sauerteigWasser: number;
    sauerteigGesamt: number;
    gesamtMehl: number;
    mehl: Anteile;
    hauptteigWasser: number;
    salz: number;
    kuemmel: string;
    teiggewicht: number;
    einzelGewicht: number;
    hydration: number;
    zeitplan: Zeitplan;
    ersteGare: string;
    stueckgare: string;
    backZeit: string;
    dampfMin: number;
    autolyseZeit: string;
    mitAutolyse: boolean;
    tempHinweis: string;
    eigenschaften: { krume: string; geschmack: string; haltbarkeit: string };
    schritte: Schritt[];
    gesamtDauer: number;
}

export function berechneOptimaleHydration(anteile: Anteile): number {
    const hydrationWerte: Anteile = { roggen: 75, dinkel: 78, weizen: 72, buchweizen: 85 };
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

export function berechneZeitplan(temp: number): Zeitplan {
    if (temp <= 20) return { sauerteigZeit: "10-12h", gareZeit: "90-120 Min" };
    if (temp <= 24) return { sauerteigZeit: "8-10h", gareZeit: "90-120 Min" };
    if (temp <= 28) return { sauerteigZeit: "6-8h", gareZeit: "70-90 Min" };
    return { sauerteigZeit: "4-6h", gareZeit: "50-70 Min" };
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

/** "8-10h" / "45-60 Min" → [min, max] in Minuten */
function spanne(t: string): [number, number] {
    const m = t.match(/(\d+)-(\d+)\s*(h|Min)/);
    if (!m) throw new Error(`Keine Zeitspanne: ${t}`);
    const f = m[3] === 'h' ? 60 : 1;
    return [Number(m[1]) * f, Number(m[2]) * f];
}

const mitte = (r: [number, number]) => Math.round((r[0] + r[1]) / 2);

/** Minuten → "h:mm", auf 5 Minuten gerundet */
export function hm(x: number): string {
    const min = Math.round(x / 5) * 5;
    return Math.floor(min / 60) + ':' + String(min % 60).padStart(2, '0');
}

export function berechneRezept(e: Eingabe): Rezept {
    const { anstellgut, anteile, teigTeilen } = e;

    const sauerteigMehl = anstellgut * 2;
    const sauerteigWasser = anstellgut * 2;
    const sauerteigGesamt = anstellgut + sauerteigMehl + sauerteigWasser;

    const skalierung = (sauerteigGesamt / 600) * (e.brotGroesse / 1200);

    const gesamtMehl = Math.round(360 * skalierung);
    const mehl: Anteile = {
        roggen: Math.round((gesamtMehl * anteile.roggen) / 100),
        dinkel: Math.round((gesamtMehl * anteile.dinkel) / 100),
        weizen: Math.round((gesamtMehl * anteile.weizen) / 100),
        buchweizen: Math.round((gesamtMehl * anteile.buchweizen) / 100)
    };

    const gesamtMehlGesamt = sauerteigMehl + gesamtMehl;
    const gesamtWasserZiel = Math.round((gesamtMehlGesamt * e.hydration) / 100);
    const hauptteigWasser = Math.max(0, gesamtWasserZiel - sauerteigWasser);

    const salz = Math.round(14 * skalierung);
    const kuemmel = (1.5 * skalierung).toFixed(1);

    const teiggewicht = Math.round(sauerteigGesamt + gesamtMehl + hauptteigWasser + salz);
    const hydration = Math.round(((sauerteigWasser + hauptteigWasser) / gesamtMehlGesamt) * 100);

    const zeitplan = berechneZeitplan(e.sauerteigTemp);
    const ersteGare = berechneZeitplan(22).gareZeit;

    const einzelGewicht = teigTeilen ? teiggewicht / 2 : teiggewicht;
    const backZeit = einzelGewicht <= 900 ? "22-26 Min" : einzelGewicht <= 1500 ? "28-32 Min" : "33-38 Min";
    const dampfMin = teigTeilen ? 10 : 15;

    // Stückgare dynamisch nach Roggenanteil & Temperatur
    const stueckgareBase = anteile.roggen >= 80 ? 45 : anteile.roggen >= 60 ? 60 : 90;
    const stueckgareFaktor = e.gareTemp >= 28 ? 0.75 : e.gareTemp >= 24 ? 1.0 : 1.15;
    const stueckgareMin = Math.round(stueckgareBase * stueckgareFaktor);
    const stueckgareMax = Math.round((stueckgareBase + 30) * stueckgareFaktor);
    const stueckgare = stueckgareMin + "-" + stueckgareMax + " Min";

    const tempHinweis = e.sauerteigTemp < 20 ? "Kühl: längere Reifezeit" : e.sauerteigTemp > 28 ? "Warm: Vorsicht vor Überreife" : "";

    const autolyseZeit = anteile.roggen >= 80 ? "— (entfällt bei Roggen)" : anteile.weizen >= 30 ? "60-90 Min" : "45-60 Min";
    const mitAutolyse = anteile.roggen < 80;

    // Ablauf (Mittelwerte der Spannen)
    const bz = spanne(backZeit);
    const tMischen = mitte(spanne(zeitplan.sauerteigZeit));
    const tFormen = tMischen + mitte(spanne(ersteGare));
    const tBacken = tFormen + mitte([stueckgareMin, stueckgareMax]);
    const tOfen = Math.max(tFormen, tBacken - 35);
    const tAus = tBacken + dampfMin + mitte(bz);
    const schritte: Schritt[] = [[0, 'Sauerteig ansetzen', zeitplan.sauerteigZeit]];
    if (mitAutolyse) {
        schritte.push([tMischen - mitte(spanne(autolyseZeit)), 'Autolyse ansetzen (vor Sauerteig-Reife)', autolyseZeit]);
    }
    schritte.push(
        [tMischen, mitAutolyse ? 'Sauerteig + Salz zugeben, erste Gare' : 'Hauptteig mischen, erste Gare', ersteGare],
        [tFormen, 'Formen, Stückgare', stueckgare],
        [tOfen, 'Ofen auf 250°C vorheizen', '30-40 Min'],
        [tBacken, 'Backen', (bz[0] + dampfMin) + '-' + (bz[1] + dampfMin) + ' Min'],
        [tAus, 'Auskühlen', 'min. 2h']
    );

    return {
        anstellgut, sauerteigMehl, sauerteigWasser, sauerteigGesamt,
        gesamtMehl, mehl, hauptteigWasser, salz, kuemmel,
        teiggewicht, einzelGewicht, hydration,
        zeitplan, ersteGare, stueckgare, backZeit, dampfMin,
        autolyseZeit, mitAutolyse, tempHinweis,
        eigenschaften: berechneBrotEigenschaften(anteile),
        schritte, gesamtDauer: tAus
    };
}
