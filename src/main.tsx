// Eigenständiger Sauerteig-Rechner: Oberfläche und Design aus der Haushalt-App (src/gemeinsam, übernommen mit
// scripts/sync-haushalt.sh). Läuft ganz im Browser: Rezepte und Back-Timer liegen in der lokalen Datenbank
// (datenbank.ts, timerDaten.ts), auch ohne Konto und ohne Netz. Ein Konto (nur mit Einladung, zugang.tsx, Admin
// unter /admin) braucht es, um Geräte zu verknüpfen: Ab zwei Geräten gleichen sie sich über den Server ab
// (abgleich.ts), und der Server schickt die Erinnerungen des Back-Timers per Push (fern.ts).
import { StrictMode, useEffect, useState, useSyncExternalStore, type FormEvent, type FormHTMLAttributes } from 'react';
import { createRoot } from 'react-dom/client';
import './gemeinsam/haushalt.css';
import './app.css';
import { Rechner, START, alsEinstellungen, type Rezept, type Werte } from './gemeinsam/Oberflaeche';
import { abonniereGeraete, fehltSchluessel, geraete, gleicheAb, starteAbgleich, trenneAbgleich } from './abgleich';
import { entpacke, leseSchluessel, merkeSchluessel, neuerSchluessel, neuesGeheimnis, verpacke, zerlegeCode, zeigeCode } from './schluessel';
import { db, rezepte as lokaleRezepte, speichereRezept } from './datenbank';
import { installiereTimerDaten } from './timerDaten';
import { leseKonto, merkeKonto, uebernimmAlteRezepte, type Konto } from './speicher';
import { Offline, post, rufe } from './api';
import { installiereFernPush, meldeGeraet, vergissPush } from './fern';
import { inHaushaltApp, installiereHaushaltApp } from './haushaltApp';
import { installiereBlaetter, oeffneBlatt, schliesseBlatt, zeigeToast } from './ui';
import { Zugang } from './zugang';
import { Admin } from './admin';

/** Zahl-ID für die Oberfläche (aus der Haushalt-App, rechnet mit Zahlen): die letzten 48 Bit der uid. */
const lokaleId = (uid: string) => parseInt(uid.replace(/-/g, '').slice(-12), 16) || 0;

function App() {
    const [konto, setKontoState] = useState<Konto | null>(() => leseKonto());
    const setKonto = (k: Konto | null) => {
        merkeKonto(k);
        if (!k) merkeSchluessel(null); // Schlüssel gehört zum Konto; bei erneutem Verknüpfen kommt er mit dem Code
        setKontoState(k);
    };

    // Mit Konto abgleichen; meldet der Server die Sitzung als unbekannt (Konto gelöscht), nur noch lokal
    useEffect(() => {
        if (!konto) {
            trenneAbgleich();
            return;
        }
        starteAbgleich(() => setKonto(null));
        if (import.meta.env.PROD && !inHaushaltApp) void meldeGeraet();
    }, [!!konto]);

    // Name des Kontos aktuell halten (umbenannt, gelöscht)
    useEffect(() => {
        if (!konto) return;
        const pruefe = async () => {
            if (document.visibilityState !== 'visible') return;
            try {
                const r = await rufe('/api/ich');
                if (r.status === 401) setKonto(null);
                else if (r.ok && r.name !== konto.name) setKonto({ name: String(r.name) });
            } catch { /* offline */ }
        };
        void pruefe();
        document.addEventListener('visibilitychange', pruefe);
        return () => document.removeEventListener('visibilitychange', pruefe);
    }, [konto?.name]);

    return <Rezepte konto={konto} setKonto={setKonto} />;
}

