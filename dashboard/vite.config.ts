import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// On GitHub Pages a project site is served from /<repo>/, so the asset base
// must match. CI sets VITE_BASE (e.g. "/threatfeed-analyzer/"); local dev and
// other hosts (Vercel, custom domains) fall back to root.
const base = process.env.VITE_BASE ?? '/';

export default defineConfig({
  plugins: [react()],
  base,
  server: { port: 5173, host: true },
  preview: { port: 4173 },
});
