/* Oberfläche des Sauerteig-Rechners – gemeinsam für die Haushalt-App (/backen) und die eigenständige App
 * (Sauerteig-Repo, kopiert per scripts/sync-haushalt.sh). Rechnet im Browser; wo Rezepte liegen und wie
 * gesichert und gelöscht wird, bestimmt die einbindende App (Props). Braucht das CSS der Haushalt-App
 * (app/static/style.css) und sauerteig.css. */
import { useEffect, useState } from 'react';
import type { CSSProperties, Dispatch, FormHTMLAttributes, ReactNode, SetStateAction } from 'react';
import {
  SAUERTEIG_ARTEN,
  SORTEN,
  VERHAELTNISSE,
  mehlMischungen,
  tipps,
  verhaeltnisText,
  type Anteile,
  type SauerteigArt,
  type Sorte,
  type Verhaeltnis,
} from './daten';
import {
  ANBACK_STANDARD,
  VORFORMEN_MIN,
  alteWerte,
  berechneOptimaleHydration,
  berechneRezept,
  hm,
  hmKurz,
  normalisiere,
  sauerteigArtFuer,
  spanne,
  type Rezept as Berechnung,
  type SchrittArt,
} from './rechner';
import { Symbol } from './symbole';
import { BEGINN, hakeAb, offenAb, uhrzeit, type Lauf } from './timer';
import { TimerKarte, TimerStart, useJetzt, useLauf, useMeldungen } from './TimerKarte';
import './sauerteig.css';

export interface Werte {
  sauerteigTemp: number;
  gareTemp: number;
  /** Teiggewicht (g); das Anstellgut rechnet der Rechner daraus */
  brotGroesse: number;
  /** Anstellgut : Mehl : Wasser beim Ansetzen */
  verhaeltnis: Verhaeltnis;
  hydration: number;
  mischung: string;
  custom: Anteile;
  teigTeilen: boolean;
  ofenTemp: number;
  /** Anbacken mit Dampf (°C); fehlt: automatisch (anbackTempAus) */
  anbackTemp?: number;
  /** Mehl des Sauerteigs; fehlt: passend zum Brot (sauerteigArtFuer), bei Mischungswechsel wieder automatisch */
  sauerteigArt?: SauerteigArt;
}

const istSauerteigArt = (v: unknown): v is SauerteigArt => SAUERTEIG_ARTEN.some(([k]) => k === v);
/** Ab so viel Anstellgut (g) der Hinweis, es vorher zu vermehren. */
const ANSTELLGUT_VIEL = 150;
const istVerhaeltnis = (v: unknown): v is Verhaeltnis => VERHAELTNISSE.some((x) => x.key === v);

const START_MISCHUNG = 'roggen-optimal';
export const START: Werte = {
  sauerteigTemp: 22,
  gareTemp: 30,
  brotGroesse: 1200,
  verhaeltnis: 'normal',
  hydration: berechneOptimaleHydration(mehlMischungen[START_MISCHUNG]!),
  mischung: START_MISCHUNG,
  custom: { roggen: 70, dinkel: 20, weizen: 10, buchweizen: 0 },
  teigTeilen: false,
  ofenTemp: 220,
};

const anteileVon = (w: Werte): Anteile =>
  w.mischung === 'custom' ? w.custom : (mehlMischungen[w.mischung] ?? mehlMischungen[START_MISCHUNG]!);

/** Format der eigenständigen App (Einstellungen in speicher.ts): Zahlen als Strings. */
export function alsEinstellungen(w: Werte): Record<string, string | boolean> {
  return {
    sauerteigTemp: String(w.sauerteigTemp),
    gareTemp: String(w.gareTemp),
    brotGroesse: String(w.brotGroesse),
    verhaeltnis: w.verhaeltnis,
    hydration: String(w.hydration),
    mehlMischung: w.mischung,
    customRoggen: String(w.custom.roggen),
    customDinkel: String(w.custom.dinkel),
    customWeizen: String(w.custom.weizen),
    customBuchweizen: String(w.custom.buchweizen),
    teigTeilen: w.teigTeilen,
    ofenTemp: String(w.ofenTemp),
    ...(w.anbackTemp !== undefined ? { anbackTemp: String(w.anbackTemp) } : {}),
    ...(w.sauerteigArt ? { sauerteigArt: w.sauerteigArt } : {}),
  };
}