function Rezepte({ konto, setKonto }: { konto: Konto | null; setKonto: (k: Konto | null) => void }) {
    const [w, setW] = useState<Werte>(START);
    const [code, setCode] = useState<{ code: string; gueltigBis: number } | null>(null);
    const [mitteilungen, setMitteilungen] = useState<NotificationPermission | 'fehlt'>(() =>
        typeof Notification === 'undefined' || !('serviceWorker' in navigator) ? 'fehlt' : Notification.permission,
    );
    useSyncExternalStore(db.abonniere, db.stand);
    const anzahlGeraete = useSyncExternalStore(abonniereGeraete, geraete);
    const ohneSchluessel = useSyncExternalStore(abonniereGeraete, fehltSchluessel);
    const [busy, setBusy] = useState(false);

    const einschalten = async () => {
        const p = await Notification.requestPermission();
        setMitteilungen(p);
        if (p === 'granted') {
            if (konto) await meldeGeraet();
            zeigeToast('Mitteilungen eingeschaltet', 'success');
        }
    };

    const lokal = lokaleRezepte();
    const uidZu = new Map(lokal.map((r) => [lokaleId(r.uid), r.uid]));
    const rezepte: Rezept[] = lokal.map((r) => ({
        id: lokaleId(r.uid),
        name: r.name,
        datum: r.datum,
        settings: r.einstellungen,
    }));

    const sichern = (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const form = e.currentTarget;
        const name = String(new FormData(form).get('name') ?? '').trim();
        if (!name) return;
        speichereRezept(name, new Date().toLocaleDateString('de-DE'), alsEinstellungen(w) as unknown as Record<string, unknown>);
        schliesseBlatt(form.closest('dialog'));
        zeigeToast(`„${name}“ gesichert`, 'success');
    };

    const loeschenForm = (r: Rezept): FormHTMLAttributes<HTMLFormElement> => ({
        onSubmit: (e) => {
            e.preventDefault();
            const uid = uidZu.get(r.id);
            if (uid) db.loesche('rezept', uid);
            zeigeToast(`„${r.name}“ gelöscht`, 'success');
        },
    });

    const ohneNetz = () => zeigeToast('Keine Verbindung. Das geht nur online.', 'error');

    /** Code = Teil für den Server + Geheimnis, mit dem der Schlüssel verpackt ist (geht nie an den Server). */
    const geraetecode = async () => {
        setBusy(true);
        try {
            let k = leseSchluessel();
            if (!k) merkeSchluessel((k = neuerSchluessel()));
            const geheim = neuesGeheimnis();
            const r = await post('/api/geraetecode', { schluessel: await verpacke(k, geheim) });
            if (r.status === 401) return setKonto(null);
            if (!r.ok) return zeigeToast(r.error ?? 'Das hat nicht geklappt', 'error');
            setCode({ code: zeigeCode(String(r.code), geheim), gueltigBis: Number(r.gueltigBis) });
        } catch {
            ohneNetz();
        } finally {
            setBusy(false);
        }
    };

    /** Schlüssel mit dem Gerätecode eines anderen Geräts holen (dieses Gerät ist schon im Konto). */
    const schluesselHolen = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const form = e.currentTarget;
        const teile = zerlegeCode(String(new FormData(form).get('code') ?? ''));
        if (!teile.geheim) return zeigeToast('Bitte den ganzen Code mit 16 Zeichen eingeben', 'error');
        setBusy(true);
        try {
            const r = await post('/api/schluessel', { code: teile.server });
            const k = r.ok && typeof r.schluessel === 'string' ? await entpacke(r.schluessel, teile.geheim) : null;
            if (!k) return zeigeToast(r.error ?? 'Code passt nicht', 'error');
            merkeSchluessel(k);
            form.reset();
            zeigeToast('Schlüssel übernommen', 'success');
            void gleicheAb();
        } catch {
            ohneNetz();
        } finally {
            setBusy(false);
        }
    };

    const abmelden = async () => {
        if (!confirm('Dieses Gerät vom Konto trennen? Rezepte und Timer bleiben auf diesem Gerät, gleichen sich aber nicht mehr ab.')) return;
        try {
            const endpoint = await vergissPush();
            const r = await post('/api/abmelden', { endpoint });
            if (!r.ok && r.status !== 401) return zeigeToast(r.error ?? 'Das hat nicht geklappt', 'error');
        } catch (err) {
            if (err instanceof Offline) return ohneNetz();
        }
        setKonto(null);
    };

    const verknuepft = (name: string) => {
        setKonto({ name });
        zeigeToast(`Verknüpft mit „${name}“`, 'success');
        void gleicheAb();
    };

    return (
        <>
            <div id="toast" role="status" aria-live="polite" />
            <main className="container">
                <div className="lt-row sd-kopf">
                    <h1 className="large-title">Sauerteig-Rechner</h1>
                    <button type="button" className="btn icon-btn sd-zahnrad" aria-label="Einstellungen"
                        onClick={() => { setCode(null); oeffneBlatt('sd-einstellungen-sheet'); }}>
                        <Zahnrad />
                    </button>
                </div>
                <p className="muted sd-untertitel">Vollkornbrot aus Roggen, Dinkel, Weizen und Buchweizen</p>
                <Rechner
                    w={w}
                    setW={setW}
                    rezepte={rezepte}
                    melde={zeigeToast}
                    oeffneBlatt={oeffneBlatt}
                    sichernForm={{ onSubmit: sichern }}
                    loeschenForm={loeschenForm}
                    speicherHinweis={
                        konto && anzahlGeraete >= 2
                            ? `Wird auf diesem Gerät gespeichert und mit den Geräten von „${konto.name}“ abgeglichen.`
                            : 'Wird auf diesem Gerät gespeichert.'
                    }
                />
            </main>

            <dialog className="sheet" id="sd-einstellungen-sheet" aria-labelledby="sd-einstellungen-t">
                <div className="sheet-body stack">
                    <div className="sheet-bar">
                        <span />
                        <h2 className="sheet-title" id="sd-einstellungen-t">Einstellungen</h2>
                        <button type="button" className="sheet-cancel sd-sheet-ok" data-close="">Fertig</button>
                    </div>

                    <h3 className="section-title">Mitteilungen</h3>
                    <div className="card stack">
                        <p className="muted small">
                            {inHaushaltApp
                                ? 'Mitteilungen des Back-Timers kommen über die Haushalt-App.'
                                : mitteilungen === 'denied'
                                    ? 'Mitteilungen sind für diese Seite im Browser abgeschaltet. Einschalten geht in den Einstellungen des Browsers.'
                                    : mitteilungen === 'fehlt'
                                        ? 'Für Mitteilungen des Back-Timers die App zum Home-Bildschirm hinzufügen und von dort öffnen.'
                                        : !konto
                                            ? 'Ohne Konto meldet der Back-Timer sich, solange die Seite offen ist. Mit Konto kommen die Meldungen auch bei geschlossener Seite.'
                                            : mitteilungen === 'granted'
                                                ? 'Eingeschaltet: Dieses Gerät meldet die Back-Timer des Kontos, auch die von anderen Geräten.'
                                                : 'Mitteilungen einschalten, damit dieses Gerät die Back-Timer des Kontos meldet, auch die von anderen Geräten.'}
                        </p>
                        {!inHaushaltApp && mitteilungen === 'default' && (
                            <button type="button" className="btn accent-fill" onClick={einschalten}>Mitteilungen einschalten</button>
                        )}
                    </div>

                    <h3 className="section-title">Geräte verknüpfen</h3>
                    <div className="card stack">
                        {!konto ? (
                            <>
                                <p className="muted small">
                                    Alles liegt nur auf diesem Gerät. Mit einem Konto gleichen sich Rezepte und Timer
                                    zwischen deinen Geräten ab (auch mit der iPhone-App). Der Server hält die Daten
                                    nur, solange mindestens zwei Geräte verknüpft sind.
                                </p>
                                <Zugang angemeldet={verknuepft} />
                            </>
                        ) : (
                            <>
                                <p className="sd-konto">Konto <strong>{konto.name}</strong></p>
                                <p className="muted small">
                                    {anzahlGeraete >= 2
                                        ? `${anzahlGeraete} Geräte verknüpft, sie gleichen sich Ende-zu-Ende verschlüsselt ab. Der Server kann nichts davon lesen.`
                                        : 'Nur dieses Gerät ist verknüpft, am Server liegt nichts. Verknüpfe ein weiteres, damit sie sich abgleichen.'}
                                </p>
                                {ohneSchluessel && (
                                    <form className="stack" onSubmit={schluesselHolen}>
                                        <p className="zg-fehler">
                                            Diesem Gerät fehlt der Schlüssel des Kontos. Auf einem anderen Gerät „Weiteres
                                            Gerät verknüpfen“ tippen und den Code hier eingeben.
                                        </p>
                                        <input name="code" type="text" required autoComplete="one-time-code" autoCapitalize="characters"
                                            spellCheck={false} placeholder="XXXX-XXXX-XXXX-XXXX" aria-label="Gerätecode" />
                                        <button type="submit" className="btn accent-fill" disabled={busy}>Schlüssel holen</button>
                                    </form>
                                )}
                                {code ? (
                                    <>
                                        <p>
                                            Auf dem anderen Gerät {location.host} oder die iPhone-App öffnen und in den
                                            Einstellungen unter „Geräte verknüpfen“ diesen Code eingeben:
                                        </p>
                                        <p className="ad-code">{code.code}</p>
                                        <p className="muted small">
                                            Gilt bis {new Date(code.gueltigBis).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })} Uhr,
                                            nur einmal.
                                        </p>
                                    </>
                                ) : (
                                    <button type="button" className="btn" onClick={geraetecode} disabled={busy}>Weiteres Gerät verknüpfen</button>
                                )}
                                <button type="button" className="btn danger" onClick={abmelden}>Dieses Gerät trennen</button>
                            </>
                        )}
                    </div>
                </div>
            </dialog>
        </>
    );
}

/** Zahnrad (gleicher Strich wie src/gemeinsam/symbole.tsx; dort nicht, weil die Datei aus der Haushalt-App kommt). */
function Zahnrad() {
    return (
        <svg className="sf" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"
            strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
        </svg>
    );
}

// Ältere Stände in die lokale Datenbank, Timer an die Datenbank hängen
uebernimmAlteRezepte();
installiereTimerDaten();
// In der iOS-App von Haushalt: Back-Timer an die App, die meldet (vor dem ersten Zeichnen, wegen der Mitteilungs-Attrappe)
void installiereHaushaltApp();
installiereBlaetter();
createRoot(document.getElementById('app')!).render(
    <StrictMode>{location.pathname.replace(/\/$/, '') === '/admin' ? <Admin /> : <App />}</StrictMode>,
);

// Offline-Betrieb (nur im Build, im Dev-Server würde der Cache stören)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js')
        .then(() => { if (!inHaushaltApp) installiereFernPush(); }) // Back-Timer: Push vom Server ab „Backen beginnen“
        .catch(() => { /* App läuft auch ohne */ });
    // Lokale Datenbank vor automatischem Löschen durch den Browser schützen
    navigator.storage?.persist?.().catch(() => { /* ignorieren */ });
}
