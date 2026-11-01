// Toast und Blätter wie in der Haushalt-App (gleiche Klassen aus src/gemeinsam/haushalt.css).

let toastTimer: number | undefined;

export function zeigeToast(text: string, art?: 'success' | 'error'): void {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = text;
    t.className = art === 'error' ? 'toast-error' : art === 'success' ? 'toast-success' : '';
    t.setAttribute('role', art === 'error' ? 'alert' : 'status');
    clearTimeout(toastTimer);
    t.classList.add('show');
    toastTimer = window.setTimeout(() => t.classList.remove('show'), 3500);
}

export function oeffneBlatt(id: string): void {
    const d = document.getElementById(id) as HTMLDialogElement | null;
    if (d && !d.open) d.showModal();
}

/** Schließen mit der Animation der Haushalt-App (Klasse „closing“). */
export function schliesseBlatt(d: HTMLDialogElement | null): void {
    if (!d || !d.open || d.classList.contains('closing')) return;
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
        d.close();
        return;
    }
    const fertig = () => {
        d.classList.remove('closing');
        if (d.open) d.close();
    };
    d.classList.add('closing');
    d.addEventListener('animationend', fertig, { once: true });
    window.setTimeout(fertig, 400);
}

/** Abbrechen-Knöpfe (data-close), Tipp auf den Hintergrund und Escape schließen Blätter. */
export function installiereBlaetter(): void {
    document.addEventListener('click', (e) => {
        const ziel = e.target as HTMLElement;
        const knopf = ziel.closest('[data-close]');
        if (knopf) schliesseBlatt(knopf.closest('dialog'));
        else if (ziel.tagName === 'DIALOG') schliesseBlatt(ziel as HTMLDialogElement);
    });
    document.addEventListener('cancel', (e) => {
        const d = e.target as HTMLElement;
        if (d.tagName === 'DIALOG') {
            e.preventDefault();
            schliesseBlatt(d as HTMLDialogElement);
        }
    }, true);
}