function ausEinstellungen(e: Record<string, unknown>): Werte {
  const n = (k: string, d: number) => {
    const v = parseInt(String(e[k] ?? ''), 10);
    return Number.isFinite(v) ? v : d;
  };
  const mischung =
    typeof e.mehlMischung === 'string' && (e.mehlMischung === 'custom' || e.mehlMischung in mehlMischungen)
      ? e.mehlMischung
      : START_MISCHUNG;
  // Rezepte von vor dem einstellbaren Verhältnis: Anstellgut und „Brotgröße“ ergaben zusammen das Teiggewicht, die
  // Hydration zählte das Anstellgut nicht mit. Umgerechnet, damit der Teig gleich bleibt.
  const neu = istVerhaeltnis(e.verhaeltnis);
  const alt = alteWerte(n('anstellgut', 120), n('brotGroesse', START.brotGroesse), n('hydration', 75));
  return {
    sauerteigTemp: n('sauerteigTemp', START.sauerteigTemp),
    gareTemp: n('gareTemp', START.gareTemp),
    brotGroesse: neu ? n('brotGroesse', START.brotGroesse) : alt.brotGroesse,
    verhaeltnis: neu ? (e.verhaeltnis as Verhaeltnis) : 'normal',
    hydration: neu ? n('hydration', START.hydration) : alt.hydration,
    mischung,
    custom: {
      roggen: n('customRoggen', START.custom.roggen),
      dinkel: n('customDinkel', START.custom.dinkel),
      weizen: n('customWeizen', START.custom.weizen),
      buchweizen: n('customBuchweizen', START.custom.buchweizen),
    },
    teigTeilen: typeof e.teigTeilen === 'boolean' ? e.teigTeilen : false,
    ofenTemp: n('ofenTemp', START.ofenTemp),
    ...(Number.isFinite(parseInt(String(e.anbackTemp ?? ''), 10)) ? { anbackTemp: n('anbackTemp', 250) } : {}),
    ...(istSauerteigArt(e.sauerteigArt) ? { sauerteigArt: e.sauerteigArt } : {}),
  };
}

function Regler(props: {
  id: string;
  label: ReactNode;
  wert: ReactNode;
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (v: number) => void;
}) {
  const p = ((props.value - props.min) / (props.max - props.min)) * 100;
  return (
    <div className="sd-slider">
      <div className="sd-slider-top">
        <label htmlFor={props.id}>{props.label}</label>
        <span className="sd-val">{props.wert}</span>
      </div>
      <input
        type="range"
        id={props.id}
        className="snap-range"
        min={props.min}
        max={props.max}
        step={props.step ?? 1}
        value={props.value}
        style={{ '--p': `${p}%` } as CSSProperties}
        onChange={(e) => props.onChange(parseInt(e.currentTarget.value, 10))}
      />
    </div>
  );
}

function Zeile({ label, children, dot }: { label: ReactNode; children: ReactNode; dot?: string }) {
  return (
    <li>
      <span className="sd-label">
        {dot && <i className="sd-dot" style={{ background: dot }} />}
        {label}
      </span>
      <span className="sd-num">{children}</span>
    </li>
  );
}

const MEHL_NAME: Record<Sorte, string> = {
  roggen: 'Roggen-Vollkornmehl',
  dinkel: 'Dinkel-Vollkornmehl',
  weizen: 'Weizen-Vollkornmehl',
  buchweizen: 'Buchweizenmehl',
};

function Mehle({ r, ohneRoggen, nurRoggen }: { r: Berechnung; ohneRoggen?: boolean; nurRoggen?: boolean }) {
  return (
    <>
      {SORTEN.filter(([k]) => r.mehl[k] > 0 && (ohneRoggen ? k !== 'roggen' : nurRoggen ? k === 'roggen' : true)).map(
        ([k]) => (
          <Zeile key={k} label={MEHL_NAME[k]} dot={`var(--mehl-${k})`}>
            {r.mehl[k]} g
          </Zeile>
        ),
      )}
    </>
  );
}

function SauerteigSalz({ r }: { r: Berechnung }) {
  return (
    <>
      <Zeile label="Aktiver Sauerteig">{r.sauerteigGesamt} g</Zeile>
      <Zeile label="Salz">{r.salz} g</Zeile>
      <Zeile label={<span className="muted">ggf. Gewürze/Nüsse</span>}>{null}</Zeile>
    </>
  );
}

/** Erklärung zum Mehl des Sauerteigs (Roggen- oder Weizensauerteig); wie SauerteigDaten.mehlInfo (iOS). */
export const SAUERTEIG_MEHL_INFO = [
  'Roggen, Weizen oder Dinkel, je nach Sauerteig: das Mehl, mit dem du dein Anstellgut führst, am besten Vollkorn. Einstellen unter „Anstellgut“; vorgewählt ist das Hauptmehl des Brotes.',
  'Weizen- und Dinkelsauerteig reifen schneller und schmecken milder. Hat er sich verdoppelt, ist er reif: Dann gleich weiter, sonst wird er sauer und verliert Triebkraft.',
  'Bei Broten mit viel Roggen (ab etwa der Hälfte) besser Roggenmehl nehmen, auch für ein Weizen-Anstellgut. Roggen braucht die Säure des Sauerteigs, sonst wird die Krume klebrig.',
];

