/* Back-Timer (timer.ts) in der Oberfläche: Karte oben im Rechner („Sauerteig reift“ / „Backen läuft“) und das
 * Blatt „Sauerteig angesetzt“. Die Schritte mit Uhrzeiten zeigt der Ablauf (Oberflaeche.tsx). */
import { useEffect, useState, useSyncExternalStore } from 'react';
import type { Schritt } from './rechner';
import {
  BEGINN,
  VORLAUF_WAHL,
  aendereVorlauf,
  beendeLauf,
  beginneBacken,
  erlaubeMitteilungen,
  letzterVorlauf,
  meldungHoerer,
  naechster,
  neuerLauf,
  restzeit,
  starteLauf,
  timerStore,
  uhrzeit,
} from './timer';

export function useLauf() {
  return useSyncExternalStore(timerStore.abonniere, timerStore.lauf);
}

/** Aktuelle Zeit, jede Sekunde neu (nur solange ``aktiv``). */
export function useJetzt(aktiv: boolean): number {
  const [jetzt, setJetzt] = useState(Date.now);
  useEffect(() => {
    if (!aktiv) return;
    const t = setInterval(() => setJetzt(Date.now()), 1000);
    return () => clearInterval(t);
  }, [aktiv]);
  return jetzt;
}

/** Meldungen des Timers als Toast, solange der Rechner offen ist. */
export function useMeldungen(melde: (text: string, art?: 'success' | 'error') => void) {
  useEffect(() => {
    const f = (m: { titel: string }) => melde(m.titel, 'success');
    meldungHoerer.add(f);
    return () => {
      meldungHoerer.delete(f);
    };
  }, [melde]);
}

const lokal = (ms: number) => {
  const d = new Date(ms - new Date(ms).getTimezoneOffset() * 60_000);
  return d.toISOString().slice(0, 16);
};

const vorlaufText = (v: number) => (v ? `${v} Min vorher` : 'Keine');

function Mitteilungshinweis() {
  const erlaubt = typeof Notification === 'undefined' ? 'nicht-da' : Notification.permission;
  if (erlaubt === 'granted') return null;
  return (
    <p className="sd-note">
      {erlaubt === 'denied'
        ? 'Mitteilungen sind für diese Seite blockiert. Der Timer zeigt die Schritte nur hier an.'
        : erlaubt === 'nicht-da'
          ? 'Dieser Browser kann keine Mitteilungen zeigen. Auf dem iPhone geht das nur in der installierten App.'
          : 'Beim Starten fragt der Browser, ob Mitteilungen erlaubt sind.'}
    </p>
  );
}

export function TimerKarte() {
  const lauf = useLauf();
  const jetzt = useJetzt(!!lauf);
  const [sicher, setSicher] = useState(false);
  useEffect(() => {
    if (!sicher) return;
    const t = setTimeout(() => setSicher(false), 3000);
    return () => clearTimeout(t);
  }, [sicher]);
  if (!lauf) return null;

  const reifen = lauf.phase === 'reifen';
  const i = naechster(lauf, jetzt);
  const n = i >= 0 ? lauf.schritte[i] : undefined;
  const fertig = !reifen && !n;
  const beginn = lauf.schritte[BEGINN];

  const vorlauf = (
    <>
      <label className="field" htmlFor="sd-timer-vorlauf">
        Erinnerung vor jedem Schritt
      </label>
      <select
        id="sd-timer-vorlauf"
        value={lauf.vorlauf}
        onChange={(e) => aendereVorlauf(parseInt(e.currentTarget.value, 10))}
      >
        {VORLAUF_WAHL.map((v) => (
          <option key={v} value={v}>
            {vorlaufText(v)}
          </option>
        ))}
      </select>
    </>
  );

  if (reifen)
    return (
      <div className="card sd-timer sd-no-print" aria-live="polite">
        <div className="sd-timer-head">
          <h2>Sauerteig reift</h2>
          <button
            type="button"
            className={sicher ? 'btn sm danger' : 'btn sm'}
            onClick={() => (sicher ? beendeLauf() : setSicher(true))}
          >
            {sicher ? 'Wirklich beenden?' : 'Beenden'}
          </button>
        </div>
        <div className="sd-timer-next">
          <span className="muted small">
            Angesetzt um {uhrzeit(lauf.start, jetzt)} · reif ca. {uhrzeit(lauf.reife[0], jetzt)}–
            {uhrzeit(lauf.reife[1], jetzt)}
          </span>
          {beginn && <strong>Backen beginnt ca. {uhrzeit(beginn.at, jetzt)}</strong>}
          {beginn && (
            <span className="sd-timer-count">
              {beginn.at > jetzt ? `≈ ${restzeit(beginn.at - jetzt)}` : 'Sauerteig prüfen'}
            </span>
          )}
        </div>
        <button type="button" className="btn accent-fill sd-timer-go" onClick={beginneBacken}>
          Backen beginnen
        </button>
        <p className="muted small">
          Tippen, sobald der Sauerteig reif ist (Blasen, leicht gewölbt, säuerlicher Geruch). Ab dann laufen die
          Schritte mit Erinnerungen, Zutaten und Anleitung stehen im Ablauf.
        </p>
        {vorlauf}
        <Mitteilungshinweis />
      </div>
    );

  return (
    <div className="card sd-timer sd-no-print" aria-live="polite">
      <div className="sd-timer-head">
        <h2>{fertig ? 'Fertig gebacken' : 'Backen läuft'}</h2>
        <button
          type="button"
          className={sicher ? 'btn sm danger' : 'btn sm'}
          onClick={() => (sicher || fertig ? beendeLauf() : setSicher(true))}
        >
          {fertig ? 'Schließen' : sicher ? 'Wirklich beenden?' : 'Beenden'}
        </button>
      </div>
      {n ? (
        <div className="sd-timer-next">
          <span className="muted small">Nächster Schritt um {uhrzeit(n.at, jetzt)}</span>
          <strong>{n.titel}</strong>
          <span className="sd-timer-count">{restzeit(n.at - jetzt)}</span>
        </div>
      ) : (
        <p className="muted">Brot mindestens 2 Stunden auskühlen lassen, erst dann anschneiden.</p>
      )}
      {!fertig && (
        <>
          {vorlauf}
          {lauf.fern ? (
            <p className="muted small sd-timer-fern">Erinnerungen kommen per Push, auch wenn die App zu ist.</p>
          ) : (
            <Mitteilungshinweis />
          )}
        </>
      )}
    </div>
  );
}

