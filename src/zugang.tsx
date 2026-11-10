// Erster Start ohne Konto: Einladungscode einlösen (neues Konto, Name frei wählbar) oder ein weiteres Gerät mit
// einem Gerätecode an ein bestehendes Konto anmelden. Rezepte aus der Zeit vor den Konten wandern dabei mit.
import { useState, type FormEvent } from 'react';
import { Offline, post } from './api';
import { altRezepte, vergissAltRezepte } from './speicher';

export function Zugang({ angemeldet }: { angemeldet: (name: string) => void }) {
    const [art, setArt] = useState<'neu' | 'geraet'>(() =>
        new URLSearchParams(location.search).has('geraet') ? 'geraet' : 'neu',
    );
    const [fehler, setFehler] = useState('');
    const [busy, setBusy] = useState(false);
    const alt = altRezepte();

    const absenden = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        setBusy(true);
        setFehler('');
        try {
            const r = await post(art === 'neu' ? '/api/registrieren' : '/api/anmelden', {
                code: String(f.get('code') ?? ''),
                name: String(f.get('name') ?? ''),
                rezepte: alt,
            });
            if (!r.ok) {
                setFehler(r.error ?? 'Das hat nicht geklappt');
                return;
            }
            if (alt.length) vergissAltRezepte();
            history.replaceState(null, '', '/');
            angemeldet(String(r.name));
        } catch (err) {
            setFehler(err instanceof Offline ? 'Keine Verbindung. Zum Anmelden braucht es Internet.' : 'Das hat nicht geklappt');
        } finally {
            setBusy(false);
        }
    };

    return (
        <main className="container">
            <h1 className="large-title sd-titel">Sauerteig-Rechner</h1>
            <p className="muted sd-untertitel">Vollkornbrot aus Roggen, Dinkel, Weizen und Buchweizen</p>
            <form className="card narrow stack" onSubmit={absenden} key={art}>
                {art === 'neu' ? (
                    <>
                        <h2>Konto erstellen</h2>
                        <p className="muted">Mit deinem Einladungscode bekommst du ein eigenes Konto für deine Rezepte.</p>
                        <div>
                            <label className="field" htmlFor="zg-code">Einladungscode</label>
                            <input id="zg-code" name="code" type="text" required autoComplete="one-time-code"
                                autoCapitalize="characters" spellCheck={false} placeholder="XXXX-XXXX-XXXX"
                                defaultValue={new URLSearchParams(location.search).get('einladung') ?? ''} />
                        </div>
                        <div>
                            <label className="field" htmlFor="zg-name">Dein Name</label>
                            <input id="zg-name" name="name" type="text" required maxLength={40} autoComplete="nickname" />
                        </div>
                    </>
                ) : (
                    <>
                        <h2>Gerät anmelden</h2>
                        <p className="muted">
                            Den Gerätecode zeigt die App auf einem Gerät, das schon angemeldet ist („Weiteres Gerät
                            anmelden“). Er gilt 15 Minuten.
                        </p>
                        <div>
                            <label className="field" htmlFor="zg-code">Gerätecode</label>
                            <input id="zg-code" name="code" type="text" required autoComplete="one-time-code"
                                autoCapitalize="characters" spellCheck={false} placeholder="XXXX-XXXX" />
                        </div>
                    </>
                )}
                {alt.length > 0 && (
                    <p className="muted small">
                        {alt.length === 1 ? 'Ein gesichertes Rezept' : `${alt.length} gesicherte Rezepte`} aus diesem
                        Browser {alt.length === 1 ? 'kommt' : 'kommen'} mit ins Konto.
                    </p>
                )}
                {fehler && <p className="zg-fehler" role="alert">{fehler}</p>}
                <button type="submit" className="btn btn-big accent-fill" disabled={busy}>
                    {art === 'neu' ? 'Konto erstellen' : 'Anmelden'}
                </button>
                <button type="button" className="link-btn zg-wechsel" onClick={() => { setArt(art === 'neu' ? 'geraet' : 'neu'); setFehler(''); }}>
                    {art === 'neu' ? 'Ich habe schon ein Konto' : 'Ich habe einen Einladungscode'}
                </button>
            </form>
        </main>
    );
}
