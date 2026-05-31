# ThreatFeed Analyzer — Deferred Work

Captured from `/plan-eng-review` (2026-05-31). B-Seed scope is locked; items below are explicitly **not** in the Week 1 ship path.

---

## B-Core (Week 2)

### TODO: Python heuristic scorer sidecar

- **What:** Add `ml/score.py` + `Invoke-Scorer.ps1` implementing `ml/score-contract.v1.json`; write `data/scores.json` with `engine=python-heuristic` fallback to PS scorer.
- **Why:** Enables learning loop and contract validation before ONNX; keeps ranking logic swappable without touching HTML generator.
- **Pros:** Same JSON contract as design doc; feedback priors (+8 acted, +4 up, −6 down) can influence scores.
- **Cons:** Python install burden on daily-task machine; cold-start quality unknown until labels exist.
- **Context:** B-Seed ships pure `Get-PriorityScore` in `lib/Scoring.ps1`. Sidecar reads `data/scored-input.jsonl` emitted by main script post-match. Start from design doc contract examples.
- **Depends on / blocked by:** B-Seed complete; `Get-ArticleKey` stable; ≥1 week of `data/feedback.jsonl` optional but helpful.

### TODO: Loopback feedback viewer (`Start-ThreatFeedViewer.ps1`)

- **What:** Local HTTP server on `127.0.0.1:8765` serving `reports/index.html` and accepting POST `/feedback` → append `data/feedback.jsonl`.
- **Why:** Static file-open cannot write JSONL; in-browser thumbs require a tiny local collector.
- **Pros:** Analyst-friendly UX vs CLI-only feedback.
- **Cons:** Another process to document; firewall/port edge cases on locked-down PCs.
- **Context:** B-Seed uses `Add-TfaFeedback.ps1 -ArticleKey <sha1> -Action <enum>`. Viewer is optional upgrade, not blocker for D4 dashboard.
- **Depends on / blocked by:** B-Seed feedback schema + `Get-ArticleKey` stable.

### TODO: Export-ShiftBrief.ps1 + brief.txt

- **What:** Plain-text shift brief export for Slack/email paste.
- **Why:** Distribution beyond browser (design doc open question default).
- **Pros:** Teammates who live in chat get Top-10 without opening HTML.
- **Cons:** Duplicate content maintenance vs HTML panel.
- **Context:** Shift Brief Top-10 already in `index.html` after B-Seed.
- **Depends on / blocked by:** B-Seed Shift Brief panel shipped.

### TODO: Dedup TTL + `.threatfeed-seen.json` compaction

- **What:** TTL on seen keys (design: 180d for feedback; extend dedup store hygiene).
- **Why:** URL-variant fragmentation and unbounded seen file growth.
- **Pros:** Cleaner novelty signal for `NEW` reason chip.
- **Cons:** Risk of re-surfacing old articles analysts thought gone.
- **Context:** B-Seed fixes key normalization via `Get-ArticleKey`; TTL is separate policy decision.
- **Depends on / blocked by:** `Get-ArticleKey` landed in B-Seed.

### TODO: Feed fetch parallelization

- **What:** Parallel `Get-FeedRaw` with concurrency cap (e.g. 4–6).
- **Why:** ~20 feeds × 25s worst case ≈ 8+ minutes sequential.
- **Pros:** Faster daily run; better shift-start freshness.
- **Cons:** Rate-limit / IP block risk from feed providers; harder error aggregation.
- **Context:** Eng review Section 4 — defer to B-Core; ship retry×1 in B-Seed first.
- **Depends on / blocked by:** Feed retry logic in B-Seed.

---

## B-ML (Week 3+)

### TODO: ONNX ranker train/export gate

- **What:** Train `ml/models/ranker-v1.onnx` only if ≥200 labeled rows **and** offline NDCG@10 beats heuristic by ≥5%.
- **Why:** Design doc ML gate prevents shipping untrusted model.
- **Pros:** True zero-token learning loop.
- **Cons:** Label sparsity on small SOC team; Windows ONNX runtime deps.
- **Context:** Requires `feedback.jsonl` + eval harness in `ml/tests/`.
- **Depends on / blocked by:** B-Core python-heuristic scorer + feedback volume.

### TODO: GitHub publish + CI smoke

- **What:** Public repo, MIT license, GHA: `pwsh -File ./ThreatFeed-Analyzer.ps1 -MaxFeeds 4 -NoOpen` + Pester + mock NVD.
- **Why:** OSS distribution plan Week 2+; no git repo today.
- **Pros:** Forkability matches builder mode intent.
- **Cons:** NVD key handling in CI; feed flakiness in smoke tests.
- **Context:** README already documents local folder copy for Week 1 teammates.
- **Depends on / blocked by:** B-Seed stable; git init.

---

## Integrations (explicitly deferred)

### TODO: STIX/MISP export/sync

- **What:** Hunt ticket / MISP-stub JSON (Approach C artifact).
- **Why:** Pre-platform wedge — not replacing OpenCTI/MISP yet.
- **Pros:** Strong OSS differentiation later.
- **Cons:** Workflow adoption uncertain; scope explosion.
- **Context:** Design doc positions ThreatFeed as morning router, not platform.
- **Depends on / blocked by:** B-Core feedback loop proving value.

### TODO: Slack webhook / autonomous LLM triage

- **What:** Push brief to Slack; cloud LLM ranking.
- **Why:** Zero cloud tokens constraint for triage; manual paste-first for deep dives.
- **Pros:** Convenience.
- **Cons:** Violates $0 triage KPI; adds secrets management.
- **Context:** ChatGPT/Claude/Gemini buttons remain manual out-of-band.
- **Depends on / blocked by:** Product decision reversal.
