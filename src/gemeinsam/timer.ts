/* Back-Timer des Sauerteig-Rechners. Schritte werden der Reihe nach abgehakt (Ansetzen mit dem Start, „Backen
 * beginnen“ hakt den ersten Backschritt ab); ein Haken setzt den Schritt auf jetzt und verschiebt die späteren
 * um denselben Betrag. Ein schon erledigter Schritt lässt sich so auf jetzt aktualisieren. Zwei Phasen:
 * - „reifen“ (nach „Sauerteig angesetzt“): nur im Browser; zeigt, wann der Sauerteig ungefähr reif ist und das
 *   Backen beginnt, und erinnert einmal daran.
 * - „backen“ (nach „Backen beginnen“): die restlichen Schritte ab jetzt neu gerechnet, je Schritt eine Meldung
 *   vorher („bald“, einstellbar) und eine bei Fälligkeit („jetzt“). Hat die einbindende App einen Server mit
 *   Push (setzeFernPush), meldet der; sonst meldet der Browser selbst.
 * Der Stand liegt in localStorage („sauerteig-timer“), ein Ticker prüft alle paar Sekunden. Lokale Mitteilungen
 * über den Service Worker, sonst die Notification-API; ohne offene App kommen sie nicht. */
import type { Schritt } from './rechner';

export interface TimerSchritt {
  /** Fälligkeit (ms seit Epoche) */
  at: number;
  titel: string;
  dauer: string;
}

export interface Lauf {
  phase: 'reifen' | 'backen';
  /** T: Sauerteig angesetzt (ms) */
  start: number;
  /** Sauerteig reif zwischen (ms) */
  reife: [number, number];
  /** Zeitpunkt des Startens; frühere Fälligkeiten melden sich nicht. */
  erstellt: number;
  /** Vorwarnung in Minuten, 0 = aus */
  vorlauf: number;
  schritte: TimerSchritt[];
  /** Schon gemeldet: „<index>:bald“ / „<index>:jetzt“ */
  gemeldet: string[];
  /** Phase „backen“: der Server meldet per Push auf dieses Gerät, der Browser zeigt keine eigenen Mitteilungen. */
  fern?: boolean;
  /** Index des nächsten nicht abgehakten Schritts (fehlt bei älteren Ständen: siehe offenAb) */
  weiter?: number;
}

/** Push vom Server ab „Backen beginnen“; ``plane`` antwortet, ob dieses Gerät die Meldungen bekommt. */
export interface FernPush {
  plane(l: Lauf): Promise<boolean>;
  stoppe(): Promise<void>;
}

export interface Meldung {
  key: string;
  titel: string;
  text: string;
}

const KEY = 'sauerteig-timer';
const VORLAUF_KEY = 'sauerteig-vorlauf';
/** Später als das (App war zu): nicht mehr melden, nur als erledigt merken. */
const VERSPAETUNG_MAX = 3 * 60_000;
/** So lange nach dem letzten Schritt verschwindet der Timer von selbst. */
const AUFRAEUMEN_NACH = 3 * 60 * 60_000;
export const VORLAUF_WAHL = [0, 5, 10, 15, 20, 30, 45, 60];

const MIN = 60_000;
const auf5 = (min: number) => Math.round(min / 5) * 5;

/** Erster Schritt des eigentlichen Backens (nach „Sauerteig ansetzen“). */
export const BEGINN = 1;

export function neuerLauf(
  schritte: Schritt[],
  start: number,
  vorlauf: number,
  reifeMin: [number, number],
  jetzt = Date.now(),
): Lauf {
  return {
    phase: 'reifen',
    start,
    reife: [start + reifeMin[0] * MIN, start + reifeMin[1] * MIN],
    erstellt: jetzt,
    vorlauf,
    schritte: schritte.map(([t, titel, dauer]) => ({ at: start + auf5(t) * MIN, titel, dauer })),
    gemeldet: [],
  };
}

/** Index des nächsten noch nicht fälligen Schritts, -1 wenn alle durch sind. */
export function naechster(lauf: Lauf, jetzt: number): number {
  return lauf.schritte.findIndex((s) => s.at > jetzt);
}

export function uhrzeit(ms: number, jetzt = Date.now()): string {
  const d = new Date(ms);
  const zeit = d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === new Date(jetzt).toDateString()) return zeit;
  return `${d.toLocaleDateString('de-DE', { weekday: 'short' })} ${zeit}`;
}

