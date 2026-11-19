// Push vom eigenen Server (server/server.ts) ab „Backen beginnen“, nur mit Konto: Push-Abo dieses Geräts und den
// Zeitplan melden (/api/timer). Der Server schickt die Meldungen an alle Geräte des Kontos und plant neu, wenn der
// Timer im Abgleich anders ankommt. Hat dieses Gerät ein Abo, zeigt der Browser keine eigenen Mitteilungen
// (timer.ts, „fern“). Ohne Konto meldet der Browser selbst, solange die Seite offen ist.
import { setzeFernPush } from './gemeinsam/timer';
import { post } from './api';
import { kern } from './laufKern';
import { leseKonto } from './speicher';

const b64 = (s: string) => {
    const roh = atob((s + '='.repeat((4 - (s.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(roh, (c) => c.charCodeAt(0));
};

const gleich = (a: ArrayBuffer | null | undefined, b: Uint8Array) =>
    !!a && a.byteLength === b.length && new Uint8Array(a).every((x, i) => x === b[i]);

/** Abo für den aktuellen Schlüssel des Servers; ein Abo mit altem Schlüssel wird ersetzt. */
async function abo(): Promise<PushSubscription | null> {
    if (!('serviceWorker' in navigator) || typeof Notification === 'undefined') return null;
    if (Notification.permission !== 'granted') return null;
    const reg = await navigator.serviceWorker.getRegistration();
    if (!reg || !('pushManager' in reg)) return null;
    const { key } = (await (await fetch('/api/push-key')).json()) as { key: string };
    const schluessel = b64(key);
    let a = await reg.pushManager.getSubscription();
    if (a && !gleich(a.options.applicationServerKey, schluessel)) {
        await a.unsubscribe();
        a = null;
    }
    return a ?? reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: schluessel });
}

/** Dieses Gerät beim Konto anmelden, damit es auch Back-Timer anderer Geräte des Kontos meldet. */
export async function meldeGeraet(): Promise<void> {
    try {
        const a = await abo();
        if (a) await post('/api/push-abo', { abo: a.toJSON() });
    } catch {
        /* ohne Push geht es auch */
    }
}

/** Beim Abmelden: Endpoint dieses Geräts, damit der Server es vom Konto löst. */
export async function vergissPush(): Promise<string | undefined> {
    const reg = await navigator.serviceWorker?.getRegistration();
    const a = await reg?.pushManager?.getSubscription();
    return a?.endpoint;
}

export function installiereFernPush(): void {
    setzeFernPush({
        async plane(l) {
            if (!leseKonto()) return false;
            const a = await abo();
            if (!a) return false;
            const r = await post('/api/timer', { abo: a.toJSON(), lauf: kern(l) });
            return r.ok;
        },
        async stoppe() {
            if (leseKonto()) await post('/api/timer/stop');
        },
    });
}
