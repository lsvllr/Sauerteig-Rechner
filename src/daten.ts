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

export const mehlMischungen: Record<string, Mischung> = {
    'roggen-pur': { roggen: 100, dinkel: 0, weizen: 0, buchweizen: 0, name: 'Reines Roggen', beschreibung: 'Traditionell, kräftig, kompakt', eigenschaften: 'Sehr kompakt, intensiver Geschmack' },
    'roggen-optimal': { roggen: 70, dinkel: 20, weizen: 10, buchweizen: 0, name: 'Roggen Optimal', beschreibung: 'Beste Balance: Geschmack + Lockerung', eigenschaften: 'Ausgewogen, gut aufgehend' },
    'roggen-dinkel': { roggen: 60, dinkel: 40, weizen: 0, buchweizen: 0, name: 'Roggen-Dinkel', beschreibung: 'Nussig, bekömmlich, lockerer', eigenschaften: 'Nussiges Aroma, gute Verdaulichkeit' },
    'roggen-weizen': { roggen: 70, dinkel: 0, weizen: 30, buchweizen: 0, name: 'Roggen-Weizen', beschreibung: 'Luftig, mild, familienfreundlich', eigenschaften: 'Sehr locker, milder Geschmack' },
    'vollkorn-mix': { roggen: 50, dinkel: 30, weizen: 15, buchweizen: 5, name: 'Vollkorn-Mix', beschreibung: 'Komplex, nährstoffreich, herzhaft', eigenschaften: 'Komplexer Geschmack, sehr nährstoffreich' },
    'buchweizen-spezial': { roggen: 60, dinkel: 20, weizen: 5, buchweizen: 15, name: 'Buchweizen Spezial', beschreibung: 'Glutenfrei-Anteil, nussig, dunkel', eigenschaften: 'Dunkle Farbe, erdiger Geschmack' },
    'mild-luftig': { roggen: 40, dinkel: 30, weizen: 30, buchweizen: 0, name: 'Mild & Luftig', beschreibung: 'Für Einsteiger, sehr locker', eigenschaften: 'Sehr locker, mild, toast-geeignet' },
    'power-vollkorn': { roggen: 45, dinkel: 25, weizen: 20, buchweizen: 10, name: 'Power Vollkorn', beschreibung: 'Maximum an Nährstoffen', eigenschaften: 'Sehr nährstoffreich, kräftig' }
};

export const tipps: readonly string[] = [
    'Fingertest: Delle federt nur zur Hälfte zurück = fertig',
    'Bei viel Roggen: immer mit feuchten Händen arbeiten',
    'Lieber etwas früher als zu spät backen',
    'Klopftest: Fertiges Brot klingt hohl',
    'Nach dem Backen mindestens 2h auskühlen lassen',
    'Je höher der Roggen-Anteil, desto kompakter das Brot'
];