function SauerteigAnsetzen({ r, w }: { r: Berechnung; w: Werte }) {
  const [info, setInfo] = useState(false);
  return (
    <>
      <ul className="sd-rows">
        <Zeile label="Anstellgut">{r.anstellgut} g</Zeile>
        <Zeile
          label={
            <>
              {MEHL_NAME[r.sauerteigArt]}
              <button
                type="button"
                className="info-btn"
                aria-expanded={info}
                aria-controls="sd-mehl-info"
                aria-label="Welches Mehl?"
                onClick={() => setInfo(!info)}
              >
                i
              </button>
            </>
          }
          dot={`var(--mehl-${r.sauerteigArt})`}
        >
          {r.sauerteigMehl} g
        </Zeile>
        <Zeile label="Wasser" dot="var(--mehl-wasser)">
          {r.sauerteigWasser} ml
        </Zeile>
      </ul>
      {info && (
        <div className="info-panel" id="sd-mehl-info" style={{ margin: '0 0 12px' }}>
          {SAUERTEIG_MEHL_INFO.map((t) => (
            <p key={t}>{t}</p>
          ))}
        </div>
      )}
      {r.sauerteigHinweis && <div className="sd-note">{r.sauerteigHinweis}</div>}
      {r.tempHinweis && <div className="sd-note">{r.tempHinweis}</div>}
      <ol className="sd-steps">
        <li>Anstellgut, Mehl und Wasser ({verhaeltnisText(r.verhaeltnis)}) gründlich verrühren.</li>
        <li>
          Abgedeckt bei {w.sauerteigTemp} °C <strong>{r.zeitplan.sauerteigZeit}</strong> reifen lassen.
        </li>
        <li>
          {r.sauerteigArt === 'roggen'
            ? 'Reif, wenn er Blasen wirft, gewölbt ist, feine Risse an der Oberfläche zeigt und säuerlich riecht.'
            : 'Reif, wenn er sich etwa verdoppelt hat, gewölbt und durchgehend blasig ist und mild säuerlich riecht.'}{' '}
          Ergibt ca. {r.sauerteigGesamt} g.
        </li>
      </ol>
    </>
  );
}

/** [30, 60, 90] → „30, 60 und 90“ */
const aufzaehlung = (z: number[]) => (z.length > 1 ? `${z.slice(0, -1).join(', ')} und ${z[z.length - 1]}` : String(z[0] ?? ''));

/** Weizenteig: kneten statt nur mischen, damit sich der Kleber bildet. */
function Kneten({ r }: { r: Berechnung }) {
  return (
    <>
      <li>
        Alles zum Autolyseteig geben und kneten, bis der Teig glatt ist und sich vom Schüsselrand löst: von Hand ca. 10
        Min{r.mehl.dinkel > r.mehl.weizen ? ', Dinkel nur ca. 5 Min, er verträgt kein langes Kneten' : ''}.
      </li>
      <li>Fenstertest: Ein Stück Teig lässt sich dünn ausziehen, ohne gleich zu reißen (Vollkorn reißt etwas früher).</li>
    </>
  );
}

