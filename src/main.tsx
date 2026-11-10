// Eigenständiger Sauerteig-Rechner: Oberfläche und Design aus der Haushalt-App (src/gemeinsam, übernommen mit
// scripts/sync-haushalt.sh). Konten nur mit Einladung (zugang.tsx, Admin unter /admin), Rezepte im Konto auf dem
// Server mit Kopie im Browser für den Offline-Betrieb (speicher.ts). Der Server (server/server.ts) schickt die
// Erinnerungen des Back-Timers per Push an alle Geräte des Kontos (fern.ts).
import { StrictMode, useEffect, useState, type FormEvent, type FormHTMLAttributes } from 'react';
import { createRoot } from 'react-dom/client';
import './gemeinsam/haushalt.css';
import './app.css';
import { Rechner, START, alsEinstellungen, type Rezept, type Werte } from './gemeinsam/Oberflaeche';
import { beendeLauf } from './gemeinsam/timer';
import { leseKonto, merkeKonto, type Einstellungen, type KontoRezept, type KontoStand } from './speicher';
import { Offline, post, rufe } from './api';
import { installiereFernPush, meldeGeraet, vergissPush } from './fern';
import { installiereBlaetter, oeffneBlatt, schliesseBlatt, zeigeToast } from './ui';
import { Zugang } from './zugang';
import { Admin } from './admin';

/** Konto und Rezepte vom Server holen; null = nicht (mehr) angemeldet. Wirft Offline. */
async function holeKonto(): Promise<KontoStand | null> {
    const ich = await rufe('/api/ich');
    if (ich.status === 401) return null;
    const r = await rufe('/api/rezepte');
    if (!ich.ok || !r.ok) throw new Offline('Server antwortet nicht');
    return { name: String(ich.name), rezepte: r.rezepte as KontoRezept[] };
}

function App() {
    // Mit Kopie im Browser sofort starten (auch offline), dann mit dem Server abgleichen
    const [konto, setKonto] = useState<KontoStand | null | undefined>(() => leseKonto() ?? undefined);
    const [offline, setOffline] = useState(false);

    const setze = (k: KontoStand | null) => {
        merkeKonto(k);
        setKonto(k);
    };

    const abgleichen = async () => {
        try {
            const k = await holeKonto();
            setze(k);
            setOffline(false);
            if (k && import.meta.env.PROD) void meldeGeraet();
        } catch {
            setOffline(true);
        }
    };

    useEffect(() => {
        void abgleichen();
        const sichtbar = () => { if (document.visibilityState === 'visible') void abgleichen(); };
        document.addEventListener('visibilitychange', sichtbar);
        return () => document.removeEventListener('visibilitychange', sichtbar);
    }, []);

    if (konto === undefined)
        return offline ? (
            <main className="container">
                <h1 className="large-title sd-titel">Sauerteig-Rechner</h1>
                <div className="card narrow stack">
                    <p>Keine Verbindung. Zum ersten Anmelden braucht es Internet.</p>
                    <button type="button" className="btn" onClick={abgleichen}>Erneut versuchen</button>
                </div>
            </main>
        ) : null;
    if (konto === null) return <Zugang angemeldet={() => void abgleichen()} />;
    return <Rezepte konto={konto} offline={offline} setze={setze} abgleichen={abgleichen} />;
}