/** Restzeit: „1:23 h“, unter einer Stunde „12:05“ (Min:Sek). */
export function restzeit(ms: number): string {
  const s = Math.max(0, Math.ceil(ms / 1000));
  if (s >= 3600) return `${Math.floor(s / 3600)}:${String(Math.floor((s % 3600) / 60)).padStart(2, '0')} h`;
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Index des nächsten nicht abgehakten Schritts. */
export function offenAb(l: Lauf): number {
  return l.weiter ?? (l.phase === 'reifen' ? BEGINN : BEGINN + 1);
}

/** Schritt ``i`` jetzt erledigt: er bekommt die Uhrzeit jetzt, alle späteren verschieben sich um denselben Betrag
 * (später erledigt → später, früher → früher) und gelten als offen. Danach Phase „backen“. */
export function hakeAbAm(l: Lauf, i: number, jetzt: number): Lauf {
  const s = l.schritte[i];
  const d = s ? jetzt - s.at : 0;
  const backen = l.phase === 'backen';
  return {
    ...l,
    phase: 'backen',
    erstellt: jetzt,
    weiter: i + 1,
    // Meldungen der verschobenen Schritte neu
    gemeldet: backen ? l.gemeldet.filter((k) => parseInt(k, 10) < i) : [],
    fern: backen ? l.fern : false,
    schritte: l.schritte.map((x, j) => (j >= i ? { ...x, at: x.at + d } : x)),
  };
}

/** Phase „backen“ ab jetzt: Schritte ab BEGINN so verschoben, dass BEGINN jetzt dran ist. */
export function backenAb(l: Lauf, jetzt: number): Lauf {
  return hakeAbAm(l, BEGINN, jetzt);
}

/** Was jetzt zu melden ist; trägt alles Fällige in ``gemeldet`` ein (auch zu spät Erkanntes, ohne Meldung). */
export function faellig(lauf: Lauf, jetzt: number): Meldung[] {
  const out: Meldung[] = [];
  const merke = (key: string, wann: number, m: Omit<Meldung, 'key'>) => {
    if (lauf.gemeldet.includes(key) || wann > jetzt) return false;
    lauf.gemeldet.push(key);
    if (wann > lauf.erstellt && jetzt - wann <= VERSPAETUNG_MAX) out.push({ key, ...m });
    return true;
  };
  if (lauf.phase === 'reifen') {
    // Nur der Beginn des Backens; der Rest hängt davon ab, wann der Sauerteig wirklich reif ist.
    const b = lauf.schritte[BEGINN];
    if (!b) return out;
    if (
      merke(`${BEGINN}:jetzt`, b.at, {
        titel: 'Sauerteig prüfen',
        text: `Wenn er reif ist: „Backen beginnen“ tippen. Als Erstes: ${b.titel}.`,
      })
    )
      return out;
    if (lauf.vorlauf > 0)
      merke(`${BEGINN}:bald`, b.at - lauf.vorlauf * MIN, {
        titel: `In ${lauf.vorlauf} Min beginnt das Backen`,
        text: `Um ca. ${uhrzeit(b.at, jetzt)}: ${b.titel}.`,
      });
    return out;
  }
  lauf.schritte.forEach((s, i) => {
    const danach = lauf.schritte[i + 1];
    const weiter = danach ? ` Danach um ${uhrzeit(danach.at, jetzt)}: ${danach.titel}.` : '';
    if (merke(`${i}:jetzt`, s.at, { titel: `Jetzt: ${s.titel}`, text: `${s.dauer}.${weiter}` })) {
      if (!lauf.gemeldet.includes(`${i}:bald`)) lauf.gemeldet.push(`${i}:bald`);
      return;
    }
    if (lauf.vorlauf > 0)
      merke(`${i}:bald`, s.at - lauf.vorlauf * MIN, {
        titel: `In ${lauf.vorlauf} Min: ${s.titel}`,
        text: `Um ${uhrzeit(s.at, jetzt)} (${s.dauer}).`,
      });
  });
  return out;
}

/* ------------------------------------------------------------------ Speicher */

function lade(): Lauf | null {
  try {
    const l = JSON.parse(localStorage.getItem(KEY) || 'null') as Lauf | null;
    return l && Array.isArray(l.schritte) && Array.isArray(l.gemeldet) && Array.isArray(l.reife) ? l : null;
  } catch {
    return null;
  }
}

function sichere(l: Lauf | null): void {
  try {
    if (l) localStorage.setItem(KEY, JSON.stringify(l));
    else localStorage.removeItem(KEY);
  } catch {
    /* ohne Speicher: läuft nur bis zum Neuladen */
  }
}

export function letzterVorlauf(): number {
  try {
    const v = parseInt(localStorage.getItem(VORLAUF_KEY) || '', 10);
    return VORLAUF_WAHL.includes(v) ? v : 10;
  } catch {
    return 10;
  }
}

let lauf: Lauf | null = lade();
const hoerer = new Set<() => void>();

function setze(l: Lauf | null): void {
  lauf = l;
  sichere(l);
  hoerer.forEach((f) => f());
  plane();
}

export const timerStore = {
  abonniere(f: () => void): () => void {
    hoerer.add(f);
    return () => hoerer.delete(f);
  },
  lauf: (): Lauf | null => lauf,
};

let fernPush: FernPush | null = null;

/** Von der einbindenden App: Push vom Server (Haushalt-App, Sourdough.tsx). */
export function setzeFernPush(f: FernPush | null): void {
  fernPush = f;
  // App neu geöffnet, während gebacken wird: Zeitplan erneut melden (Server neu gestartet, Push-Abo erneuert).
  if (lauf) fernPlanen(lauf);
}

/** Phase „backen“: Zeitplan an den Server; ``fern`` merken, wenn dieses Gerät von dort Push bekommt. */
function fernPlanen(l: Lauf): void {
  if (!fernPush || l.phase !== 'backen') return;
  fernPush.plane(l).then(
    (ok) => {
      if (lauf && lauf.erstellt === l.erstellt && lauf.phase === 'backen' && (lauf.fern ?? false) !== ok)
        setze({ ...lauf, fern: ok });
    },
    () => undefined,
  );
}

function fernStoppen(): void {
  if (lauf?.phase === 'backen') fernPush?.stoppe().catch(() => undefined);
}

export function starteLauf(l: Lauf): void {
  fernStoppen();
  try {
    localStorage.setItem(VORLAUF_KEY, String(l.vorlauf));
  } catch {
    /* egal */
  }
  faellig(l, Date.now()); // schon Vergangenes (Start in der Vergangenheit) nicht nachmelden
  setze(l);
}

export function aendereVorlauf(vorlauf: number): void {
  if (!lauf) return;
  try {
    localStorage.setItem(VORLAUF_KEY, String(vorlauf));
  } catch {
    /* egal */
  }
  const jetzt = Date.now();
  // Vorwarnungen neu, soweit der Schritt noch kommt; eine dadurch schon verstrichene kommt nicht nach.
  const l: Lauf = {
    ...lauf,
    vorlauf,
    erstellt: Math.max(lauf.erstellt, jetzt),
    gemeldet: lauf.gemeldet.filter((k) => !k.endsWith(':bald') || lauf!.schritte[parseInt(k, 10)]!.at <= jetzt),
  };
  faellig(l, jetzt);
  setze(l);
  fernPlanen(l);
}

export function beginneBacken(): void {
  if (lauf?.phase === 'reifen') hakeAb(BEGINN);
}

/** Abhaken: der nächste offene Schritt, oder ein erledigter neu auf jetzt (nicht das Ansetzen, das ist der Start). */
export function hakeAb(i: number): void {
  if (!lauf || i < BEGINN || i > offenAb(lauf)) return;
  const jetzt = Date.now();
  const l = hakeAbAm(lauf, i, jetzt);
  faellig(l, jetzt);
  setze(l);
  fernPlanen(l);
}

export function beendeLauf(): void {
  fernStoppen();
  setze(null);
}

/* ------------------------------------------------------------------- Melden */

export async function erlaubeMitteilungen(): Promise<NotificationPermission | 'nicht-da'> {
  if (typeof Notification === 'undefined') return 'nicht-da';
  if (Notification.permission !== 'default') return Notification.permission;
  try {
    return await Notification.requestPermission();
  } catch {
    return Notification.permission;
  }
}

async function zeige(m: Meldung): Promise<void> {
  if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
  const opts: NotificationOptions & { renotify?: boolean } = {
    body: m.text,
    tag: 'sauerteig',
    renotify: true,
    data: { url: location.pathname },
  };
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) {
      await reg.showNotification(m.titel, opts);
      return;
    }
  } catch {
    /* weiter mit der Notification-API */
  }
  try {
    new Notification(m.titel, opts);
  } catch {
    /* z. B. Android ohne Service Worker */
  }
}

