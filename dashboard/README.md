# ThreatFeed Hosted Dashboard

Professional SOC-style web UI for ThreatFeed Analyzer. Static **Vite + React** app that reads `public/data/dashboard.json` produced by each pipeline run.

## Prerequisites

- [Node.js](https://nodejs.org/) 20+ (LTS)
- A completed `ThreatFeed-Analyzer.ps1` run (or `Sync-DashboardData.ps1`)

## Refresh data after a run

From the repo root:

```powershell
.\ThreatFeed-Analyzer.ps1
```

The analyzer writes `dashboard/public/data/dashboard.json` and mirrors to `data/dashboard.json`.

To sync without re-fetching feeds:

```powershell
.\Sync-DashboardData.ps1
```

From the dashboard folder:

```powershell
npm run sync
```

## Run locally

```powershell
cd dashboard
npm install
npm run dev
```

Open http://localhost:5173

Production preview:

```powershell
npm run build
npm run preview
```

## Deploy (Vercel — recommended)

Zero backend: the site is static files + JSON in `public/data/`.

1. Push the repo to GitHub.
2. Import the project in [Vercel](https://vercel.com/new).
3. Set **Root Directory** to `dashboard`.
4. Build command: `npm run build` (default from `vercel.json`).
5. Output: `dist`.

**Important:** Vercel builds do not run PowerShell. Refresh data before deploy:

```powershell
.\ThreatFeed-Analyzer.ps1
git add data/dashboard.json dashboard/public/data/dashboard.json
git commit -m "chore: refresh dashboard bundle"
```

Or use a scheduled GitHub Action / Task Scheduler job that commits the JSON artifact.

### Other hosts

- **Netlify:** root `dashboard`, publish `dist`, same pre-build data step.
- **Railway / any static host:** `npm run build` and serve `dist/`.
- **Internal Windows:** IIS or `npx serve dist` after build; copy `public/data` with each run.

## Data contract

`public/data/dashboard.json` (schema version `1`):

| Field | Description |
|-------|-------------|
| `stats` | Run counters (feeds, matches, CVEs, etc.) |
| `shiftBrief` | Top 10 priority articles with scores and reason chips |
| `articles` | Tracked article window (up to 500) |
| `aggregates` | Keyword + MITRE chart data |
| `tracking` | Topic trends (when exported from full run) |
| `cves` | Top 150 CVEs by CVSS (full list count in `stats.cveCount`) |

Split files (`shift-brief.json`, `articles.json`, …) are written for debugging; the app only loads `dashboard.json`.

## Legacy HTML report

`reports/index.html` is still generated (B-Seed) for offline / email attachment use. The hosted dashboard is the recommended view for daily SOC shifts.