/** Zutaten und Anleitung eines Schritts im Ablauf. */
function Anleitung({ art, r, w }: { art: SchrittArt | undefined; r: Berechnung; w: Werte }) {
  switch (art) {
    case 'ansetzen':
      return <SauerteigAnsetzen r={r} w={w} />;
    case 'autolyse':
      return (
        <>
          <ul className="sd-rows">
            <Mehle r={r} ohneRoggen />
            <Zeile label="Warmes Wasser" dot="var(--mehl-wasser)">
              {r.hauptteigWasser} ml
            </Zeile>
          </ul>
          <ol className="sd-steps">
            <li>Mehl und warmes Wasser verrühren, bis kein trockenes Mehl mehr zu sehen ist.</li>
            <li>
              Abgedeckt <strong>{r.autolyseZeit}</strong> ruhen lassen.
              {r.mehl.roggen > 0 && ' Das Roggenmehl kommt erst danach dazu.'}
            </li>
          </ol>
        </>
      );
    case 'mischen':
      return r.mitAutolyse ? (
        <>
          <div className="day-head">Zum Autolyseteig geben</div>
          <ul className="sd-rows">
            <Mehle r={r} nurRoggen />
            <SauerteigSalz r={r} />
          </ul>
          <ol className="sd-steps">
            {r.weizenTeig ? (
              <Kneten r={r} />
            ) : (
              <li>Alles zum Autolyseteig geben und gründlich verkneten, mit feuchten Händen.</li>
            )}
          </ol>
        </>
      ) : (
        <>
          <ul className="sd-rows">
            <Mehle r={r} />
            <Zeile label="Warmes Wasser" dot="var(--mehl-wasser)">
              {r.hauptteigWasser} ml
            </Zeile>
            <SauerteigSalz r={r} />
          </ul>
          <ol className="sd-steps">
            <li>Alles gründlich zu einem Teig mischen, mit feuchten Händen.</li>
          </ol>
        </>
      );
    case 'gare':
      return r.weizenTeig ? (
        <ol className="sd-steps">
          <li>
            Abgedeckt bei {w.gareTemp} °C gehen lassen: <strong>{r.ersteGare}</strong>.
          </li>
          <li>
            Nach <strong>{aufzaehlung(r.faltZeiten)} Min</strong> dehnen und falten: mit nasser Hand eine Seite
            hochziehen und über die Mitte legen, Schüssel drehen, rundum wiederholen. Danach in Ruhe gehen lassen.
          </li>
          <li>Fertig, wenn der Teig um etwa die Hälfte gewachsen, gewölbt und luftig ist und Blasen am Rand zeigt.</li>
        </ol>
      ) : (
        <ol className="sd-steps">
          <li>
            Abgedeckt bei {w.gareTemp} °C gehen lassen: <strong>{r.ersteGare}</strong>.
          </li>
          <li>Fertig, wenn der Teig sichtbar aufgegangen ist und Blasen zeigt.</li>
        </ol>
      );
    case 'formen':
      return r.weizenTeig ? (
        <ol className="sd-steps">
          <li>
            Teig auf eine leicht bemehlte Fläche geben
            {w.teigTeilen ? `, halbieren (je ca. ${Math.round(r.einzelGewicht)} g)` : ''} und rund vorformen.{' '}
            {VORFORMEN_MIN} Min entspannen lassen.
          </li>
          <li>Straff formen, rund oder länglich, mit dem Schluss nach oben in einen bemehlten Gärkorb legen.</li>
          <li>
            Stückgare bei {w.gareTemp} °C: <strong>{r.stueckgare}</strong>. Fertig, wenn eine Delle langsam und nicht
            ganz zurückfedert.
          </li>
          <li>Oder abgedeckt über Nacht in den Kühlschrank (8-14 h) und kalt backen.</li>
        </ol>
      ) : (
        <ol className="sd-steps">
          {w.teigTeilen && <li>Teig halbieren, je ca. {Math.round(r.einzelGewicht)} g.</li>}
          <li>Mit feuchten Händen rundwirken, in einen bemehlten Gärkorb legen.</li>
          <li>
            Stückgare bei {w.gareTemp} °C: <strong>{r.stueckgare}</strong>. Fertig, wenn eine Delle nur zur Hälfte
            zurückfedert.
          </li>
        </ol>
      );
    case 'ofen':
      return (
        <ol className="sd-steps">
          <li>
            Ofen auf <strong>{r.anbackTemp} °C</strong> vorheizen ({r.vorheizen}), mittlere Schiene, noch während der
            Stückgare.
          </li>
          <li>Schüssel zum Abdecken oder ein Gefäß für Wasser (Schwaden) bereitstellen.</li>
        </ol>
      );
    case 'backen':
      return (
        <ol className="sd-steps">
          <li>
            {r.weizenTeig
              ? 'Stürzen und einmal längs einschneiden, flach angesetzt und ca. 1 cm tief.'
              : 'Stürzen und kreuzförmig einschneiden.'}
          </li>
          <li>
            {r.dampfMin} Min bei {r.anbackTemp} °C <strong>mit Dampf</strong>{' '}
            {w.teigTeilen ? '(2 Brote → engere Dampfphase)' : '(Schüssel über Brot oder Schwaden)'}.
          </li>
          <li>
            {r.anbackTemp > r.ofenTemp ? `Auf ${r.ofenTemp} °C herunterschalten, ` : 'Dann '}
            {r.backZeit} <strong>ohne Dampf</strong> backen.
          </li>
          <li>Klopftest: Fertiges Brot klingt hohl.</li>
        </ol>
      );
    case 'auskuehlen':
      return (
        <ol className="sd-steps">
          <li>Auf einem Gitter mindestens 2 Stunden auskühlen lassen, erst dann anschneiden.</li>
        </ol>
      );
    default:
      return null;
  }
}

/** Dauer-Text („45-60 Min“, „8-10h“, „min. 2h“) → Minuten (Mitte der Spanne, auf 5 gerundet). */
function dauerMinuten(d: string): number {
  try {
    const [a, b] = spanne(d);
    return Math.round((a + b) / 10) * 5;
  } catch {
    const m = d.match(/(\d+)\s*h/);
    return m ? Number(m[1]) * 60 : 0;
  }
}

/** Alle Schritte mit Zutaten und Anleitung; immer nur einer ist offen. Läuft der Timer, sind die Zeiten
 * Uhrzeiten, der nächste offene Schritt klappt von selbst auf und lässt sich abhaken. */

const hhmm = (ms: number) => {
  const d = new Date(ms);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};

/** „HH:MM“ als letzter solcher Zeitpunkt bis jetzt (später als jetzt → gestern). */
function zeitpunkt(hm: string, jetzt: number): number | null {
  const [h, m] = hm.split(':').map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  const d = new Date(jetzt);
  d.setHours(h!, m!, 0, 0);
  if (d.getTime() > jetzt) d.setDate(d.getDate() - 1);
  return d.getTime();
}

