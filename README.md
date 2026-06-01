# ThreatFeed Analyzer

Zero-token threat intelligence morning brief: PowerShell pipeline + hosted React dashboard.

## Hosted dashboard (Vercel)

**Live:** https://threatfeed-dashboard.vercel.app

**GitHub:** https://github.com/Mustafa6066/threatfeed-analyzer

The UI lives in [`dashboard/`](dashboard/). Vercel builds from the repo root using root [`vercel.json`](vercel.json) (install/build in `dashboard/`).

Connect the GitHub repo in Vercel for automatic deploys on push. GitHub Actions refreshes `dashboard/public/data/` daily (06:00 UTC) when the workflow is pushed — see note below on `workflow` scope.

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
