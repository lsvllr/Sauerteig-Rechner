// Eigenständiger Sauerteig-Rechner: Oberfläche und Design aus der Haushalt-App (src/gemeinsam, übernommen mit
// scripts/sync-haushalt.sh), Rezepte nur in diesem Browser (speicher.ts, gleiches Format wie bisher). Der Server
// (server/server.ts) liefert die App aus und schickt die Erinnerungen des Back-Timers per Push (fern.ts).
import { StrictMode, useState, type FormEvent, type FormHTMLAttributes } from 'react';
import { createRoot } from 'react-dom/client';
import './gemeinsam/haushalt.css';
import './app.css';
import { Rechner, START, alsEinstellungen, type Rezept, type Werte } from './gemeinsam/Oberflaeche';
import { lese, schreibe, type Einstellungen, type GespeichertesRezept } from './speicher';
import { installiereFernPush } from './fern';
import { installiereBlaetter, oeffneBlatt, schliesseBlatt, zeigeToast } from './ui';

function App() {
    const [w, setW] = useState<Werte>(START);
    const [gespeichert, setGespeichert] = useState<GespeichertesRezept[]>(lese);

    const rezepte: Rezept[] = gespeichert.map((r, i) => ({
        id: i,
        name: r.name,
        datum: r.datum,
        settings: r.einstellungen as unknown as Record<string, unknown>,
    }));

    const merke = (neu: GespeichertesRezept[]) => {
        const ok = schreibe(neu);
        if (ok) setGespeichert(neu);
        return ok;
    };

    const sichern = (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const form = e.currentTarget;
        const name = String(new FormData(form).get('name') ?? '').trim();
        if (!name) return;
        const ok = merke([...gespeichert, {
            name,
            datum: new Date().toLocaleDateString('de-DE'),
            einstellungen: alsEinstellungen(w) as unknown as Einstellungen,
        }]);
        schliesseBlatt(form.closest('dialog'));
        zeigeToast(ok ? `„${name}“ gesichert` : 'Sichern nicht möglich', ok ? 'success' : 'error');
    };

    const loeschenForm = (r: Rezept): FormHTMLAttributes<HTMLFormElement> => ({
        onSubmit: (e) => {
            e.preventDefault();
            if (merke(gespeichert.filter((_, i) => i !== r.id))) zeigeToast(`„${r.name}“ gelöscht`, 'success');
        },
    });

    return (
        <>
            <div id="toast" role="status" aria-live="polite" />
            <main className="container">
                <h1 className="large-title sd-titel">Sauerteig-Rechner</h1>
                <p className="muted sd-untertitel">Vollkornbrot aus Roggen, Dinkel, Weizen und Buchweizen</p>
                <Rechner
                    w={w}
                    setW={setW}
                    rezepte={rezepte}
                    melde={zeigeToast}
                    oeffneBlatt={oeffneBlatt}
                    sichernForm={{ onSubmit: sichern }}
                    loeschenForm={loeschenForm}
                    speicherHinweis="Wird nur in diesem Browser gespeichert."
                />
            </main>
        </>
    );
}

installiereBlaetter();
createRoot(document.getElementById('app')!).render(<StrictMode><App /></StrictMode>);

// Offline-Betrieb (nur im Build, im Dev-Server würde der Cache stören)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js')
        .then(installiereFernPush) // Back-Timer: Push vom Server ab „Backen beginnen“
        .catch(() => { /* App läuft auch ohne */ });
    // Gespeicherte Rezepte vor automatischem Löschen durch den Browser schützen
    navigator.storage?.persist?.().catch(() => { /* ignorieren */ });
}
