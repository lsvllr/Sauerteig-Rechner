import { defineConfig } from 'vite';

// Server (server/server.ts) als ein Node-Modul; Abhängigkeiten (web-push) bleiben in node_modules.
export default defineConfig({
    publicDir: false,
    build: { ssr: 'server/server.ts', outDir: 'dist-server', target: 'node22', emptyOutDir: true },
});