/** Schritt abhaken oder aktualisieren; über die Uhr daneben mit anderer Uhrzeit (Weiterklicken vergessen). */
function Abhaken({ l, i, erledigt, jetzt, fertig }: {
  l: Lauf;
  i: number;
  erledigt: boolean;
  jetzt: number;
  fertig: () => void;
}) {
  // null = jetzt; sonst die eingestellte Uhrzeit (beim Öffnen die aktuelle)
  const [zeit, setZeit] = useState<string | null>(null);
  const am = zeit === null ? null : zeitpunkt(zeit, jetzt);
  const label = erledigt ? 'Aktualisieren' : 'Erledigt';
  return (
    <div className="sd-no-print sd-abhaken">
      <span className="sd-abhaken-knoepfe">
        <button
          type="button"
          className={erledigt ? 'btn' : 'btn accent-fill'}
          disabled={zeit !== null && am === null}
          onClick={() => {
            hakeAb(i, am ?? undefined);
            fertig();
          }}
        >
          <Symbol name="check" size={18} />
          {am === null ? label : `${label}: ${uhrzeit(am, jetzt)}`}
        </button>
        <button
          type="button"
          className={zeit === null ? 'btn icon-btn' : 'btn icon-btn accent-fill'}
          aria-label="Andere Uhrzeit"
          aria-pressed={zeit !== null}
          onClick={() => setZeit(zeit === null ? hhmm(Date.now()) : null)}
        >
          <Symbol name="clock" size={20} />
        </button>
      </span>
      {zeit !== null && (
        <label className="sd-abhaken-zeit">
          <span className="muted small">{erledigt ? 'Erledigt um' : 'Erledigt schon um'}</span>
          <input type="time" value={zeit} onChange={(e) => setZeit(e.target.value)} />
        </label>
      )}
      {erledigt && zeit === null && (
        <span className="muted small">
          Erledigt um {uhrzeit(l.schritte[i]!.at, jetzt)}. Aktualisieren setzt ihn auf jetzt, die folgenden Schritte
          rücken mit. Mit der Uhr eine andere Uhrzeit wählen.
        </span>
      )}
    </div>
  );
}

function Ablauf({
  r,
  w,
  oeffneBlatt,
  melde,
}: {
  r: Berechnung;
  w: Werte;
  oeffneBlatt: (id: string) => void;
  melde: (text: string, art?: 'success' | 'error') => void;
}) {
  const lauf = useLauf();
  // Timer nur zuordnen, wenn er zu den aktuellen Einstellungen passt (gleiche Schritte). Zahlen im Titel zählen
  // nicht („Ofen auf 250 °C vorheizen“ ändert sich mit der Ofentemperatur, der Schritt bleibt derselbe).
  const ohneZahlen = (t: string) => t.replace(/\d+/g, '#');
  const passt =
    !!lauf &&
    lauf.schritte.length === r.schritte.length &&
    lauf.schritte.every((s, i) => ohneZahlen(s.titel) === ohneZahlen(r.schritte[i]![1]));
  const l = passt ? lauf : null;
  const jetzt = useJetzt(!!l);
  const weiter = l ? offenAb(l) : 0;
  const aktiv = l && weiter < l.schritte.length ? weiter : null;
  const [offen, setOffen] = useState(aktiv ?? 0);
  useEffect(() => {
    if (aktiv !== null) setOffen(aktiv);
  }, [aktiv]);

  return (
    <div className="card sd-ablauf">
      <h2>Ablauf</h2>
      <ol className="sd-acc">
        {r.schritte.map(([t, was, dauer, art], i) => {
          const s = l?.schritte[i];
          // Nach „Sauerteig angesetzt“: Uhrzeit von–bis; vor „Backen beginnen“ geschätzt.
          const zeit = !s ? (
            hmKurz(t)
          ) : (
            <>
              <span>
                {l!.phase === 'reifen' && i >= BEGINN && 'ca. '}
                {uhrzeit(s.at, jetzt)}
              </span>
              <span className="sd-bis">bis {uhrzeit(s.at + dauerMinuten(dauer) * 60_000, jetzt)}</span>
            </>
          );
          const erledigt = !!l && i < weiter;
          return (
            <li key={was} className={erledigt ? 'sd-done' : i === aktiv ? 'sd-now' : undefined}>
              <button
                type="button"
                className="sd-acc-head"
                aria-expanded={i === offen}
                aria-controls={`sd-schritt-${i}`}
                onClick={() => setOffen(i === offen ? -1 : i)}
              >
                <span className="sd-when">{zeit}</span>
                <span className="sd-acc-title">
                  <strong>
                    {erledigt && <Symbol name="check" size={15} />} {was}
                  </strong>
                  <span className="muted small">{dauer}</span>
                </span>
                <Symbol name="chevron" size={18} />
              </button>
              <div className="sd-acc-body" id={`sd-schritt-${i}`} hidden={i !== offen}>
                <Anleitung art={art} r={r} w={w} />
                {l && i >= BEGINN && i <= weiter && (
                  <Abhaken
                    key={`${i}:${erledigt}`}
                    l={l}
                    i={i}
                    erledigt={erledigt}
                    jetzt={jetzt}
                    fertig={() => setOffen(i + 1)}
                  />
                )}
                {art === 'ansetzen' && (
                  <TimerStart
                    schritte={r.schritte}
                    reife={spanne(r.zeitplan.sauerteigZeit)}
                    oeffneBlatt={oeffneBlatt}
                    melde={melde}
                  />
                )}
              </div>
            </li>
          );
        })}
      </ol>
      {lauf && !passt ? (
        <p className="muted small" style={{ marginBottom: 0 }}>
          Der laufende Timer gehört zu anderen Einstellungen, daher hier ohne Uhrzeiten.
        </p>
      ) : (
        !l && (
          <p className="muted small" style={{ marginBottom: 0 }}>
            T = Zeitpunkt, an dem der Sauerteig angesetzt wird. Mittelwerte der Zeitspannen.
          </p>
        )
      )}
    </div>
  );
}

