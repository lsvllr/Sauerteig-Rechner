// KI-Analyse der Krume für das Backtagebuch der iOS-App (ios/Sauerteig/Pages/TagebuchAnsicht.swift, Abgleich.analysiereKrume).
// Die App schickt Fotos (JPEG, Base64) und Angaben zum Backen (KIKontext in ios/Sauerteig/Core/Tagebuch.swift); der
// Server baut daraus den Prompt, fragt Gemini mit festem Antwortschema und gibt die geprüfte Antwort zurück.
// Bewusste Ausnahme von der Verschlüsselung, nur auf Knopfdruck: Fotos und Angaben gehen an Google, der Server
// speichert nichts davon. Der API-Schlüssel liegt nur hier (GEMINI_API_KEY), nicht in der App.

const API_KEY = process.env.GEMINI_API_KEY ?? '';
const MODELL = process.env.GEMINI_MODEL || 'gemini-3.5-flash';
const JE_TAG = Number(process.env.GEMINI_JE_TAG ?? 30);
/** Denkstufe (low | medium | high); ohne Angabe denkt Gemini 3 „medium“ oder mehr und braucht mit Fotos leicht über 90 s. */
const DENKEN = process.env.GEMINI_DENKEN || 'low';

export const MAX_BODY_KI = 4_000_000;
const MAX_BILDER = 3;
const MAX_BILD = 1_500_000; // Zeichen Base64, gut 1 MB
const MAX_KONTEXT = 20_000;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

export const aktiv = (): boolean => API_KEY !== '';

/** Stellgrößen wie `Stellgroesse` in der App. */
const PARAMETER = ['anstellgut', 'sauerteigTemp', 'gareTemp', 'brotGroesse', 'hydration', 'ofenTemp'] as const;

const SYSTEM = `Du bist erfahrene Bäckermeisterin für Sauerteigbrote mit hohem Roggenanteil und beurteilst Fotos
selbst gebackener Brote aus einer Rechner-App. Antworte auf Deutsch, knapp und konkret, ohne Floskeln.

So beurteilst du die Krume (Anschnitt):
- Untergare: dichte, feuchte oder speckige Schicht über dem Boden, einzelne große Löcher oder ein Hohlraum direkt
  unter der Kruste (abgerissene Kruste), Risse seitlich, geringer Ofentrieb.
- Übergare: flaches, breit gelaufenes Brot, kaum Ofentrieb, gleichmäßig feine aber teils zerrissene Poren,
  eingefallene Oberfläche, säuerlicher Geruch laut Notiz.
- Speckig oder klebrig: zu früh angeschnitten, zu kurz oder zu kühl gebacken, oder zu viel Wasser für den Roggenanteil.
- Roggen: Ab etwa 60 % Roggen ist eine dichte, gleichmäßige, saftige Krume ohne große Poren richtig und kein Fehler.
  Rate dann nicht zu „offenerer Porung“. Beurteile nach Saftigkeit, Gleichmäßigkeit, Schicht unten, Hohlräumen.
- Weizen- und Dinkelanteil machen die Krume lockerer und offener.
Ist kein Anschnitt zu sehen oder das Foto unscharf, sag das, setze gare auf "unklar" und sicherheit auf "niedrig".

So hängt der Rechner der App zusammen (nur diese Einstellungen gibt es, Zeiten rechnet die App daraus):
- sauerteigTemp (18–32 °C): Temperatur beim Reifen des Sauerteigs. Wärmer = schneller reif, milder; kühler = länger, saurer.
- gareTemp (20–32 °C): Temperatur der Stückgare. Ab 28 °C ist die Stückgare etwa 25 % kürzer, unter 24 °C etwa 15 % länger.
  Die erste Gare (Stockgare) ist fest und hängt nicht davon ab.
- hydration (50–85 %): Wasser bezogen auf das gesamte Mehl.
- anstellgut (30–200 g): Menge Anstellgut; skaliert den ganzen Teig mit (Sauerteig 1 : 2 : 2), ändert nicht die Säure.
- brotGroesse (600–2000 g, Schritte 100): Teiggewicht.
- ofenTemp (200–250 °C, Schritte 5): Backtemperatur nach der Dampfphase; Backzeit passt die App an.
Im Kontext stehen geplante und tatsächliche Zeiten in Minuten ab dem Ansetzen des Sauerteigs. Große Abweichungen
(z. B. Sauerteig viel später reif als geplant) sind oft die Ursache.

Vorschläge: höchstens vier, das Wichtigste zuerst. Ein Vorschlag ändert entweder eine Einstellung (parameter =
Name der Einstellung, aenderung = Änderung als Zahl, z. B. 2 für +2 °C oder -3 für -3 % Hydration, text leer) oder
ist ein Hinweis zur Arbeitsweise (parameter = "keiner", aenderung = 0, text = der Hinweis). grund: ein Satz warum.
Ändere Einstellungen vorsichtig (Temperaturen um 1–3 °C, Hydration um 2–5 %). Beziehe frühere Backen derselben
Mischung ein, wenn sie im Kontext stehen, und wiederhole keine Änderung, die schon nicht geholfen hat.`;

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    krume: {
      type: 'OBJECT',
      properties: {
        porung: { type: 'STRING', enum: ['offen', 'mittel', 'dicht'] },
        gleichmaessig: { type: 'BOOLEAN' },
        auffaelligkeiten: { type: 'ARRAY', items: { type: 'STRING' } },
      },
      required: ['porung', 'gleichmaessig', 'auffaelligkeiten'],
    },
    gare: { type: 'STRING', enum: ['unter', 'optimal', 'ueber', 'unklar'] },
    kruste: { type: 'STRING' },
    diagnose: { type: 'STRING' },
    vorschlaege: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          parameter: { type: 'STRING', enum: [...PARAMETER, 'keiner'] },
          aenderung: { type: 'NUMBER' },
          text: { type: 'STRING' },
          grund: { type: 'STRING' },
        },
        required: ['parameter', 'aenderung', 'text', 'grund'],
      },
    },
    sicherheit: { type: 'STRING', enum: ['hoch', 'mittel', 'niedrig'] },
  },
  required: ['krume', 'gare', 'kruste', 'diagnose', 'vorschlaege', 'sicherheit'],
};

