/* Oberfläche des Sauerteig-Rechners – gemeinsam für die Haushalt-App (/backen) und die eigenständige App
 * (Sauerteig-Repo, kopiert per scripts/sync-haushalt.sh). Rechnet im Browser; wo Rezepte liegen und wie
 * gesichert und gelöscht wird, bestimmt die einbindende App (Props). Braucht das CSS der Haushalt-App
 * (app/static/style.css) und sauerteig.css. */
import { useEffect, useState } from 'react';
import type { CSSProperties, Dispatch, FormHTMLAttributes, ReactNode, SetStateAction } from 'react';
import { SORTEN, mehlMischungen, tipps, type Anteile, type Sorte } from './daten';
import {
  berechneOptimaleHydration,
  berechneRezept,
  hm,
  normalisiere,
  spanne,
  type Rezept as Berechnung,
  type SchrittArt,
} from './rechner';
import { Symbol } from './symbole';
import { BEGINN, naechster, uhrzeit } from './timer';
import { TimerKarte, TimerStart, useJetzt, useLauf, useMeldungen } from './TimerKarte';
import './sauerteig.css';

export interface Werte {
  anstellgut: number;
  sauerteigTemp: number;
  gareTemp: number;
  brotGroesse: number;
  hydration: number;
  mischung: string;
  custom: Anteile;
  teigTeilen: boolean;
  ofenTemp: number;
}

const START_MISCHUNG = 'roggen-optimal';
export const START: Werte = {
  anstellgut: 120,
  sauerteigTemp: 22,
  gareTemp: 30,
  brotGroesse: 1200,
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
    anstellgut: String(w.anstellgut),
    sauerteigTemp: String(w.sauerteigTemp),
    gareTemp: String(w.gareTemp),
    brotGroesse: String(w.brotGroesse),
    hydration: String(w.hydration),
    mehlMischung: w.mischung,
    customRoggen: String(w.custom.roggen),
    customDinkel: String(w.custom.dinkel),
    customWeizen: String(w.custom.weizen),
    customBuchweizen: String(w.custom.buchweizen),
    teigTeilen: w.teigTeilen,
    ofenTemp: String(w.ofenTemp),
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
  return {
    anstellgut: n('anstellgut', START.anstellgut),
    sauerteigTemp: n('sauerteigTemp', START.sauerteigTemp),
    gareTemp: n('gareTemp', START.gareTemp),
    brotGroesse: n('brotGroesse', START.brotGroesse),
    hydration: n('hydration', START.hydration),
    mischung,
    custom: {
      roggen: n('customRoggen', START.custom.roggen),
      dinkel: n('customDinkel', START.custom.dinkel),
      weizen: n('customWeizen', START.custom.weizen),
      buchweizen: n('customBuchweizen', START.custom.buchweizen),
    },
    teigTeilen: typeof e.teigTeilen === 'boolean' ? e.teigTeilen : false,
    ofenTemp: n('ofenTemp', START.ofenTemp),
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
      <Zeile
        label={
          <>
            Kümmel <span className="muted">(optional)</span>
          </>
        }
      >
        {r.kuemmel.replace('.', ',')} TL
      </Zeile>
    </>
  );
}

