// Konto in den Einstellungen: Einladungscode einlösen (neues Konto, Name frei wählbar) oder dieses Gerät mit einem
// Gerätecode an ein bestehendes Konto hängen. Die Daten bleiben dabei auf dem Gerät; ab zwei Geräten gleichen sie
// sich ab (abgleich.ts).
import { useState, type FormEvent } from 'react';
import { Offline, post } from './api';
import { entpacke, merkeSchluessel, neuerSchluessel, zerlegeCode } from './schluessel';

export function Zugang({ angemeldet }: { angemeldet: (name: string) => void }) {
    const suche = new URLSearchParams(location.search);
    const [art, setArt] = useState<'neu' | 'geraet'>(() => (suche.has('einladung') ? 'neu' : 'geraet'));
    const [fehler, setFehler] = useState('');
    const [busy, setBusy] = useState(false);

    const absenden = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        setBusy(true);
        setFehler('');
        try {
            const eingabe = String(f.get('code') ?? '');
            const teile = zerlegeCode(eingabe);
            const r = await post(art === 'neu' ? '/api/registrieren' : '/api/anmelden', {
                code: art === 'neu' ? eingabe : teile.server,
                name: String(f.get('name') ?? ''),
            });
            if (!r.ok) {
                setFehler(r.error ?? 'Das hat nicht geklappt');
                return;
            }
            // Neues Konto: eigener Schlüssel. Weiteres Gerät: Schlüssel aus dem Gerätecode (ohne Geheimnis, z. B.
            // Code vom Admin: später nachholen).
            if (art === 'neu') merkeSchluessel(neuerSchluessel());
            else merkeSchluessel(typeof r.schluessel === 'string' && teile.geheim ? await entpacke(r.schluessel, teile.geheim) : null);
            history.replaceState(null, '', '/');
            angemeldet(String(r.name));
        } catch (err) {
            setFehler(err instanceof Offline ? 'Keine Verbindung. Zum Verknüpfen braucht es Internet.' : 'Das hat nicht geklappt');
        } finally {
            setBusy(false);
        }
    };

    return (
        <form className="stack" onSubmit={absenden} key={art}>
            {art === 'geraet' ? (
                <>
                    <p className="muted small">
                        Den Gerätecode zeigt ein Gerät, das schon im Konto ist („Weiteres Gerät verknüpfen“). Er gilt
                        15 Minuten.
                    </p>
                    <div>
                        <label className="field" htmlFor="zg-code">Gerätecode</label>
                        <input id="zg-code" name="code" type="text" required autoComplete="one-time-code"
                            autoCapitalize="characters" spellCheck={false} placeholder="XXXX-XXXX-XXXX-XXXX" />
                    </div>
                </>
            ) : (
                <>
                    <p className="muted small">Mit einem Einladungscode bekommst du ein eigenes Konto.</p>
                    <div>
                        <label className="field" htmlFor="zg-code">Einladungscode</label>
                        <input id="zg-code" name="code" type="text" required autoComplete="one-time-code"
                            autoCapitalize="characters" spellCheck={false} placeholder="XXXX-XXXX-XXXX"
                            defaultValue={suche.get('einladung') ?? ''} />
                    </div>
                    <div>
                        <label className="field" htmlFor="zg-name">Dein Name</label>
                        <input id="zg-name" name="name" type="text" required maxLength={40} autoComplete="nickname" />
                    </div>
                </>
            )}
            {fehler && <p className="zg-fehler" role="alert">{fehler}</p>}
            <button type="submit" className="btn accent-fill" disabled={busy}>
                {art === 'neu' ? 'Konto erstellen' : 'Verknüpfen'}
            </button>
            <button type="button" className="link-btn zg-wechsel" onClick={() => { setArt(art === 'neu' ? 'geraet' : 'neu'); setFehler(''); }}>
                {art === 'neu' ? 'Ich habe schon ein Konto' : 'Ich habe einen Einladungscode'}
            </button>
        </form>
    );
}
