/* Oberfläche des Sauerteig-Rechners – gemeinsam für die Haushalt-App (/backen) und die eigenständige App
 * (Sauerteig-Repo, kopiert per scripts/sync-haushalt.sh). Rechnet im Browser; wo Rezepte liegen und wie
 * gesichert und gelöscht wird, bestimmt die einbindende App (Props). Braucht das CSS der Haushalt-App
 * (app/static/style.css) und sauerteig.css. */
import type { CSSProperties, Dispatch, FormHTMLAttributes, ReactNode, SetStateAction } from 'react';
import { SORTEN, mehlMischungen, tipps, type Anteile, type Sorte } from './daten';
import { berechneOptimaleHydration, berechneRezept, hm, normalisiere } from './rechner';
import { Symbol } from './symbole';
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
            <strong>220 °C</strong>
            <small>{r.backZeit} nach Dampf</small>
          </div>
        </div>
      </div>

      <div className="grid-2 sd-layout">
        <div>
          <div className="card">
            <h2>Mehl</h2>
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
            <h2>Sauerteig &amp; Gare</h2>
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
          </div>

          {rezepte.length > 0 && (
            <div className="card sd-no-print" id="rezepte">
              <h2>Rezepte</h2>
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
        </div>

        <div>
          <div className="card">
            <h2>Zeitplan</h2>
            <ul className="sd-rows">
              <Zeile label="Sauerteig-Reife">{r.zeitplan.sauerteigZeit}</Zeile>
              <Zeile label="Erste Gare">{r.ersteGare}</Zeile>
              <Zeile label="Stückgare">{r.stueckgare}</Zeile>
            </ul>
          </div>

          <div className="card">
            <h2>
              <span className="sd-step">1</span>Sauerteig
            </h2>
            <ul className="sd-rows">
              <Zeile label="Anstellgut">{r.anstellgut} g</Zeile>
              <Zeile label="Roggen-Vollkornmehl">{r.sauerteigMehl} g</Zeile>
              <Zeile label="Wasser">{r.sauerteigWasser} ml</Zeile>
              <Zeile label={`Reifezeit bei ${w.sauerteigTemp} °C`}>
                <span className="sd-tint">{r.zeitplan.sauerteigZeit}</span>
              </Zeile>
            </ul>
            {r.tempHinweis && <div className="sd-note">{r.tempHinweis}</div>}
            <p className="muted small" style={{ marginBottom: 0 }}>
              Ergibt ca. {r.sauerteigGesamt} g aktiven Sauerteig. Benötigt: {r.sauerteigGesamt} g.
            </p>
          </div>

          <div className="card">
            <h2>
              <span className="sd-step">2</span>Hauptteig
            </h2>
            <div className="day-head">
              {r.mitAutolyse ? 'Autolyse (Mehl + Wasser)' : 'Zutaten (alles zusammen mischen)'}
            </div>
            <ul className="sd-rows">
              {SORTEN.filter(([k]) => r.mehl[k] > 0).map(([k]) => (
                <Zeile key={k} label={MEHL_NAME[k]} dot={`var(--mehl-${k})`}>
                  {r.mehl[k]} g
                </Zeile>
              ))}
              <Zeile label="Warmes Wasser" dot="var(--mehl-wasser)">
                {r.hauptteigWasser} ml
              </Zeile>
            </ul>
            {r.mitAutolyse && <div className="day-head">Nach Autolyse zugeben</div>}
            <ul className="sd-rows">
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
              <Zeile label="Autolyse">
                <span className="sd-tint">{r.autolyseZeit}</span>
              </Zeile>
              <Zeile label="Erste Gare">
                <span className="sd-tint">{r.ersteGare}</span>
              </Zeile>
            </ul>
          </div>

          <div className="card">
            <h2>
              <span className="sd-step">3</span>Formen &amp; Backen
            </h2>
            <ul className="sd-rows">
              <Zeile label="Stückgare im Gärkorb">
                <span className="sd-tint">{r.stueckgare}</span>
              </Zeile>
              <Zeile label="Ofen vorheizen auf 250 °C">30-40 Min</Zeile>
            </ul>
            <ol className="sd-steps">
              <li>Mit feuchten Händen rundwirken, in bemehlten Gärkorb legen.</li>
              <li>Stürzen und kreuzförmig einschneiden.</li>
              <li>
                {r.dampfMin} Min bei 250 °C <strong>mit Dampf</strong>{' '}
                {w.teigTeilen ? '(2 Brote → engere Dampfphase)' : '(Schüssel über Brot oder Schwaden)'}
              </li>
              <li>{r.backZeit} bei 220 °C ohne Dampf</li>
            </ol>
            <p className="muted small" style={{ marginBottom: 0 }}>
              Mittlere Schiene verwenden.
            </p>
          </div>

          <div className="card">
            <h2>Ablauf</h2>
            <ol className="sd-timeline">
              {r.schritte.map(([t, was, dauer]) => (
                <li key={was}>
                  <span className="sd-when">T+{hm(t)}</span>
                  <span>
                    <strong>{was}</strong>
                    <span className="muted small">{dauer}</span>
                  </span>
                </li>
              ))}
            </ol>
            <p className="muted small" style={{ marginBottom: 0 }}>
              T = Zeitpunkt, an dem der Sauerteig angesetzt wird. Mittelwerte der Zeitspannen.
            </p>
          </div>

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

      <div className="list-fab-space" aria-hidden="true" />
      <button type="button" className="sd-fab sd-no-print" aria-label="Rezept sichern" onClick={sichernOeffnen}>
        <Symbol name="disk" size={24} />
      </button>
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
          <p className="muted small">{speicherHinweis} Laden unter „Rezepte“.</p>
        </form>
      </dialog>
    </>
  );
}
