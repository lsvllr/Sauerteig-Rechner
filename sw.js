// Service Worker – Vorlage. Beim Build setzt vite.config.ts
// Build-Hash und Dateiliste für die Platzhalter unten ein.
const CACHE = 'sauerteig-__VERSION__';
const DATEIEN = __DATEIEN__;

self.addEventListener('install', (e) => {
    e.waitUntil(
        caches.open(CACHE)
            .then((c) => c.addAll(DATEIEN))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (e) => {
    e.waitUntil(
        caches.keys()
            .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
            .then(() => self.clients.claim())
    );
});

// Cache zuerst – die App läuft komplett offline. Updates kommen über
// eine neue sw.js (anderer Hash → neuer Cache).
self.addEventListener('fetch', (e) => {
    const req = e.request;
    if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

    if (req.mode === 'navigate') {
        e.respondWith(caches.match('/index.html').then((r) => r || fetch(req)));
        return;
    }
    e.respondWith(caches.match(req).then((r) => r || fetch(req)));
});

// Back-Timer: Erinnerungen per Push vom Server (server/server.ts)
self.addEventListener('push', (e) => {
    let d = {};
    try {
        d = e.data ? e.data.json() : {};
    } catch {
        d = { body: e.data ? e.data.text() : '' };
    }
    e.waitUntil(self.registration.showNotification(d.title || 'Sauerteig-Rechner', {
        body: d.body || '',
        icon: '/icon-192.png',
        tag: d.tag || undefined,
        renotify: !!d.tag,
        data: { url: d.url || '/' },
    }));
});

// Tipp auf eine Mitteilung: offene App nach vorn holen, sonst öffnen
self.addEventListener('notificationclick', (e) => {
    e.notification.close();
    const ziel = new URL((e.notification.data && e.notification.data.url) || '/', self.location.origin).href;
    e.waitUntil((async () => {
        const fenster = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
        for (const f of fenster) {
            if (new URL(f.url).origin === self.location.origin) return f.focus();
        }
        return self.clients.openWindow(ziel);
    })());
});