export interface Rezept {
  id: number;
  name: string;
  datum: string;
  /** Einstellungen im Format von alsEinstellungen. */
  settings: Record<string, unknown>;
}

export interface RechnerProps {
  w: Werte;
  setW: Dispatch<SetStateAction<Werte>>;
  rezepte: Rezept[];
  melde: (text: string, art?: 'success' | 'error') => void;
  oeffneBlatt: (id: string) => void;
  /** Formular „Rezept sichern“ (Felder name, settings): Server-Formular oder onSubmit. */
  sichernForm: FormHTMLAttributes<HTMLFormElement>;
  loeschenForm: (r: Rezept) => FormHTMLAttributes<HTMLFormElement>;
  /** Hinweis im Sichern-Blatt, wo das Rezept landet. */
  speicherHinweis: string;
}

export function Rechner({
  w,
  setW,
  rezepte,
  melde,
  oeffneBlatt,
  sichernForm,
  loeschenForm,
  speicherHinweis,
}: RechnerProps) {
  const set = (patch: Partial<Werte>) => setW((alt) => ({ ...alt, ...patch }));
  useMeldungen(melde);

  const anteile = anteileVon(w);
  const optimal = berechneOptimaleHydration(anteile);
  const r = berechneRezept({
    verhaeltnis: w.verhaeltnis,
    sauerteigTemp: w.sauerteigTemp,
    gareTemp: w.gareTemp,
    brotGroesse: w.brotGroesse,
    hydration: w.hydration,
    anteile,
    teigTeilen: w.teigTeilen,
    ofenTemp: w.ofenTemp,
    anbackTemp: w.anbackTemp,
    sauerteigArt: w.sauerteigArt,
  });
  const artPassend = sauerteigArtFuer(anteile);
  const [tippsOffen, setTippsOffen] = useState(false);
  const summe = SORTEN.reduce((a, [k]) => a + w.custom[k], 0);
  const mischung = w.mischung === 'custom' ? null : mehlMischungen[w.mischung];

  // Mischung oder eigene Anteile geändert: empfohlene Hydration setzen (wie die eigenständige App).
  const neueAnteile = (patch: Partial<Werte>) =>
    setW((alt) => {
      // Sauerteig wieder passend zum neuen Brot (sauerteigArt weglassen = automatisch)
      const { sauerteigArt: _, ...neu } = { ...alt, ...patch };
      return { ...neu, hydration: berechneOptimaleHydration(anteileVon(neu)) };
    });

  const aufHundert = () => {
    const norm = normalisiere(w.custom);
    if (!norm) {
      melde('Mindestens ein Mehl muss über 0 % liegen', 'error');
      return;
    }
    neueAnteile({ custom: norm });
  };

  const laden = (rez: Rezept) => {
    setW(ausEinstellungen(rez.settings));
    melde(`„${rez.name}“ geladen`, 'success');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const sichernOeffnen = () => {
    oeffneBlatt('sd-save-sheet');
    const feld = document.getElementById('sd-save-name') as HTMLInputElement | null;
    feld?.focus();
    feld?.select();
  };

  const balkenSumme = SORTEN.reduce((a, [k]) => a + anteile[k], 0) || 1;

  return (
    <>
      <TimerKarte />
      <div className="card sd-summary">
        <div className="stats stats-4">
          <div className="stat">
            <span className="muted">Teig</span>
            <strong>{r.teiggewicht} g</strong>
            <small>{w.teigTeilen ? `2 × ${Math.round(r.einzelGewicht)} g` : '1 Brot'}</small>
          </div>
          <div className="stat">
            <span className="muted">Hydration</span>
            <strong>{r.hydration} %</strong>
            <small>{r.gesamtMehl} g Mehl im Hauptteig</small>
          </div>
          <div className="stat">
            <span className="muted">Gesamtdauer</span>
            <strong>{hm(r.gesamtDauer)} h</strong>
            <small>bis aus dem Ofen</small>
          </div>
          <div className="stat">
            <span className="muted">Backen</span>
            <strong>
              {r.anbackTemp} → {r.ofenTemp} °C
            </strong>
            <small>
              {r.dampfMin} Min Dampf, dann {r.backZeit}
            </small>
          </div>
        </div>
      </div>

      <div className="grid-2 sd-layout">
        <div>
          <div className="card">
            <h2>Brotauswahl</h2>
            <label className="field" htmlFor="sd-mischung">
              Mischung
            </label>
            <select
              id="sd-mischung"
              value={w.mischung}
              onChange={(e) => neueAnteile({ mischung: e.currentTarget.value })}
            >
              {Object.entries(mehlMischungen).map(([k, m]) => (
                <option key={k} value={k}>
                  {m.name}
                </option>
              ))}
              <option value="custom">Eigene Mischung</option>
            </select>
            <div className="sd-blend">
              <strong>{mischung ? mischung.name : 'Eigene Mischung'}</strong>
              <div className="muted small">{mischung ? mischung.beschreibung : 'Anteile frei wählbar'}</div>
              {mischung && <div className="muted small">Eigenschaften: {mischung.eigenschaften}</div>}
              <div className="sd-bar" aria-hidden="true">
                {SORTEN.filter(([k]) => anteile[k] > 0).map(([k]) => (
                  <span
                    key={k}
                    style={{ flexBasis: `${(anteile[k] / balkenSumme) * 100}%`, background: `var(--mehl-${k})` }}
                  />
                ))}
              </div>
              <div className="sd-legend">
                {SORTEN.map(([k, n]) => (
                  <span key={k} className={anteile[k] > 0 ? undefined : 'zero'}>
                    <i className="sd-dot" style={{ background: `var(--mehl-${k})` }} />
                    {n} <b>{anteile[k]} %</b>
                  </span>
                ))}
              </div>
            </div>
            {w.mischung === 'custom' && (
              <div className="sd-custom">
                {SORTEN.map(([k, n]) => (
                  <Regler
                    key={k}
                    id={`sd-custom-${k}`}
                    label={
                      <>
                        <i className="sd-dot" style={{ background: `var(--mehl-${k})` }} />
                        {n}
                      </>
                    }
                    wert={`${w.custom[k]} %`}
                    value={w.custom[k]}
                    min={0}
                    max={100}
                    step={5}
                    onChange={(v) => neueAnteile({ custom: { ...w.custom, [k]: v } })}
                  />
                ))}
                <div className="sum-row">
                  <span className={summe === 100 ? 'muted small' : 'qty-warn small'}>Summe: {summe} %</span>
                  {summe !== 100 && (
                    <button type="button" className="btn sm" onClick={aufHundert}>
                      Auf 100 % anpassen
                    </button>
                  )}
                </div>
              </div>
            )}
            {rezepte.length > 0 && (
              <div className="sd-no-print" id="rezepte">
                <div className="day-head">Gespeicherte Rezepte</div>
                <ul className="list">
                  {rezepte.map((rez) => (
                    <li className="list-item" key={rez.id}>
                      <button type="button" className="sd-load" onClick={() => laden(rez)}>
                        <strong>{rez.name}</strong>
                        <span className="muted small">{rez.datum}</span>
                      </button>
                      <form {...loeschenForm(rez)} className="inline">
                        <button className="link-btn" type="submit" aria-label={`„${rez.name}“ löschen`}>
                          <Symbol name="trash" size={17} />
                        </button>
                      </form>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <p className="sd-no-print" style={{ margin: '12px 0 0' }}>
              <button type="button" className="btn sd-save-btn" onClick={sichernOeffnen}>
                <Symbol name="disk" size={18} />
                Rezept sichern
              </button>
            </p>
          </div>

          <div className="card">
            <h2>Teig</h2>
            <Regler
              id="sd-groesse"
              label="Teiggewicht"
              wert={`${r.teiggewicht} g`}
              value={w.brotGroesse}
              min={600}
              max={2000}
              step={100}
              onChange={(v) => set({ brotGroesse: v })}
            />
            <Regler
              id="sd-hydration"
              label={
                <>
                  Hydration{' '}
                  {Math.abs(w.hydration - optimal) <= 2 ? (
                    <span className="pill effort">Empfohlen</span>
                  ) : (
                    <span className="pill today">Angepasst</span>
                  )}
                </>
              }
              wert={`${w.hydration} %`}
              value={w.hydration}
              min={50}
              max={85}
              onChange={(v) => set({ hydration: v })}
            />
            <label className="switch-row" htmlFor="sd-teilen">
              <span>Auf 2 Brote teilen</span>
              <span className="switch">
                <input
                  type="checkbox"
                  id="sd-teilen"
                  role="switch"
                  checked={w.teigTeilen}
                  onChange={(e) => set({ teigTeilen: e.currentTarget.checked })}
                />
                <span className="slider" />
              </span>
            </label>
            <p className="muted small" style={{ marginBottom: 0 }}>
              Höhere Hydration ergibt weicheren Teig. Bei Mischungswechsel wird der empfohlene Wert gesetzt.
            </p>
          </div>

          <div className="card">
            <h2>Sauerteig und Temperaturen</h2>
            <div className="sd-art">
              <span className="sd-art-label" id="sd-verh-label">
                Verhältnis
              </span>
              <div className="chips" role="radiogroup" aria-labelledby="sd-verh-label">
                {VERHAELTNISSE.map((x) => (
                  <label key={x.key} className="chip pick">
                    <input
                      type="radio"
                      name="sd-verh"
                      value={x.key}
                      checked={w.verhaeltnis === x.key}
                      onChange={() => set({ verhaeltnis: x.key })}
                    />
                    {x.name} <span className="sd-chip-sub">{verhaeltnisText(x.key)}</span>
                  </label>
                ))}
              </div>
              <ul className="sd-rows" style={{ margin: '10px 0 0' }}>
                <Zeile label="Anstellgut">{r.anstellgut} g</Zeile>
              </ul>
              <p className="muted small" style={{ margin: '4px 0 0' }}>
                Aus Teiggewicht und Verhältnis; {r.versaeuerung} % des Mehls stecken im Sauerteig. Mehr Futter (1 : 5 :
                5) reift länger und schmeckt milder, weniger (1 : 1 : 1) geht schneller und wird kräftiger.
              </p>
              {r.anstellgut > ANSTELLGUT_VIEL && (
                <div className="sd-note" style={{ margin: '8px 0 0' }}>
                  So viel Anstellgut hast du vielleicht nicht im Glas: am Vortag auffrischen und vermehren.
                </div>
              )}
            </div>
            <div className="sd-art">
              <span className="sd-art-label" id="sd-art-label">
                Sauerteig{' '}
                {r.sauerteigArt === artPassend ? (
                  <span className="pill effort">Passend zum Brot</span>
                ) : (
                  <span className="pill today">Angepasst</span>
                )}
              </span>
              <div className="chips" role="radiogroup" aria-labelledby="sd-art-label">
                {SAUERTEIG_ARTEN.map(([k, n]) => (
                  <label key={k} className="chip pick">
                    <input
                      type="radio"
                      name="sd-art"
                      value={k}
                      checked={r.sauerteigArt === k}
                      onChange={() => set({ sauerteigArt: k })}
                    />
                    <i className="sd-dot" style={{ background: `var(--mehl-${k})` }} />
                    {n}
                  </label>
                ))}
              </div>
              {r.sauerteigHinweis && <div className="sd-note">{r.sauerteigHinweis}</div>}
            </div>
            <Regler
              id="sd-st-temp"
              label="Sauerteig-Temperatur"
              wert={`${w.sauerteigTemp} °C`}
              value={w.sauerteigTemp}
              min={18}
              max={32}
              onChange={(v) => set({ sauerteigTemp: v })}
            />
            <Regler
              id="sd-gare-temp"
              label="Gare-Temperatur"
              wert={`${w.gareTemp} °C`}
              value={w.gareTemp}
              min={20}
              max={32}
              onChange={(v) => set({ gareTemp: v })}
            />
            <div className="day-head">Ofen</div>
            <Regler
              id="sd-anback-temp"
              label="Anbacken mit Dampf"
              wert={`${r.anbackTemp} °C`}
              value={w.anbackTemp ?? ANBACK_STANDARD}
              min={200}
              max={350}
              step={5}
              onChange={(v) => set({ anbackTemp: v })}
            />
            <p className="muted small">
              Dampfphase: {r.dampfMin} Min. Je heißer, desto kürzer (wie bei Pizza); auf diese Temperatur wird
              vorgeheizt.
            </p>
            <Regler
              id="sd-ofen-temp"
              label="Ofentemperatur"
              wert={`${w.ofenTemp} °C`}
              value={w.ofenTemp}
              min={200}
              max={250}
              step={5}
              onChange={(v) => set({ ofenTemp: v })}
            />
            <p className="muted small" style={{ marginBottom: 0 }}>
              Nach der Dampfphase heruntergeschaltet, ohne Dampf: {r.backZeit}.
            </p>
          </div>
        </div>

        <div>
          <Ablauf r={r} w={w} oeffneBlatt={oeffneBlatt} melde={melde} />

          <div className="card">
            <h2>Erwartetes Ergebnis</h2>
            <ul className="sd-rows sd-text">
              <Zeile label="Krume">{r.eigenschaften.krume}</Zeile>
              <Zeile label="Geschmack">{r.eigenschaften.geschmack}</Zeile>
              <Zeile label="Haltbarkeit">{r.eigenschaften.haltbarkeit}</Zeile>
            </ul>
          </div>

          <div className="card">
            <button
              type="button"
              className="sd-acc-head sd-tips-head"
              aria-expanded={tippsOffen}
              aria-controls="sd-tipps"
              onClick={() => setTippsOffen(!tippsOffen)}
            >
              <h2 className="sd-acc-title">Tipps</h2>
              <Symbol name="chevron" />
            </button>
            <ul className="sd-tips" id="sd-tipps" hidden={!tippsOffen}>
              {tipps.map((t) => (
                <li key={t}>
                  <Symbol name="check" size={17} />
                  <span>{t}</span>
                </li>
              ))}
            </ul>
          </div>

          <p className="sd-no-print">
            <button type="button" className="btn" onClick={() => window.print()}>
              Drucken
            </button>
          </p>
        </div>
      </div>

      <dialog className="sheet" id="sd-save-sheet" aria-labelledby="sd-save-t">
        <form {...sichernForm} className="sheet-body">
          <div className="sheet-bar">
            <button type="button" className="sheet-cancel" data-close="">
              Abbrechen
            </button>
            <h2 className="sheet-title" id="sd-save-t">
              Rezept sichern
            </h2>
            <button type="submit" className="sheet-cancel sd-sheet-ok">
              Sichern
            </button>
          </div>
          <label className="field" htmlFor="sd-save-name">
            Name
          </label>
          <input
            type="text"
            id="sd-save-name"
            name="name"
            defaultValue="Mein Sauerteigbrot"
            maxLength={60}
            required
            autoComplete="off"
            enterKeyHint="done"
          />
          <input type="hidden" name="settings" value={JSON.stringify(alsEinstellungen(w))} />
          <p className="muted small">{speicherHinweis} Laden unter „Brotauswahl“.</p>
        </form>
      </dialog>
    </>
  );
}
