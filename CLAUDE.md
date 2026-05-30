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
│   ├── blinkit/ instamart/ flipkart-minutes/ flipkart/ amazon/ zepto/   # 6 LIVE
│   ├── amazon-now/        # login-gated; PLAN.md + login_v2.js WIP (uncommitted)
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

## Block-risk map (datacenter VPS IP) — all 6 LIVE platforms run DIRECT, no proxy
| Platform | Status | Notes |
|---|---|---|
| blinkit | ✅ LIVE | localStorage location override; 332 store coords / 798 pincodes |
| instamart | ✅ LIVE | stealth context + POST to /api/instamart/search/v2 (WAF bypass) |
| zepto | ✅ LIVE | reached via bff-gateway.zeptonow.com BFF API (CloudFront on website still 403s) |
| flipkart-minutes | ✅ LIVE | HYPERLOCAL store; GPS "use my location"; scaled to 345 pincodes |
| flipkart | ✅ LIVE | marketplace, national pricing, 1 row/SKU |
| amazon | ✅ LIVE | interstitial bypass on /dp; targeted scrape of 314 ASINs |
| amazon-now | 🔧 WIP | login automation against AWS WAF AAMation captcha — see platforms/amazon-now/PLAN.md (uncommitted) |

## Pipeline (run.sh, per platform)
`scrape.js` → `build_excel.py` → `tools/predict.py` (Predictions sheet) → `tools/review.py` → `tools/vault_note.py` (+ rollups)
→ Telegram delivery → git commit+push. Every step after the scrape is best-effort and
never aborts the run. Excel/logs/result.json are gitignored; the Markdown vault, `data/`
history, and review verdicts/baselines are what get committed each run.

## Cron (IST) — installed by ./setup_cron.sh
One sweep per window at 09:00 / 12:00 / 16:00 via `./run_all.sh`, which scrapes the
6 live platforms IN PARALLEL (blinkit, instamart, flipkart-minutes, flipkart, amazon,
zepto) then runs the self-heal pass at :30. Switched sequential→parallel 2026-05-22
(VPS has headroom); each run.sh git-push critical section is flock-serialized
(.gitpush.lock) so concurrent commits don't collide. setup_cron.sh is re-runnable
and touches only "# ecom-intel"-tagged lines. amazon-now is NOT in cron — gated
behind login (see platforms/amazon-now/PLAN.md for the in-progress login work).

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
**NOT bought and NOT currently needed** — all 6 live platforms run direct from the
datacenter IP. Zepto was unlocked 2026-05-29 via its bff-gateway.zeptonow.com BFF API
(the CloudFront-fronted website still 403s the DC IP, but the gateway is reachable
direct). Instamart was unlocked 2026-05-22 via stealth POST to its public search API.
tools/proxy.js + setup remain wired in case Amazon escalates to a captcha. Free
public proxies are OFF-LIMITS (MITM risk). Provider plan if ever needed: IPRoyal
residential, pay-as-you-go (~$10–25/mo at ~8 GB/month). The only remaining gated
platform is amazon-now, and that's login-gated, not IP-gated.

## Hard lessons
- This repo IS the backup. After any VPS wipe: `git clone` + `npm install` per platform + `npx playwright install chromium`. Never lose the code again.
- Never reinstall Hermes via Hostinger's catalog on this box — it triggers a full OS recreate (wipes the disk).
