// Weckdienst für die Live-Aktivität des Back-Timers der iOS-App (ios/LOCAL-FIRST.md, Abschnitt 6.6).
//
// Einzige Aufgabe: zu jeder Schrittzeit einen APNs-Push an die Live-Aktivität schicken, damit sie auf dem
// Sperrbildschirm auch bei geschlossener App zum nächsten Schritt weiterschaltet. Der Dienst kennt nur den Push-Token
// der Aktivität und die Zeitpunkte, keine Rezepte, Titel oder Konten. Inhalt der Nutzlast:
// {"zeiten": [ms…], "aktuell": i}; Titel und Dauer stehen in den Attributen der Aktivität auf dem Gerät.
//
//   POST /api/wecker       {token: "apns:<hex>" | "apns-sandbox:<hex>", zeiten: [ms…]}   gleicher Token → ersetzt
//   POST /api/wecker/stop  {token}                                                    beendet die Aktivität
import * as apns from './apns';
import * as db from './db';

/** Kurz nach der Schrittzeit gilt die Anzeige als veraltet (dann rechnet die Ansicht selbst weiter). */
const STALE_NACH_S = 30;
/** Nach dem letzten Schritt bleibt die Aktivität so lange stehen (Auskühlen). */
const AUSKUEHLEN_S = 2 * 3600;
/** Später erkannt (z. B. nach einem Neustart): nicht mehr schicken. */
const ZU_SPAET = 10 * 60_000;
/** So lange nach dem letzten Schritt verschwindet ein Eintrag von selbst. */
const AUFRAEUMEN_NACH = 3 * 3600_000;
const MAX_EINTRAEGE = 2000;

/** Laufender Schritt: der letzte, dessen Zeit erreicht ist (0, wenn noch keiner). */
export function aktuell(zeiten: number[], jetzt: number): number {
  let i = 0;
  zeiten.forEach((z, j) => {
    if (z <= jetzt) i = j;
  });
  return i;
}

/** Anmeldung prüfen: gültiger Token, 2–20 aufsteigende Zeiten, höchstens 7 Tage weg. */
export function pruefe(v: unknown, jetzt: number): { token: string; zeiten: number[] } | null {
  const d = v as { token?: unknown; zeiten?: unknown } | null;
  if (!d || typeof d.token !== 'string' || !apns.zerlege(d.token)) return null;
  if (!Array.isArray(d.zeiten) || d.zeiten.length < 2 || d.zeiten.length > 20) return null;
  const zeiten: number[] = [];
  for (const z of d.zeiten) {
    if (typeof z !== 'number' || !Number.isFinite(z) || Math.abs(z - jetzt) > 7 * 24 * 3600_000) return null;
    if (zeiten.length && z < zeiten[zeiten.length - 1]!) return null;
    zeiten.push(Math.round(z));
  }
  return { token: d.token.toLowerCase(), zeiten };
}

export function anmelden(token: string, zeiten: number[], jetzt: number): boolean {
  if (db.anzahlWecker() >= MAX_EINTRAEGE) return false;
  // Den Stand von jetzt zeigt die App schon selbst; gemeldet wird erst der nächste Schritt.
  db.setzeWecker({ token, zeiten, gesendet: aktuell(zeiten, jetzt) });
  return true;
}

export async function stoppen(token: string): Promise<void> {
  const w = db.wecker().find((x) => x.token === token);
  db.loescheWecker(token);
  if (!w || !apns.aktiv()) return;
  const jetzt = Date.now();
  await apns.sendeAktivitaet(token, 'end', { zeiten: w.zeiten, aktuell: aktuell(w.zeiten, jetzt) }, undefined, jetzt / 1000);
}

/** Alle 10 s: fällige Schritte melden, beim letzten die Aktivität beenden. */
export async function tick(jetzt = Date.now()): Promise<void> {
  const ein = apns.aktiv();
  for (const w of db.wecker()) {
    const letzte = w.zeiten.length - 1;
    const i = aktuell(w.zeiten, jetzt);
    if (jetzt - w.zeiten[letzte]! > AUFRAEUMEN_NACH) {
      db.loescheWecker(w.token);
      continue;
    }
    if (!ein || i <= w.gesendet) continue;
    if (jetzt - w.zeiten[i]! > ZU_SPAET) {
      if (i >= letzte) db.loescheWecker(w.token);
      else db.setzeWeckerGesendet(w.token, w.zeiten, i);
      continue;
    }
    const ende = i >= letzte;
    const state = { zeiten: w.zeiten, aktuell: i };
    const r = ende
      ? await apns.sendeAktivitaet(w.token, 'end', state, undefined, w.zeiten[letzte]! / 1000 + AUSKUEHLEN_S)
      : await apns.sendeAktivitaet(w.token, 'update', state, w.zeiten[i + 1]! / 1000 + STALE_NACH_S);
    if (r === 'gone' || (r === 'ok' && ende)) db.loescheWecker(w.token);
    else if (r === 'ok') db.setzeWeckerGesendet(w.token, w.zeiten, i);
    // 'error': im nächsten Takt erneut, bis ZU_SPAET
  }
}