export interface Analyse {
  krume: { porung: string; gleichmaessig: boolean; auffaelligkeiten: string[] };
  gare: string;
  kruste: string;
  diagnose: string;
  vorschlaege: { parameter: string; aenderung: number; text: string; grund: string }[];
  sicherheit: string;
}

/* ---------- Grenzen je Konto (im Speicher, zählt ab Mitternacht neu) ---------- */

const zaehler = new Map<number, { tag: string; n: number }>();

function zuViel(konto: number): boolean {
  const tag = new Date().toISOString().slice(0, 10);
  const z = zaehler.get(konto);
  if (!z || z.tag !== tag) {
    zaehler.set(konto, { tag, n: 1 });
    return false;
  }
  z.n += 1;
  return z.n > JE_TAG;
}

/* ---------- Prüfen ---------- */

export function pruefeAnfrage(d: Record<string, unknown>): { bilder: string[]; kontext: string } | null {
  const b = d.bilder;
  if (!Array.isArray(b) || b.length < 1 || b.length > MAX_BILDER) return null;
  if (!b.every((x) => typeof x === 'string' && x.length <= MAX_BILD && BASE64.test(x))) return null;
  const k = d.kontext;
  if (!k || typeof k !== 'object') return null;
  const kontext = JSON.stringify(k, null, 1);
  if (kontext.length > MAX_KONTEXT) return null;
  return { bilder: b as string[], kontext };
}

const text = (v: unknown, max: number): string => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const eins = <T extends string>(v: unknown, erlaubt: readonly T[], sonst: T): T =>
  typeof v === 'string' && (erlaubt as readonly string[]).includes(v) ? (v as T) : sonst;

/** Antwort von Gemini auf das Schema der App bringen; Unbrauchbares fällt weg. */
export function saeubere(roh: unknown): Analyse | null {
  if (!roh || typeof roh !== 'object') return null;
  const r = roh as Record<string, unknown>;
  const k = (r.krume && typeof r.krume === 'object' ? r.krume : {}) as Record<string, unknown>;
  const diagnose = text(r.diagnose, 1200);
  if (!diagnose) return null;
  const vorschlaege = (Array.isArray(r.vorschlaege) ? r.vorschlaege : [])
    .slice(0, 4)
    .map((v) => {
      const x = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
      const parameter = eins(x.parameter, [...PARAMETER, 'keiner'] as const, 'keiner');
      const aenderung = typeof x.aenderung === 'number' && Number.isFinite(x.aenderung) ? x.aenderung : 0;
      return {
        parameter: parameter !== 'keiner' && aenderung !== 0 ? parameter : '',
        aenderung: parameter !== 'keiner' ? Math.max(-200, Math.min(200, aenderung)) : 0,
        text: text(x.text, 300),
        grund: text(x.grund, 400),
      };
    })
    .filter((v) => v.parameter !== '' || v.text !== '');
  return {
    krume: {
      porung: eins(k.porung, ['offen', 'mittel', 'dicht'] as const, 'mittel'),
      gleichmaessig: k.gleichmaessig === true,
      auffaelligkeiten: (Array.isArray(k.auffaelligkeiten) ? k.auffaelligkeiten : [])
        .map((a) => text(a, 200))
        .filter(Boolean)
        .slice(0, 6),
    },
    gare: eins(r.gare, ['unter', 'optimal', 'ueber', 'unklar'] as const, 'unklar'),
    kruste: text(r.kruste, 400),
    diagnose,
    vorschlaege,
    sicherheit: eins(r.sicherheit, ['hoch', 'mittel', 'niedrig'] as const, 'mittel'),
  };
}

/* ---------- Gemini ---------- */

export type Ergebnis = { ok: true; analyse: Analyse } | { ok: false; status: number; fehler: string };

type GeminiAntwort = {
  candidates?: { content?: { parts?: { text?: string; thought?: boolean }[] }; finishReason?: string }[];
  error?: { message?: string };
} | null;

