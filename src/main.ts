import './style.css';
import { SORTEN, mehlMischungen, tipps, type Anteile, type Sorte } from './daten';
import { berechneOptimaleHydration, berechneRezept, hm, normalisiere } from './rechner';
import { lese, loescheAlle, schreibe, type GespeichertesRezept } from './speicher';

function $<T extends HTMLElement = HTMLElement>(id: string): T {
    const e = document.getElementById(id);
    if (!e) throw new Error(`Element #${id} fehlt`);
    return e as T;
}

const setText = (id: string, v: string | number) => { $(id).textContent = String(v); };
const zeige = (id: string, sichtbar: boolean, display = 'flex') => { $(id).style.display = sichtbar ? display : 'none'; };

const HAKEN_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>';
const INFO_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 8v5"/><path d="M12 16.5v.01"/></svg>';
const PAPIERKORB_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M9 7V4.5h6V7"/><path d="M6 7l1 13h10l1-13"/></svg>';

$('tipps-liste').innerHTML = tipps.map(t => `<div class="row">${HAKEN_SVG}<span>${t}</span></div>`).join('');

const el = {
    anstellgut: $<HTMLInputElement>('anstellgut'),
    anstellgutWert: $('anstellgut-wert'),
    sauerteigTemp: $<HTMLInputElement>('sauerteig-temp'),
    sauerteigTempWert: $('sauerteig-temp-wert'),
    gareTemp: $<HTMLInputElement>('gare-temp'),
    gareTempWert: $('gare-temp-wert'),
    brotGroesse: $<HTMLInputElement>('brot-groesse'),
    brotGroesseWert: $('brot-groesse-wert'),
    hydrationSlider: $<HTMLInputElement>('hydration-slider'),
    hydrationWert: $('hydration-wert'),
    hydrationHinweis: $('hydration-hinweis'),
    teigTeilen: $<HTMLInputElement>('teig-teilen'),
    mehlMischung: $<HTMLSelectElement>('mehl-mischung'),
    customControls: $('custom-controls'),
    summeAnzeige: $('summe-anzeige'),
    normalizeBtn: $('normalize-btn')
};

const custom = Object.fromEntries(SORTEN.map(([k]) => [k, {
    input: $<HTMLInputElement>(`custom-${k}`),
    wert: $(`custom-${k}-wert`)
}])) as Record<Sorte, { input: HTMLInputElement; wert: HTMLElement }>;

const zahl = (i: HTMLInputElement) => parseInt(i.value);

function setzeCustom(k: Sorte, v: string | number) {
    custom[k].input.value = String(v);
    custom[k].wert.textContent = custom[k].input.value;
}

// Slider mit Wertanzeige
([
    [el.anstellgut, el.anstellgutWert],
    [el.sauerteigTemp, el.sauerteigTempWert],
    [el.gareTemp, el.gareTempWert],
    [el.brotGroesse, el.brotGroesseWert]
] as const).forEach(([input, wert]) =>
    input.addEventListener('input', () => { wert.textContent = input.value; aktualisiere(); }));

el.teigTeilen.addEventListener('change', aktualisiere);
el.hydrationSlider.addEventListener('input', () => {
    el.hydrationWert.textContent = el.hydrationSlider.value;
    markiereHydrationAenderung();
    aktualisiere();
});

el.mehlMischung.addEventListener('change', () => {
    el.customControls.style.display = el.mehlMischung.value === 'custom' ? 'block' : 'none';
    if (el.mehlMischung.value !== 'custom') aktualisiereGewaehlteMischung();
    setzeOptimaleHydration();
    aktualisiere();
});

SORTEN.forEach(([k]) => custom[k].input.addEventListener('input', () => {
    custom[k].wert.textContent = custom[k].input.value;
    aktualisiereCustomSumme();
    setzeOptimaleHydration();
    aktualisiere();
}));
el.normalizeBtn.addEventListener('click', normalisiereCustomWerte);

$('save-btn').addEventListener('click', speichereRezept);
$('load-btn').addEventListener('click', ladeRezept);
$('print-btn').addEventListener('click', () => window.print());

// --- UI-Helfer ---
function fuelleSlider() {
    document.querySelectorAll<HTMLInputElement>('.slider').forEach(s => {
        const p = (Number(s.value) - Number(s.min)) / (Number(s.max) - Number(s.min)) * 100;
        s.style.setProperty('--p', p + '%');
    });
}

