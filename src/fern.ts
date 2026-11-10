// Push vom eigenen Server (server/server.ts) ab „Backen beginnen“: Push-Abo dieses Geräts beim Konto anmelden und
// den Zeitplan melden. Der Server schickt die Meldungen an alle Geräte des Kontos; klappt das Melden, zeigt der
// Browser keine eigenen Mitteilungen mehr (timer.ts, „fern“).
import { setzeFernPush } from './gemeinsam/timer';
import { post } from './api';

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
        async plane(lauf) {
            const a = await abo();
            if (!a) return false;
            const r = await post('/api/timer', { abo: a.toJSON(), lauf });
            return r.ok;
        },
        async stoppe() {
            await post('/api/timer/stop');
        },
    });
}
