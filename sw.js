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