function setzeHydrationBadge(empfohlen: boolean) {
    el.hydrationHinweis.textContent = empfohlen ? 'Empfohlen' : 'Angepasst';
    el.hydrationHinweis.className = 'badge ' + (empfohlen ? 'ok' : 'warn');
}

function zeichneAnteile(anteile: Anteile) {
    const summe = SORTEN.reduce((a, [k]) => a + (anteile[k] || 0), 0) || 1;
    $('mehl-bar').innerHTML = SORTEN
        .filter(([k]) => anteile[k] > 0)
        .map(([k]) => `<span style="flex-basis:${anteile[k] / summe * 100}%;background:var(--${k})"></span>`).join('');
    $('mehl-anteile').innerHTML = SORTEN.map(([k, n]) =>
        `<div class="${anteile[k] > 0 ? '' : 'zero'}"><span class="dot" style="background:var(--${k})"></span>${n} <b>${anteile[k]}%</b></div>`
    ).join('');
    if (el.mehlMischung.value === 'custom') {
        setText('mischung-name', 'Eigene Mischung');
        setText('mischung-beschreibung', 'Anteile frei wählbar');
        $('mischung-eigenschaften').innerHTML = '';
    }
}

let toastTimer: number | undefined;
function zeigeToast(text: string) {
    setText('toast-text', text);
    const t = $('toast');
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => t.classList.remove('show'), 1800);
}

document.querySelectorAll<HTMLElement>('dialog [data-close]').forEach(b =>
    b.addEventListener('click', () => b.closest('dialog')?.close()));
document.querySelectorAll<HTMLDialogElement>('dialog.sheet').forEach(d =>
    d.addEventListener('click', e => { if (e.target === d) d.close(); }));

const navbar = $('navbar');
new IntersectionObserver(([e]) => navbar.classList.toggle('scrolled', !e.isIntersecting),
    { rootMargin: '-44px 0px 0px 0px' }).observe(document.querySelector('.large-title h1')!);

// --- Mischung & Hydration ---
function getMehlAnteile(): Anteile {
    if (el.mehlMischung.value === 'custom') {
        return Object.fromEntries(SORTEN.map(([k]) => [k, zahl(custom[k].input)])) as Anteile;
    }
    return mehlMischungen[el.mehlMischung.value];
}

function setzeOptimaleHydration() {
    const optimaleHydration = berechneOptimaleHydration(getMehlAnteile());
    el.hydrationSlider.value = String(optimaleHydration);
    el.hydrationWert.textContent = String(optimaleHydration);
    el.hydrationHinweis.style.display = 'inline-block';
    setzeHydrationBadge(true);
}

function markiereHydrationAenderung() {
    const optimaleHydration = berechneOptimaleHydration(getMehlAnteile());
    setzeHydrationBadge(Math.abs(zahl(el.hydrationSlider) - optimaleHydration) <= 2);
}

function aktualisiereGewaehlteMischung() {
    const mischung = mehlMischungen[el.mehlMischung.value];
    if (mischung) {
        setText('mischung-name', mischung.name);
        setText('mischung-beschreibung', mischung.beschreibung);
        $('mischung-eigenschaften').innerHTML = '<strong>Eigenschaften:</strong> ' + mischung.eigenschaften;
        zeichneAnteile(mischung);
    }
}

function aktualisiereCustomSumme() {
    const summe = SORTEN.reduce((a, [k]) => a + zahl(custom[k].input), 0);
    el.summeAnzeige.textContent = `Summe: ${summe} %`;
    el.summeAnzeige.className = summe !== 100 ? 'sum-bad' : 'sum-ok';
    el.normalizeBtn.style.display = summe !== 100 ? 'inline-block' : 'none';
}

function normalisiereCustomWerte() {
    const norm = normalisiere(getMehlAnteile());
    if (!norm) {
        zeigeToast('Mindestens ein Mehl muss über 0 % liegen');
        return;
    }
    SORTEN.forEach(([k]) => setzeCustom(k, norm[k]));
    aktualisiereCustomSumme();
    aktualisiere();
}

