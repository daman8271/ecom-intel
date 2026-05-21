# ecom-intel — Jivo multi-platform price intelligence

Operator manual. Auto-loads when you run `claude` in this directory.

## What this is
Tracks Jivo SKU prices/stock across quick-commerce + marketplace platforms, across the top-20 Indian cities (~40 pincodes), and produces a clean Excel report per platform. Built for thrice-daily cron runs (9am/12pm/4pm IST) with an automated end-of-run review + self-heal. Pitched to Jivo's head of e-commerce.

## Architecture (the rule)
- **Scraping = deterministic Node + Playwright scripts. ZERO LLM in the scrape loop.** (LLM in the loop = 100–10000× the cost; never do it.)
- LLM is used only — later — for validation (cheap model) + narrative report (Sonnet).
- Each platform is self-contained under `platforms/<name>/`.
- `cron` triggers `./run.sh <platform>`.

## Layout
```
ecom-intel/
├── CLAUDE.md              # this file (operator manual)
├── README.md              # repo overview · docs/ARCHITECTURE.md · docs/PROXY.md
├── run.sh                 # ./run.sh <p>  (scrape→excel→review→vault→telegram→push)
├── setup_cron.sh          # installs the 3×/day staggered cron + self-heal
├── healthcheck.sh         # → tools/selfheal.sh (detect → re-run once → Telegram-escalate)
├── platforms/             # one self-contained dir per platform
│   ├── blinkit/ flipkart-minutes/ flipkart/ amazon/   # LIVE
│   ├── zepto/ (BLOCKED, proxy-ready)  amazon-now/ (login-gated)
│   └── <p>/{SKILL.md, scrape.js, build_excel.py, pincodes.json}
├── tools/                 # review.py · vault_note.py · vault_rollup.py · selfheal.sh · proxy.js
├── vault/                 # Obsidian memory: runs/ daily/ weekly/ monthly/ platforms/  (committed)
├── data/                  # <p>/history.csv — the future price-model training table (committed)
├── reviews/  baselines/   # per-run verdicts + rolling expected metrics (committed)
├── output/                # generated Excel (gitignored)
└── logs/                  # per-run logs (gitignored)
```

## Run a platform
```bash
./run.sh blinkit            # scrape + build excel, ~100s
cat platforms/blinkit/result.json | python3 -m json.tool | head   # raw data
ls output/                  # the Excel
```

## Add a new platform (the workflow)
1. `cp -r platforms/blinkit platforms/<new>` and read `platforms/<new>/SKILL.md`
2. Adapt `scrape.js`: the site URL, the location-setting mechanism, the product-card selectors. Keep the same output JSON shape so `build_excel.py` works unchanged.
3. Test: `./run.sh <new>` — watch the log. **This is the "does it catch us" test** (datacenter VPS IP).
4. If it returns 0 rows / captcha / 403 → that platform blocks the datacenter IP → needs a residential proxy.
5. Commit + push.

## Block-risk map (datacenter VPS IP)
| Platform | Risk | Notes |
|---|---|---|
| blinkit | low (proven) | localStorage location override works |
| zepto | low–med | similar quick-comm |
| flipkart-minutes | med | newer quick-comm |
| amazon-now | med–high | Amazon infra |
| flipkart | high | marketplace bot detection |
| amazon | very high | ML bot detection, blocks datacenter IPs fast → proxy required |

## Pipeline (run.sh, per platform)
`scrape.js` → `build_excel.py` → `tools/predict.py` (Predictions sheet) → `tools/review.py` → `tools/vault_note.py` (+ rollups)
→ Telegram delivery → git commit+push. Every step after the scrape is best-effort and
never aborts the run. Excel/logs/result.json are gitignored; the Markdown vault, `data/`
history, and review verdicts/baselines are what get committed each run.

## Cron (IST) — installed by ./setup_cron.sh
One sweep per window at 09:00 / 12:00 / 16:00 via `./run_all.sh`, which scrapes every
live platform SEQUENTIALLY (blinkit → flipkart-minutes → flipkart → amazon) then runs the
self-heal pass. Sequential because at ~332 Blinkit stores a sweep is ~13 min and must not
overlap the others on this single VPS. setup_cron.sh is re-runnable and touches only
"# ecom-intel"-tagged lines. No zepto, no amazon-now.

Self-heal (tools/selfheal.sh, at the end of each sweep): re-runs a platform ONCE (under
logs/.heal-<p>.lock) only on a BROKEN verdict / staleness / row-collapse vs baseline;
SUSPECT is recorded (reviews/ + vault note) but NOT re-run. Escalates to Telegram + logs/health.log if still broken.

Blinkit pincodes: pincodes.json = 332 distinct store coordinates covering 798 pincodes
(deduped from PinCode-blinkit.xlsx; pincodes.full.json = all 798, pincodes.coverage.md =
geocoding report). Geocoding is region-level (free datasets), so coords are metro-accurate, not street-accurate.

## Review (tools/review.py) — never ship garbage, stay cheap
Deterministic checks ALWAYS run (free): zero/low rows, price/MRP/discount sanity,
captcha/403 markers, coverage collapse vs baseline, schema, freshness — these alone
decide BROKEN. An OPTIONAL tiny LLM judgment (Claude Haiku) can only downgrade OK→SUSPECT,
runs only when not already BROKEN, and is FAILURE-PROOF: if the model is unreachable or
rate-limited it logs and the verdict stands on the deterministic checks. Backend: uses
ANTHROPIC_API_KEY if set, else `claude -p` headless on the logged-in Max subscription
(no per-token cost). Rate-limited subscription = deterministic-only, never a crash.

## Memory vault (vault/) + history (data/)
After each run, tools/vault_note.py writes an Obsidian note vault/runs/<p>/<p>-<RUN_ID>.md
from result.json + the review verdict, upserts the platform hub (vault/platforms/<p>.md)
and the day's note (vault/daily/<date>.md), and appends one row per SKU×location to
data/<p>/history.csv. tools/vault_rollup.py builds daily/weekly/monthly trend notes.
Notes link into an Obsidian graph via body [[wikilinks]]; generators are deterministic,
stdlib-only, idempotent per RUN_ID. Design + conventions: vault/VAULT-SPEC.md.

## Proxy (residential Indian IPs) — see docs/PROXY.md
Some sites block our datacenter IP (Zepto = hard 403; Amazon may escalate). The system
manages the proxy; you only supply credentials. Provider: IPRoyal residential, pay-as-you-go
(~$10–25/mo at ~8 GB/month). Set PROXY_URL / PROXY_USERNAME / PROXY_PASSWORD in secrets.env
(template secrets.env.example). tools/proxy.js returns the proxy when set, else null ⇒ DIRECT.
Only Zepto is wired today; wire others (Amazon first) with the same 2-line chromium.launch
change ONLY if they start getting blocked — don't burn proxy GB on platforms that work direct.

## Hard lessons
- This repo IS the backup. After any VPS wipe: `git clone` + `npm install` per platform + `npx playwright install chromium`. Never lose the code again.
- Never reinstall Hermes via Hostinger's catalog on this box — it triggers a full OS recreate (wipes the disk).