/** Zutaten und Anleitung eines Schritts im Ablauf. */
function Anleitung({ art, r, w }: { art: SchrittArt | undefined; r: Berechnung; w: Werte }) {
  switch (art) {
    case 'ansetzen':
      return (
        <>
          <ul className="sd-rows">
            <Zeile label="Anstellgut">{r.anstellgut} g</Zeile>
            <Zeile label="Roggen-Vollkornmehl" dot="var(--mehl-roggen)">
              {r.sauerteigMehl} g
            </Zeile>
            <Zeile label="Wasser" dot="var(--mehl-wasser)">
              {r.sauerteigWasser} ml
            </Zeile>
          </ul>
          {r.tempHinweis && <div className="sd-note">{r.tempHinweis}</div>}
          <ol className="sd-steps">
            <li>Anstellgut, Mehl und Wasser gründlich verrühren.</li>
            <li>
              Abgedeckt bei {w.sauerteigTemp} °C <strong>{r.zeitplan.sauerteigZeit}</strong> reifen lassen.
            </li>
            <li>
              Reif, wenn er Blasen wirft, leicht gewölbt ist und säuerlich riecht. Ergibt ca. {r.sauerteigGesamt} g.
            </li>
          </ol>
        </>
      );
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
            <li>Alles zum Autolyseteig geben und gründlich verkneten, mit feuchten Händen.</li>
            <li>
              Abgedeckt bei {w.gareTemp} °C gehen lassen: <strong>{r.ersteGare}</strong>.
            </li>
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
            <li>
              Abgedeckt bei {w.gareTemp} °C gehen lassen: <strong>{r.ersteGare}</strong>.
            </li>
          </ol>
        </>
      );
    case 'formen':
      return (
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
            Ofen auf <strong>{r.anbackTemp} °C</strong> vorheizen (30-40 Min), mittlere Schiene.
          </li>
          <li>Schüssel zum Abdecken oder ein Gefäß für Wasser (Schwaden) bereitstellen.</li>
        </ol>
      );
    case 'backen':
      return (
        <ol className="sd-steps">
          <li>Stürzen und kreuzförmig einschneiden.</li>
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

/** Alle Schritte mit Zutaten und Anleitung; immer nur einer ist offen. Läuft der Timer, öffnet sich der
 * aktuelle Schritt von selbst und die Zeiten sind Uhrzeiten. */
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
  // Timer nur zuordnen, wenn er zu den aktuellen Einstellungen passt (gleiche Schritte).
  const passt =
    !!lauf &&
    lauf.schritte.length === r.schritte.length &&
    lauf.schritte.every((s, i) => s.titel === r.schritte[i]![1]);
  const l = passt ? lauf : null;
  const jetzt = useJetzt(!!l);
  let aktiv: number | null = null;
  if (l) {
    const n = naechster(l, jetzt);
    aktiv = l.phase === 'reifen' ? 0 : n < 0 ? l.schritte.length - 1 : Math.max(0, n - 1);
  }
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
            `T+${hm(t)}`
          ) : (
            <>
              <span>
                {l!.phase === 'reifen' && i >= BEGINN && 'ca. '}
                {uhrzeit(s.at, jetzt)}
              </span>
              <span className="sd-bis">bis {uhrzeit(s.at + dauerMinuten(dauer) * 60_000, jetzt)}</span>
            </>
          );
          const erledigt = l?.phase === 'backen' && aktiv !== null && i < aktiv;
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
    anstellgut: w.anstellgut,
    sauerteigTemp: w.sauerteigTemp,
    gareTemp: w.gareTemp,
    brotGroesse: w.brotGroesse,
    hydration: w.hydration,
    anteile,
    teigTeilen: w.teigTeilen,
    ofenTemp: w.ofenTemp,
  });
  const summe = SORTEN.reduce((a, [k]) => a + w.custom[k], 0);
  const mischung = w.mischung === 'custom' ? null : mehlMischungen[w.mischung];

  // Mischung oder eigene Anteile geändert: empfohlene Hydration setzen (wie die eigenständige App).
  const neueAnteile = (patch: Partial<Werte>) =>
    setW((alt) => {
      const neu = { ...alt, ...patch };
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
            <strong>{w.ofenTemp} °C</strong>
            <small>{r.backZeit} nach Dampf</small>
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
            <h2>Temperaturen</h2>
            <Regler
              id="sd-anstellgut"
              label="Anstellgut"
              wert={`${w.anstellgut} g`}
              value={w.anstellgut}
              min={30}
              max={200}
              onChange={(v) => set({ anstellgut: v })}
            />
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
              Backen ohne Dampf: {r.backZeit}. Vorheizen und Dampfphase bei {r.anbackTemp} °C.
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
            <h2>Tipps</h2>
            <ul className="sd-tips">
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