function Rezepte({ konto, offline, setze, abgleichen }: {
    konto: KontoStand;
    offline: boolean;
    setze: (k: KontoStand | null) => void;
    abgleichen: () => Promise<void>;
}) {
    const [w, setW] = useState<Werte>(START);
    const [code, setCode] = useState<{ code: string; gueltigBis: number } | null>(null);
    const [mitteilungen, setMitteilungen] = useState<NotificationPermission | 'fehlt'>(() =>
        typeof Notification === 'undefined' || !('serviceWorker' in navigator) ? 'fehlt' : Notification.permission,
    );

    const einschalten = async () => {
        const p = await Notification.requestPermission();
        setMitteilungen(p);
        if (p === 'granted') {
            await meldeGeraet();
            zeigeToast('Mitteilungen eingeschaltet', 'success');
        }
    };

    const rezepte: Rezept[] = konto.rezepte.map((r) => ({
        id: r.id,
        name: r.name,
        datum: r.datum,
        settings: r.einstellungen as unknown as Record<string, unknown>,
    }));

    /** Fehler melden; 401 heißt abgemeldet (z. B. Konto gelöscht). */
    const pruefe = (r: { ok: boolean; status: number; error?: string }) => {
        if (r.status === 401) setze(null);
        else if (!r.ok) zeigeToast(r.error ?? 'Das hat nicht geklappt', 'error');
        return r.ok;
    };
    const ohneNetz = () => zeigeToast('Keine Verbindung. Ändern geht nur online.', 'error');

    const sichern = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const form = e.currentTarget;
        const name = String(new FormData(form).get('name') ?? '').trim();
        if (!name) return;
        const neu = {
            name,
            datum: new Date().toLocaleDateString('de-DE'),
            einstellungen: alsEinstellungen(w) as unknown as Einstellungen,
        };
        try {
            const r = await post('/api/rezepte', neu);
            if (!pruefe(r)) return;
            setze({ ...konto, rezepte: [...konto.rezepte, { ...neu, id: Number(r.id) }] });
            schliesseBlatt(form.closest('dialog'));
            zeigeToast(`„${name}“ gesichert`, 'success');
        } catch {
            ohneNetz();
        }
    };

    const loeschenForm = (r: Rezept): FormHTMLAttributes<HTMLFormElement> => ({
        onSubmit: async (e) => {
            e.preventDefault();
            try {
                const a = await rufe(`/api/rezepte/${r.id}`, 'DELETE');
                if (a.status !== 404 && !pruefe(a)) return;
                setze({ ...konto, rezepte: konto.rezepte.filter((x) => x.id !== r.id) });
                zeigeToast(`„${r.name}“ gelöscht`, 'success');
            } catch {
                ohneNetz();
            }
        },
    });

    const geraetecode = async () => {
        try {
            const r = await post('/api/geraetecode');
            if (!pruefe(r)) return;
            setCode({ code: String(r.code), gueltigBis: Number(r.gueltigBis) });
            oeffneBlatt('sd-geraet-sheet');
        } catch {
            ohneNetz();
        }
    };

    const abmelden = async () => {
        if (!confirm('Auf diesem Gerät abmelden? Die Rezepte bleiben im Konto.')) return;
        try {
            const endpoint = await vergissPush();
            await post('/api/abmelden', { endpoint });
        } catch {
            ohneNetz();
            return;
        }
        beendeLauf();
        setze(null);
    };

    return (
        <>
            <div id="toast" role="status" aria-live="polite" />
            <main className="container">
                <h1 className="large-title sd-titel">Sauerteig-Rechner</h1>
                <p className="muted sd-untertitel">Vollkornbrot aus Roggen, Dinkel, Weizen und Buchweizen</p>
                {offline && (
                    <p className="sd-offline" role="status">
                        Offline: Rezepte zum Ansehen, Ändern erst wieder mit Verbindung.{' '}
                        <button type="button" className="link-btn" onClick={abgleichen}>Erneut versuchen</button>
                    </p>
                )}
                <Rechner
                    w={w}
                    setW={setW}
                    rezepte={rezepte}
                    melde={zeigeToast}
                    oeffneBlatt={oeffneBlatt}
                    sichernForm={{ onSubmit: sichern }}
                    loeschenForm={loeschenForm}
                    speicherHinweis={`Wird im Konto „${konto.name}“ gespeichert.`}
                />

                <h2 className="section-title">Konto</h2>
                <div className="card stack">
                    <p className="sd-konto">Angemeldet als <strong>{konto.name}</strong></p>
                    {mitteilungen !== 'granted' && (
                        <p className="muted small">
                            {mitteilungen === 'denied'
                                ? 'Mitteilungen sind für diese Seite im Browser abgeschaltet.'
                                : mitteilungen === 'fehlt'
                                    ? 'Für Mitteilungen des Back-Timers die App zum Home-Bildschirm hinzufügen und von dort öffnen.'
                                    : 'Mitteilungen einschalten, damit dieses Gerät die Back-Timer des Kontos meldet, auch die von anderen Geräten.'}
                        </p>
                    )}
                    <div className="row">
                        {mitteilungen === 'default' && (
                            <button type="button" className="btn accent-fill" onClick={einschalten}>Mitteilungen einschalten</button>
                        )}
                        <button type="button" className="btn" onClick={geraetecode}>Weiteres Gerät anmelden</button>
                        <button type="button" className="btn danger" onClick={abmelden}>Abmelden</button>
                    </div>
                </div>
            </main>

            <dialog className="sheet" id="sd-geraet-sheet" aria-labelledby="sd-geraet-t">
                <div className="sheet-body">
                    <div className="sheet-bar">
                        <span />
                        <h2 className="sheet-title" id="sd-geraet-t">Weiteres Gerät</h2>
                        <button type="button" className="sheet-cancel sd-sheet-ok" data-close="">Fertig</button>
                    </div>
                    <p>
                        Auf dem anderen Gerät {location.host} öffnen, „Ich habe schon ein Konto“ tippen und diesen
                        Code eingeben:
                    </p>
                    {code && (
                        <>
                            <p className="ad-code">{code.code}</p>
                            <p className="muted small">
                                Gilt bis {new Date(code.gueltigBis).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })} Uhr,
                                nur einmal.
                            </p>
                        </>
                    )}
                </div>
            </dialog>
        </>
    );
}

installiereBlaetter();
createRoot(document.getElementById('app')!).render(
    <StrictMode>{location.pathname.replace(/\/$/, '') === '/admin' ? <Admin /> : <App />}</StrictMode>,
);

// Offline-Betrieb (nur im Build, im Dev-Server würde der Cache stören)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js')
        .then(installiereFernPush) // Back-Timer: Push vom Server ab „Backen beginnen“
        .catch(() => { /* App läuft auch ohne */ });
    // Offline-Kopie der Rezepte vor automatischem Löschen durch den Browser schützen
    navigator.storage?.persist?.().catch(() => { /* ignorieren */ });
}
