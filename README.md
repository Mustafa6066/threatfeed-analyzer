# ThreatFeed Analyzer

Zero-token threat intelligence morning brief: PowerShell pipeline + hosted React dashboard.

## Hosted dashboard (Vercel)

The UI lives in [`dashboard/`](dashboard/). Deploy on Vercel with:

- **Root Directory:** `dashboard`
- **Framework:** Vite
- **Build Command:** `npm run build`
- **Output Directory:** `dist`

Connect the GitHub repo in Vercel for automatic deploys on push. GitHub Actions refreshes `dashboard/public/data/` daily (06:00 UTC) and commits when feeds change, which retriggers Vercel.

## Local use

```powershell
.\ThreatFeed-Analyzer.ps1 -NoOpen
cd dashboard
npm install
npm run dev
```

## Docs

- [Platform guide](docs/PLATFORM-GUIDE.md)
- [Platform flow](docs/PLATFORM-FLOW.md)