// --- Rezept anzeigen ---
function aktualisiere() {
    const anteile = getMehlAnteile();
    const r = berechneRezept({
        anstellgut: zahl(el.anstellgut),
        sauerteigTemp: zahl(el.sauerteigTemp),
        gareTemp: zahl(el.gareTemp),
        brotGroesse: zahl(el.brotGroesse),
        hydration: zahl(el.hydrationSlider),
        anteile,
        teigTeilen: el.teigTeilen.checked
    });

    $('dampf-hinweis').innerHTML = el.teigTeilen.checked
        ? "10 Min bei 250°C <strong>mit Dampf</strong> (2 Brote → engere Dampfphase)"
        : "15 Min bei 250°C <strong>mit Dampf</strong> (Schüssel über Brot oder Schwaden)";

    setText('stueckgare-anzeige', r.stueckgare);
    setText('stueckgare-zeitplan', r.stueckgare);
    setText('anstellgut-menge', r.anstellgut);
    setText('sauerteig-mehl', r.sauerteigMehl);
    setText('sauerteig-wasser', r.sauerteigWasser);
    setText('sauerteig-gesamt', r.sauerteigGesamt);
    setText('sauerteig-benoetigt', r.sauerteigGesamt);
    setText('hauptteig-sauerteig', r.sauerteigGesamt);
    SORTEN.forEach(([k]) => {
        setText(`hauptteig-${k}`, r.mehl[k]);
        zeige(`${k}-zeile`, r.mehl[k] > 0);
    });
    setText('hauptteig-wasser', r.hauptteigWasser);
    setText('hauptteig-salz', r.salz);
    setText('hauptteig-kuemmel', r.kuemmel.replace('.', ','));
    setText('gesamt-mehl', r.gesamtMehl);
    setText('hydration', r.hydration);
    el.brotGroesseWert.textContent = String(r.teiggewicht);
    setText('temp-anzeige', el.sauerteigTemp.value);
    setText('zeit-anzeige', r.zeitplan.sauerteigZeit);
    setText('sauerteig-zeit', r.zeitplan.sauerteigZeit);
    setText('erste-gare-zeit', r.ersteGare);
    setText('erste-gare-anzeige', r.ersteGare);
    setText('back-zeit', r.backZeit);
    setText('back-zeit-anzeige', r.backZeit + " bei 220°C ohne Dampf");

    setText('krume-beschreibung', r.eigenschaften.krume);
    setText('geschmack-beschreibung', r.eigenschaften.geschmack);
    setText('haltbarkeit-beschreibung', r.eigenschaften.haltbarkeit);

    $('temp-hinweise').innerHTML = r.tempHinweis ? `${INFO_SVG}<p>${r.tempHinweis}</p>` : '';

    setText('autolyse-zeit', r.autolyseZeit);
    setText('autolyse-titel', r.mitAutolyse ? 'Autolyse (Mehl + Wasser)' : 'Zutaten (alles zusammen mischen)');
    zeige('nach-autolyse-titel', r.mitAutolyse, 'block');

    $('ablauf-liste').innerHTML = r.schritte.map(([t, was, dauer]) =>
        `<li><span class="when">T+${hm(t)}</span><div class="what"><b>${was}</b><span>${dauer}</span></div></li>`
    ).join('');

    // Übersicht
    setText('sum-teig', r.teiggewicht);
    setText('sum-teig-sub', el.teigTeilen.checked ? `2 × ${Math.round(r.einzelGewicht)} g` : '1 Brot');
    $('sum-dauer').innerHTML = hm(r.gesamtDauer) + '<small>h</small>';

    zeichneAnteile(anteile);
    fuelleSlider();
}

// --- Sichern & Laden ---
const saveSheet = $<HTMLDialogElement>('save-sheet');
const saveName = $<HTMLInputElement>('save-name');
const saveConfirm = $<HTMLButtonElement>('save-confirm');
saveName.addEventListener('input', () => { saveConfirm.disabled = !saveName.value.trim(); });
saveName.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); saveConfirm.click(); } });
saveConfirm.addEventListener('click', () => {
    const rezeptName = saveName.value.trim();
    if (!rezeptName) return;
    const rezeptDaten: GespeichertesRezept = {
        name: rezeptName,
        datum: new Date().toLocaleDateString('de-DE'),
        einstellungen: {
            anstellgut: el.anstellgut.value,
            sauerteigTemp: el.sauerteigTemp.value,
            gareTemp: el.gareTemp.value,
            brotGroesse: el.brotGroesse.value,
            hydration: el.hydrationSlider.value,
            mehlMischung: el.mehlMischung.value,
            customRoggen: custom.roggen.input.value,
            customDinkel: custom.dinkel.input.value,
            customWeizen: custom.weizen.input.value,
            customBuchweizen: custom.buchweizen.input.value,
            teigTeilen: el.teigTeilen.checked
        }
    };
    const gespeicherteRezepte = lese();
    gespeicherteRezepte.push(rezeptDaten);
    saveSheet.close();
    zeigeToast(schreibe(gespeicherteRezepte) ? `„${rezeptName}“ gesichert` : 'Sichern nicht möglich');
});