/** Knopf im Ablauf und Blatt „Sauerteig angesetzt“ (Uhrzeit und Vorwarnung). */
export function TimerStart({
  schritte,
  reife,
  oeffneBlatt,
  melde,
}: {
  schritte: Schritt[];
  /** Reifezeit des Sauerteigs in Minuten [min, max] */
  reife: [number, number];
  oeffneBlatt: (id: string) => void;
  melde: (text: string, art?: 'success' | 'error') => void;
}) {
  const lauf = useLauf();
  const [start, setStart] = useState('');
  const [vorlauf, setVorlauf] = useState(letzterVorlauf);
  const startMs = start ? new Date(start).getTime() : NaN;
  const vorschau = Number.isFinite(startMs) ? neuerLauf(schritte, startMs, vorlauf, reife) : null;
  const beginn = vorschau?.schritte[BEGINN];
  const ende = vorschau?.schritte[vorschau.schritte.length - 1];

  const oeffnen = () => {
    setStart(lokal(Date.now()));
    setVorlauf(letzterVorlauf());
    oeffneBlatt('sd-timer-sheet');
  };

  const starten = async () => {
    if (!vorschau) {
      melde('Uhrzeit fehlt', 'error');
      return;
    }
    const erlaubt = await erlaubeMitteilungen();
    starteLauf(neuerLauf(schritte, startMs, vorlauf, reife));
    (document.getElementById('sd-timer-sheet') as HTMLDialogElement | null)?.close();
    window.scrollTo({ top: 0, behavior: 'smooth' });
    melde(
      erlaubt === 'granted' ? 'Sauerteig angesetzt' : 'Sauerteig angesetzt, ohne Mitteilungen',
      erlaubt === 'granted' ? 'success' : 'error',
    );
  };

  return (
    <>
      <p className="sd-no-print" style={{ margin: '12px 0 0' }}>
        <button type="button" className="btn accent-fill" onClick={oeffnen}>
          Sauerteig angesetzt
        </button>
      </p>
      <dialog className="sheet" id="sd-timer-sheet" aria-labelledby="sd-timer-t">
        <form
          className="sheet-body"
          data-native=""
          onSubmit={(e) => {
            e.preventDefault();
            void starten();
          }}
        >
          <div className="sheet-bar">
            <button type="button" className="sheet-cancel" data-close="">
              Abbrechen
            </button>
            <h2 className="sheet-title" id="sd-timer-t">
              Sauerteig angesetzt
            </h2>
            <button type="submit" className="sheet-cancel sd-sheet-ok">
              Starten
            </button>
          </div>
          <label className="field" htmlFor="sd-timer-start">
            Angesetzt um
          </label>
          <input
            type="datetime-local"
            id="sd-timer-start"
            value={start}
            onChange={(e) => setStart(e.currentTarget.value)}
            required
          />
          <label className="field" htmlFor="sd-timer-vorlauf-neu">
            Erinnerung vor jedem Schritt
          </label>
          <select
            id="sd-timer-vorlauf-neu"
            value={vorlauf}
            onChange={(e) => setVorlauf(parseInt(e.currentTarget.value, 10))}
          >
            {VORLAUF_WAHL.map((v) => (
              <option key={v} value={v}>
                {vorlaufText(v)}
              </option>
            ))}
          </select>
          {vorschau && beginn && ende && (
            <p className="muted small">
              Reif ca. {uhrzeit(vorschau.reife[0])}–{uhrzeit(vorschau.reife[1])}. Backen beginnt ca.{' '}
              {uhrzeit(beginn.at)}, aus dem Ofen ca. {uhrzeit(ende.at)}.
            </p>
          )}
          {lauf && <p className="muted small">Der laufende Timer wird ersetzt.</p>}
        </form>
      </dialog>
    </>
  );
}
