/* Rechenkern des Sauerteig-Rechners. Quelle: Haushalt-App (frontend/src/sauerteig/daten.ts); die eigenständige
 * App (github.com/lsvllr/Sauerteig-Rechner) übernimmt ihn mit scripts/sync-haushalt.sh. */
export type Sorte = 'roggen' | 'dinkel' | 'weizen' | 'buchweizen';
export type Anteile = Record<Sorte, number>;

export interface Mischung extends Anteile {
    name: string;
    beschreibung: string;
    eigenschaften: string;
}

export const SORTEN: ReadonlyArray<readonly [Sorte, string]> = [
    ['roggen', 'Roggen'], ['dinkel', 'Dinkel'], ['weizen', 'Weizen'], ['buchweizen', 'Buchweizen']
];

/** Mehl, mit dem das Anstellgut geführt und der Sauerteig angesetzt wird. */
export type SauerteigArt = 'roggen' | 'weizen' | 'dinkel';
export const SAUERTEIG_ARTEN: ReadonlyArray<readonly [SauerteigArt, string]> = [
    ['roggen', 'Roggen'], ['weizen', 'Weizen'], ['dinkel', 'Dinkel']
];

/** Verhältnis Anstellgut : Mehl : Wasser beim Ansetzen. Mehr Futter je Teil Anstellgut: weniger alte Säure, reift
 * länger, schmeckt milder; weniger Futter: schneller und kräftiger. */
export type Verhaeltnis = 'kraeftig' | 'normal' | 'mild';
export const VERHAELTNISSE: ReadonlyArray<{ key: Verhaeltnis; name: string; futter: number }> = [
    { key: 'kraeftig', name: 'Kräftig', futter: 1 },
    { key: 'normal', name: 'Normal', futter: 2 },
    { key: 'mild', name: 'Mild', futter: 5 }
];
export const futterVon = (v: Verhaeltnis): number => VERHAELTNISSE.find((x) => x.key === v)?.futter ?? 2;
/** „1 : 2 : 2“ */
export const verhaeltnisText = (v: Verhaeltnis): string => `1 : ${futterVon(v)} : ${futterVon(v)}`;

export const mehlMischungen: Record<string, Mischung> = {
    'roggen-pur': { roggen: 100, dinkel: 0, weizen: 0, buchweizen: 0, name: 'Reines Roggen', beschreibung: 'Traditionell, kräftig, kompakt', eigenschaften: 'Sehr kompakt, intensiver Geschmack' },
    'roggen-optimal': { roggen: 70, dinkel: 20, weizen: 10, buchweizen: 0, name: 'Roggen Optimal', beschreibung: 'Beste Balance: Geschmack + Lockerung', eigenschaften: 'Ausgewogen, gut aufgehend' },
    'roggen-dinkel': { roggen: 60, dinkel: 40, weizen: 0, buchweizen: 0, name: 'Roggen-Dinkel', beschreibung: 'Nussig, bekömmlich, lockerer', eigenschaften: 'Nussiges Aroma, gute Verdaulichkeit' },
    'roggen-weizen': { roggen: 70, dinkel: 0, weizen: 30, buchweizen: 0, name: 'Roggen-Weizen', beschreibung: 'Luftig, mild, familienfreundlich', eigenschaften: 'Sehr locker, milder Geschmack' },
    'vollkorn-mix': { roggen: 50, dinkel: 30, weizen: 15, buchweizen: 5, name: 'Vollkorn-Mix', beschreibung: 'Komplex, nährstoffreich, herzhaft', eigenschaften: 'Komplexer Geschmack, sehr nährstoffreich' },
    'buchweizen-spezial': { roggen: 60, dinkel: 20, weizen: 5, buchweizen: 15, name: 'Buchweizen Spezial', beschreibung: 'Glutenfrei-Anteil, nussig, dunkel', eigenschaften: 'Dunkle Farbe, erdiger Geschmack' },
    'mild-luftig': { roggen: 40, dinkel: 30, weizen: 30, buchweizen: 0, name: 'Mild & Luftig', beschreibung: 'Für Einsteiger, sehr locker', eigenschaften: 'Sehr locker, mild, toast-geeignet' },
    'power-vollkorn': { roggen: 45, dinkel: 25, weizen: 20, buchweizen: 10, name: 'Power Vollkorn', beschreibung: 'Maximum an Nährstoffen', eigenschaften: 'Sehr nährstoffreich, kräftig' },
    // Weizenteige (Weizen und Dinkel ab 70 %): eigener Ablauf mit Kneten, Dehnen und Falten, Vorformen (rechner.ts)
    'weizen-pur': { roggen: 0, dinkel: 0, weizen: 100, buchweizen: 0, name: 'Reines Weizen', beschreibung: 'Mild, saftig, kräftige Kruste', eigenschaften: 'Locker, offene Krume, milder Geschmack' },
    'weizen-dinkel': { roggen: 0, dinkel: 40, weizen: 60, buchweizen: 0, name: 'Weizen-Dinkel', beschreibung: 'Mild-nussig, locker', eigenschaften: 'Locker, nussiges Aroma' },
    'dinkel-pur': { roggen: 0, dinkel: 100, weizen: 0, buchweizen: 0, name: 'Reines Dinkel', beschreibung: 'Nussig, bekömmlich, nur kurz kneten', eigenschaften: 'Zart, nussig, etwas flacher als Weizen' },
    'weizen-roggen': { roggen: 30, dinkel: 0, weizen: 70, buchweizen: 0, name: 'Weizen-Roggen', beschreibung: 'Weizenbrot mit würziger Roggennote', eigenschaften: 'Locker, kräftiger als reines Weizen' }
};

export const tipps: readonly string[] = [
    'Fingertest: Delle federt nur zur Hälfte zurück = fertig',
    'Bei viel Roggen: immer mit feuchten Händen arbeiten',
    'Weizen und Dinkel: mit wenig Mehl formen und den Teig straff wirken',
    'Lieber etwas früher als zu spät backen',
    'Klopftest: Fertiges Brot klingt hohl',
    'Nach dem Backen mindestens 2h auskühlen lassen',
    'Je höher der Roggen-Anteil, desto kompakter das Brot',
    'Weizenteig kann geformt über Nacht im Kühlschrank gehen (8-14 h) und kommt kalt in den Ofen',
    'Anstellgut aus dem Kühlschrank 1–2 h vorher bei Zimmertemperatur stehen lassen',
    'Warmer Ort für die Gare: Backofen mit eingeschalteter Lampe hat ca. 30 °C'
];