function speichereRezept() {
    saveName.value = 'Mein Sauerteigbrot';
    saveConfirm.disabled = false;
    saveSheet.showModal();
    saveName.select();
}

const loadSheet = $<HTMLDialogElement>('load-sheet');
const loadBody = $('load-body');

function renderRezeptListe() {
    const rezepte = lese();
    loadBody.innerHTML = '';
    if (rezepte.length === 0) {
        loadBody.innerHTML = '<div class="empty"><b>Keine Rezepte</b>Sichere ein Rezept über das Download-Symbol oben rechts.</div>';
        return;
    }
    const group = document.createElement('div');
    group.className = 'group';
    rezepte.forEach((r, i) => {
        const row = document.createElement('div');
        row.className = 'row';
        const btn = document.createElement('button');
        btn.className = 'row-btn';
        const n = document.createElement('span'); n.className = 'n'; n.textContent = r.name;
        const d = document.createElement('span'); d.className = 'd'; d.textContent = r.datum;
        btn.append(n, d);
        btn.addEventListener('click', () => wendeRezeptAn(r));
        const del = document.createElement('button');
        del.className = 'icon-btn del-btn';
        del.setAttribute('aria-label', `„${r.name}“ löschen`);
        del.innerHTML = PAPIERKORB_SVG;
        del.addEventListener('click', () => {
            const alle = lese(); alle.splice(i, 1); schreibe(alle); renderRezeptListe();
        });
        row.append(btn, del);
        group.append(row);
    });
    loadBody.append(group);
    const g2 = document.createElement('div');
    g2.className = 'group';
    g2.style.marginTop = '28px';
    const delAll = document.createElement('button');
    delAll.className = 'row destructive';
    delAll.textContent = 'Alle Rezepte löschen';
    delAll.addEventListener('click', () => {
        if (confirm('Alle gesicherten Rezepte löschen? Dies kann nicht widerrufen werden.')) {
            loescheAlle();
            renderRezeptListe();
            zeigeToast('Alle Rezepte gelöscht');
        }
    });
    g2.append(delAll);
    loadBody.append(g2);
}

function ladeRezept() {
    renderRezeptListe();
    loadSheet.showModal();
}

function wendeRezeptAn(rezept: GespeichertesRezept) {
    const e = rezept.einstellungen;
    ([
        [el.anstellgut, el.anstellgutWert, e.anstellgut],
        [el.sauerteigTemp, el.sauerteigTempWert, e.sauerteigTemp],
        [el.gareTemp, el.gareTempWert, e.gareTemp],
        [el.brotGroesse, el.brotGroesseWert, e.brotGroesse],
        [el.hydrationSlider, el.hydrationWert, e.hydration]
    ] as const).forEach(([input, wert, v]) => { input.value = v; wert.textContent = v; });
    el.mehlMischung.value = e.mehlMischung;
    if (typeof e.teigTeilen === 'boolean') el.teigTeilen.checked = e.teigTeilen;
    if (e.mehlMischung === 'custom') {
        el.customControls.style.display = 'block';
        setzeCustom('roggen', e.customRoggen);
        setzeCustom('dinkel', e.customDinkel);
        setzeCustom('weizen', e.customWeizen);
        setzeCustom('buchweizen', e.customBuchweizen);
        aktualisiereCustomSumme();
    } else {
        el.customControls.style.display = 'none';
        aktualisiereGewaehlteMischung();
    }
    markiereHydrationAenderung();
    aktualisiere();
    loadSheet.close();
    zeigeToast(`„${rezept.name}“ geladen`);
}

aktualisiereGewaehlteMischung();
setzeOptimaleHydration();
aktualisiere();

// Offline-Betrieb (nur im Build, im Dev-Server würde der Cache stören)
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => { /* App läuft auch ohne */ });
    // Gespeicherte Rezepte vor automatischem Löschen durch den Browser schützen
    navigator.storage?.persist?.().catch(() => { /* ignorieren */ });
}
