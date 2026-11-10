// Admin-Seite (/admin): Einladungscodes erzeugen, Konten verwalten. Passwort = Add-on-Einstellung admin_password.
import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Offline, post, rufe, type Antwort } from './api';
import { zeigeToast } from './ui';

interface Einladung { id: number; notiz: string; erstellt: number; gueltigBis: number }
interface Konto { id: number; name: string; erstellt: number; rezepte: number; geraete: number; zuletzt: number | null }
interface Stand { einladungen: Einladung[]; konten: Konto[]; backlaeufe: number }
interface Neu { code: string; gueltigBis: number; titel: string; link?: string }

const datum = (ms: number) =>
    new Date(ms).toLocaleString('de-DE', { day: 'numeric', month: 'numeric', year: '2-digit', hour: '2-digit', minute: '2-digit' });

export function Admin() {
    const [stand, setStand] = useState<Stand | null>(null);
    const [angemeldet, setAngemeldet] = useState<boolean | null>(null);
    const [fehler, setFehler] = useState('');
    const [neu, setNeu] = useState<Neu | null>(null);

    const laden = useCallback(async () => {
        try {
            const r = await rufe('/api/admin/uebersicht');
            if (r.status === 401) return setAngemeldet(false);
            if (!r.ok) return setFehler(r.error ?? 'Fehler');
            setAngemeldet(true);
            setStand(r as unknown as Stand);
        } catch (e) {
            setFehler(e instanceof Offline ? 'Keine Verbindung' : 'Fehler');
        }
    }, []);
    useEffect(() => { void laden(); }, [laden]);

    const aktion = async (f: () => Promise<Antwort>, erfolg?: string): Promise<Antwort | null> => {
        try {
            const r = await f();
            if (!r.ok) zeigeToast(r.error ?? 'Fehler', 'error');
            else if (erfolg) zeigeToast(erfolg, 'success');
            await laden();
            return r;
        } catch {
            zeigeToast('Keine Verbindung', 'error');
            return null;
        }
    };

    const anmelden = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const passwort = String(new FormData(e.currentTarget).get('passwort') ?? '');
        try {
            const r = await post('/api/admin/anmelden', { passwort });
            if (!r.ok) return setFehler(r.error ?? 'Fehler');
            setFehler('');
            await laden();
        } catch {
            setFehler('Keine Verbindung');
        }
    };

    const einladen = async (e: FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        const form = e.currentTarget;
        const notiz = String(new FormData(form).get('notiz') ?? '');
        const r = await aktion(() => post('/api/admin/einladungen', { notiz }));
        if (r?.ok) {
            const code = String(r.code);
            setNeu({
                code,
                gueltigBis: Number(r.gueltigBis),
                titel: notiz ? `Einladung für ${notiz}` : 'Neue Einladung',
                link: `${location.origin}/?einladung=${encodeURIComponent(code)}`,
            });
            form.reset();
        }
    };

    const geraetecode = async (k: Konto) => {
        const r = await aktion(() => post(`/api/admin/konten/${k.id}/geraetecode`));
        if (r?.ok) setNeu({ code: String(r.code), gueltigBis: Number(r.gueltigBis), titel: `Gerätecode für ${k.name}` });
    };

    const kopiere = async (text: string) => {
        try {
            await navigator.clipboard.writeText(text);
            zeigeToast('Kopiert', 'success');
        } catch {
            zeigeToast('Kopieren nicht möglich', 'error');
        }
    };

    return (
        <>
            <div id="toast" role="status" aria-live="polite" />
            <main className="container">
                <h1 className="large-title sd-titel">Sauerteig · Admin</h1>
                <p className="muted sd-untertitel"><a href="/">Zur App</a></p>

                {angemeldet === false && (
                    <form className="card narrow stack" onSubmit={anmelden}>
                        <h2>Anmelden</h2>
                        <div>
                            <label className="field" htmlFor="ad-pw">Admin-Passwort</label>
                            <input id="ad-pw" name="passwort" type="password" required autoComplete="current-password"
                                className="ad-pw" />
                        </div>
                        {fehler && <p className="zg-fehler" role="alert">{fehler}</p>}
                        <button type="submit" className="btn btn-big accent-fill">Anmelden</button>
                    </form>
                )}
                {angemeldet === null && fehler && <p className="zg-fehler">{fehler}</p>}

                {angemeldet && stand && (
                    <>
                        {neu && (
                            <div className="card stack ad-neu">
                                <h2>{neu.titel}</h2>
                                <p className="ad-code">{neu.code}</p>
                                <p className="muted small">Gültig bis {datum(neu.gueltigBis)}, nur einmal verwendbar. Wird nicht noch einmal angezeigt.</p>
                                <div className="row">
                                    <button type="button" className="btn" onClick={() => kopiere(neu.code)}>Code kopieren</button>
                                    {neu.link && <button type="button" className="btn" onClick={() => kopiere(neu.link!)}>Link kopieren</button>}
                                    <button type="button" className="btn" onClick={() => setNeu(null)}>Fertig</button>
                                </div>
                            </div>
                        )}

                        <h2 className="section-title">Einladen</h2>
                        <form className="card stack" onSubmit={einladen}>
                            <div>
                                <label className="field" htmlFor="ad-notiz">Für wen? (nur für dich)</label>
                                <input id="ad-notiz" name="notiz" type="text" maxLength={80} autoComplete="off" />
                            </div>
                            <button type="submit" className="btn accent-fill">Einladungscode erzeugen</button>
                        </form>

                        {stand.einladungen.length > 0 && (
                            <>
                                <h2 className="section-title">Offene Einladungen <span className="count">{stand.einladungen.length}</span></h2>
                                <ul className="list">
                                    {stand.einladungen.map((e) => (
                                        <li key={e.id} className="list-item">
                                            <span>
                                                {e.notiz || 'Ohne Notiz'}
                                                <br />
                                                <span className="muted small">bis {datum(e.gueltigBis)}</span>
                                            </span>
                                            <span className="list-right">
                                                <button type="button" className="btn sm danger"
                                                    onClick={() => aktion(() => rufe(`/api/admin/einladungen/${e.id}`, 'DELETE'), 'Einladung gelöscht')}>
                                                    Löschen
                                                </button>
                                            </span>
                                        </li>
                                    ))}
                                </ul>
                            </>
                        )}

                        <h2 className="section-title">Konten <span className="count">{stand.konten.length}</span></h2>
                        {stand.konten.length === 0 && <p className="empty">Noch keine Konten</p>}
                        <ul className="list">
                            {stand.konten.map((k) => (
                                <li key={k.id} className="list-item">
                                    <span>
                                        <strong>{k.name}</strong>
                                        <br />
                                        <span className="muted small">
                                            {k.rezepte} Rezepte · {k.geraete} Geräte
                                            {k.zuletzt ? ` · zuletzt ${datum(k.zuletzt)}` : ''}
                                        </span>
                                    </span>
                                    <span className="list-right">
                                        <button type="button" className="btn sm" onClick={() => geraetecode(k)}>Gerätecode</button>
                                        <button type="button" className="btn sm danger" onClick={() => {
                                            if (confirm(`Konto „${k.name}“ mit allen Rezepten löschen?`))
                                                void aktion(() => rufe(`/api/admin/konten/${k.id}`, 'DELETE'), 'Konto gelöscht');
                                        }}>
                                            Löschen
                                        </button>
                                    </span>
                                </li>
                            ))}
                        </ul>
                        <p className="muted small ad-fuss">Laufende Back-Timer: {stand.backlaeufe}</p>
                        <button type="button" className="btn" onClick={() => aktion(() => post('/api/admin/abmelden')).then(() => setAngemeldet(false))}>
                            Admin abmelden
                        </button>
                    </>
                )}
            </main>
        </>
    );
}