/** Gesamtfrist für alle Versuche: Cloudflare bricht nach 100 s ab, die App nach 120 s. */
const FRIST = 85_000;
/** Pausen vor dem 2. und 3. Versuch */
const PAUSEN = [1_000, 3_000];
const AUSGELASTET = new Set([429, 500, 503]);
/** Schlüssel falsch oder gesperrt: ein anderes Modell hilft nicht. */
const SCHLUESSEL = new Set([401, 403]);
/** Ausweichmodelle, wenn das Modell ausgelastet ist (Google meldet 503 „high demand“ oft nur für ein Modell).
 *  Die Versuche gehen der Reihe nach durch MODELL und diese Liste. */
const ERSATZ = (process.env.GEMINI_ERSATZ ?? 'gemini-3.8-flash,gemini-3.5-flash-lite')
  .split(',')
  .map((m) => m.trim())
  .filter(Boolean);
const MODELLE = [...new Set([MODELL, ...ERSATZ])];

/** Fragt Gemini; klappt es nicht, nach kurzer Pause mit dem nächsten Modell, solange die Frist reicht. */
async function frageGemini(body: string): Promise<{ ok: true; antwort: GeminiAntwort } | { ok: false; status: number; fehler: string }> {
  const ende = Date.now() + FRIST;
  for (let versuch = 0; ; versuch++) {
    const modell = MODELLE[versuch % MODELLE.length];
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modell)}:generateContent`;
    let r: Response;
    try {
      r = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': API_KEY },
        body,
        signal: AbortSignal.timeout(Math.max(1_000, ende - Date.now())),
      });
    } catch (err) {
      const zeit = err instanceof Error && err.name === 'TimeoutError';
      console.warn(`Gemini ${modell} nicht erreichbar (Versuch ${versuch + 1}):`, zeit ? 'Zeit abgelaufen' : err);
      return { ok: false, status: 504, fehler: zeit ? 'Gemini hat zu lange gebraucht, bitte noch einmal' : 'Gemini ist gerade nicht erreichbar' };
    }
    const antwort = (await r.json().catch(() => null)) as GeminiAntwort;
    if (r.ok) {
      if (versuch > 0) console.log(`Gemini: Antwort von ${modell} (Versuch ${versuch + 1})`);
      return { ok: true, antwort };
    }
    console.warn(`Gemini ${modell} HTTP ${r.status} (Versuch ${versuch + 1}):`, antwort?.error?.message ?? '');
    const pause = PAUSEN[versuch];
    // Neuer Versuch (mit dem nächsten Modell) nur, wenn danach noch Zeit für eine Antwort bleibt (gut 30 s).
    if (!SCHLUESSEL.has(r.status) && pause !== undefined && Date.now() + pause + 30_000 < ende) {
      await new Promise((f) => setTimeout(f, pause));
      continue;
    }
    return {
      ok: false,
      status: 502,
      fehler: AUSGELASTET.has(r.status) ? 'Gemini ist gerade ausgelastet, bitte in ein paar Minuten noch einmal' : 'Gemini hat die Anfrage abgelehnt',
    };
  }
}

export async function analysiere(konto: number, a: { bilder: string[]; kontext: string }): Promise<Ergebnis> {
  if (!aktiv()) return { ok: false, status: 503, fehler: 'Die KI-Analyse ist auf dem Server nicht eingerichtet' };
  if (zuViel(konto)) return { ok: false, status: 429, fehler: `Heute schon ${JE_TAG} Analysen, morgen wieder` };
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [
      {
        role: 'user',
        parts: [
          {
            text:
              `Fotos: ${a.bilder.length} (das erste ist meist der Anschnitt). Angaben zu diesem Backen und zu früheren ` +
              `Backen derselben Mischung (JSON):\n${a.kontext}\n\nBeurteile das Brot und schlage Verbesserungen vor.`,
          },
          ...a.bilder.map((data) => ({ inlineData: { mimeType: 'image/jpeg', data } })),
        ],
      },
    ],
    // Kein eigener Wert für temperature: Gemini 3 ist auf 1.0 abgestimmt, darunter kann es sich in Schleifen
    // verrennen. Wenig Denken reicht für ein Foto mit festem Schema und hält die Antwort weit unter der Frist.
    generationConfig: { responseMimeType: 'application/json', responseSchema: SCHEMA, thinkingConfig: { thinkingLevel: DENKEN } },
  };
  const r = await frageGemini(JSON.stringify(body));
  if (!r.ok) return r;
  const antwort = r.antwort;
  const teile = antwort?.candidates?.[0]?.content?.parts ?? [];
  const json = teile.filter((p) => !p.thought && typeof p.text === 'string').map((p) => p.text).join('');
  let roh: unknown = null;
  try {
    roh = JSON.parse(json);
  } catch {
    console.warn('Gemini: Antwort kein JSON, finishReason', antwort?.candidates?.[0]?.finishReason);
  }
  const analyse = saeubere(roh);
  if (!analyse) return { ok: false, status: 502, fehler: 'Gemini hat keine brauchbare Antwort gegeben' };
  return { ok: true, analyse };
}