/** Für die Anzeige in der offenen App (Toast), zusätzlich zur Mitteilung. */
export const meldungHoerer = new Set<(m: Meldung) => void>();

let ticker: ReturnType<typeof setInterval> | null = null;

function tick(): void {
  const gespeichert = lade(); // anderer Tab hat evtl. schon gemeldet
  if (!gespeichert) {
    if (lauf) setze(null);
    return;
  }
  const jetzt = Date.now();
  const letzter = gespeichert.schritte[gespeichert.schritte.length - 1];
  if (!letzter || jetzt - letzter.at > AUFRAEUMEN_NACH) {
    setze(null);
    return;
  }
  const neu = faellig(gespeichert, jetzt);
  if (neu.length || gespeichert.gemeldet.length !== lauf?.gemeldet.length) setze(gespeichert);
  for (const m of neu) {
    if (!gespeichert.fern) void zeige(m);
    meldungHoerer.forEach((f) => f(m));
  }
}

function plane(): void {
  if (lauf && !ticker) {
    ticker = setInterval(tick, 5000);
    if (typeof document !== 'undefined') document.addEventListener('visibilitychange', tick);
  } else if (!lauf && ticker) {
    clearInterval(ticker);
    ticker = null;
    document.removeEventListener('visibilitychange', tick);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e) => {
    if (e.key === KEY) {
      lauf = lade();
      hoerer.forEach((f) => f());
      plane();
    }
  });
  plane();
}
