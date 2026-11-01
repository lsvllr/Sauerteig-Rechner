import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { defineConfig, type Plugin } from 'vite';

// Erzeugt dist/sw.js aus der Vorlage ./sw.js mit allen Build- und public-Dateien
function serviceWorker(): Plugin {
    return {
        name: 'sauerteig-sw',
        apply: 'build',
        generateBundle(_, bundle) {
            const oeffentlich = readdirSync('public').filter((f) => !f.startsWith('.'));
            const dateien = [
                '/index.html',
                ...Object.keys(bundle).filter((f) => f !== 'index.html').map((f) => '/' + f),
                ...oeffentlich.map((f) => '/' + f),
            ];
            // index.html liegt hier evtl. noch nicht im Bundle → Quelle direkt hashen
            const hash = createHash('sha256').update(readFileSync('index.html'));
            for (const f of oeffentlich) hash.update(readFileSync('public/' + f));
            for (const datei of Object.values(bundle)) {
                hash.update(datei.type === 'chunk' ? datei.code : datei.source);
            }
            const version = hash.digest('hex').slice(0, 12);
            const quelle = readFileSync('sw.js', 'utf8')
                .replace('__VERSION__', version)
                .replace('__DATEIEN__', JSON.stringify(dateien));
            this.emitFile({ type: 'asset', fileName: 'sw.js', source: quelle });
        },
    };
}

export default defineConfig({
    plugins: [serviceWorker()],
});
