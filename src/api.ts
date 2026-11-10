// Aufrufe an den eigenen Server (server/server.ts). Antwortet der Server nicht (offline), wirft ``Offline``;
// sonst kommt die Antwort mit ``ok`` und ggf. ``error`` zurück.

export class Offline extends Error {}

export interface Antwort {
    ok: boolean;
    status: number;
    error?: string;
    [k: string]: unknown;
}

export async function rufe(pfad: string, methode = 'GET', daten?: unknown): Promise<Antwort> {
    let r: Response;
    try {
        r = await fetch(pfad, {
            method: methode,
            credentials: 'same-origin',
            headers: daten === undefined ? {} : { 'Content-Type': 'application/json' },
            body: daten === undefined ? undefined : JSON.stringify(daten),
        });
    } catch {
        throw new Offline('Keine Verbindung zum Server');
    }
    let d: Record<string, unknown> = {};
    try {
        d = await r.json();
    } catch {
        /* keine JSON-Antwort */
    }
    return { ...d, ok: r.ok && d.ok !== false, status: r.status, error: typeof d.error === 'string' ? d.error : undefined };
}

export const post = (pfad: string, daten: unknown = {}) => rufe(pfad, 'POST', daten);
