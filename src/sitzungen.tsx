// Verknüpfte Geräte des eigenen Kontos (Einstellungen): ansehen und einzelne entfernen, z. B. ein verlorenes oder
// verkauftes Gerät. Dieses Gerät trennt sich über „Dieses Gerät trennen“, nicht hier. Für alle Konten: /admin.
import { useState } from 'react';
import { Offline, rufe } from './api';
import { zeigeToast } from './ui';

interface Sitzung { id: number; geraet: string; erstellt: number; zuletzt: number; push: number; diese: number }

const datum = (ms: number) =>
    new Date(ms).toLocaleString('de-DE', { day: 'numeric', month: 'numeric', year: '2-digit', hour: '2-digit', minute: '2-digit' });

/** `geaendert`: nach dem Entfernen (Anzahl der Geräte neu holen). */
export function Sitzungen({ geaendert }: { geaendert: () => void }) {
    const [liste, setListe] = useState<Sitzung[] | null>(null);
    const [busy, setBusy] = useState(false);

    const laden = async () => {
        setBusy(true);
        try {
            const r = await rufe('/api/sitzungen');
            if (!r.ok) return zeigeToast(r.error ?? 'Das hat nicht geklappt', 'error');
            setListe(r.sitzungen as Sitzung[]);
        } catch (e) {
            zeigeToast(e instanceof Offline ? 'Keine Verbindung' : 'Das hat nicht geklappt', 'error');
        } finally {
            setBusy(false);
        }
    };

    const entfernen = async (s: Sitzung) => {
        const name = s.geraet || 'Unbekanntes Gerät';
        if (!confirm(`„${name}“ entfernen? Das Gerät gleicht sich dann nicht mehr ab und muss neu verknüpft werden.`)) return;
        setBusy(true);
        try {
            const r = await rufe(`/api/sitzungen/${s.id}`, 'DELETE');
            if (!r.ok) zeigeToast(r.error ?? 'Das hat nicht geklappt', 'error');
            else zeigeToast(`„${name}“ entfernt`, 'success');
        } catch (e) {
            zeigeToast(e instanceof Offline ? 'Keine Verbindung' : 'Das hat nicht geklappt', 'error');
        } finally {
            setBusy(false);
        }
        geaendert();
        await laden();
    };

    if (!liste)
        return (
            <button type="button" className="btn" onClick={laden} disabled={busy}>Verknüpfte Geräte anzeigen</button>
        );

    return (
        <ul className="list">
            {liste.map((s) => (
                <li key={s.id} className="list-item">
                    <span>
                        {s.geraet || 'Unbekanntes Gerät'}
                        {s.diese ? <strong> · dieses Gerät</strong> : null}
                        <br />
                        <span className="muted small">seit {datum(s.erstellt)} · zuletzt {datum(s.zuletzt)}</span>
                    </span>
                    {!s.diese && (
                        <span className="list-right">
                            <button type="button" className="btn sm danger" onClick={() => entfernen(s)} disabled={busy}>
                                Entfernen
                            </button>
                        </span>
                    )}
                </li>
            ))}
        </ul>
    );
}
