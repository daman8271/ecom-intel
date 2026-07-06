# ecom-intel — Jivo multi-platform price intelligence

Operator manual. Auto-loads when you run `claude` in this directory.

## What this is
Tracks Jivo SKU prices/stock across quick-commerce + marketplace platforms at national scale (hundreds of pincodes per quick-comm platform, ≈332–798), and produces a clean branded Excel report per platform (6 sheets + an appended Predictions sheet). Built for daily cron runs — **one deadline-aligned sweep that lands the whole batch at 10:00 AM IST, plus an 18:00 guardian deep-dive** (cut from 2×/day to 1×/day 2026-06-28) — with an automated end-of-run review, auto-heal guardian, self-heal, and an **Amazon canonical auto-heal** (Claude merges truncated-title stub SKUs, identity-only — LIVE 2026-06-13). Pitched to Jivo's head of e-commerce.

## Architecture (the rule)
- **Scraping = deterministic Node + Playwright scripts. ZERO LLM in the scrape loop.** (LLM in the loop = 100–10000× the cost; never do it.)
- LLM is used only — later — for validation (cheap model) + narrative report (Sonnet).
- Each platform is self-contained under `platforms/<name>/`.
- `cron` triggers `./run_all.sh` for VPS-hosted platforms. Blinkit and Swiggy run
  off-box and enter the batch through ingest paths. BigBasket pincode runs separately
  at 03:00 through `platforms/bigbasket/team_run_pincode.sh` across VPS + Mac Pro +
  KVM1; its pincode workbook is private/direct-only.

## Layout
```
ecom-intel/
├── CLAUDE.md              # this file (operator manual)
├── README.md              # repo overview · docs/ARCHITECTURE.md · docs/PROXY.md
├── run.sh                 # ./run.sh <p>  (scrape→excel→review→vault→telegram→push)
├── run_all.sh             # one cron sweep: VPS platforms only; Blinkit/Swiggy drop-fed; BigBasket pincode separate
├── setup_cron.sh          # installs the cron (10:00 deadline sweep, 18:00 guardian deep-dive) + sets timezone
├── healthcheck.sh         # → tools/selfheal.sh (detect → re-run once → Telegram-escalate)
├── platforms/             # one self-contained dir per platform
│   ├── blinkit/ / bigbasket/  # LIVE; Blinkit Mac/drop, BigBasket national + pincode team runner
│   ├── flipkart-minutes/ flipkart/ amazon/ zepto/  # LIVE, direct VPS/data path
│   ├── amazon-fresh/      # 8th LIVE — logged-in (cookie transplant), i=freshstore, in cron
│   ├── amazon-now/        # 9th LIVE — logged-in (own dedicated account), genuine Now via scrape.ctnow.js (almBrandId=ctnow); lock kept w/ fresh pending a concurrency test
│   └── <p>/{SKILL.md, scrape.js, build_excel.py, pincodes.json}
├── tools/                 # predict.py · review.py · guardian.py · guardian_daily.sh · autoheal_amazon.py · vault_note.py · vault_rollup.py · selfheal.sh · proxy.js
├── vault/                 # Obsidian memory: runs/ daily/ weekly/ monthly/ platforms/  (committed)
├── data/                  # <p>/history.csv — the future price-model training table (committed)
├── reviews/  baselines/   # per-run verdicts + rolling expected metrics (committed)
├── output/                # generated Excel (gitignored)
└── logs/                  # per-run logs (gitignored)
```

## Run a platform
```bash
ssh macpro '/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh'  # Blinkit auth-required scrape/drop/ingest
cd platforms/bigbasket && ./team_run_pincode.sh run                         # BigBasket pincode team run
cat platforms/blinkit/result.json | python3 -m json.tool | head   # raw data
ls output/                  # the Excel
```

### Per-pincode coverage modes (Wave 1: blinkit / zepto / flipkart-minutes)
True per-pincode ground truth over the 25-city universe (1,885 pincodes). **Three modes, gated, non-breaking** (flag unset = old anchor `pincodes.json`, untouched):
```bash
# DAILY (the cron now uses this for VPS-run platforms): only pincodes where Jivo is on sale — zepto 693 / fkm 340.
# Blinkit uses its Mac Pro daily config (902 pins in the 2026-07-06 auth-corrected run)
# and is promoted only through platforms/blinkit/ingest.sh.
# FULL census: every one of the 1,885 pincodes (weekly / discovery)
COVERAGE_FULL=1 ./run.sh zepto               # uses platforms/<p>/pincodes.full25.json
# subset (relative path auto-normalized):
COVERAGE_FULL=1 PINCODES_FILE=platforms/zepto/pincodes.zerocities.json ./run.sh zepto
python3 tools/coverage/coverage_report.py $(date +%F)   # honest per-city x per-platform matrix
```
- **The daily cron (`deadline_sweep 10:00`) now runs `COVERAGE_DAILY=1`** (flipped 2026-06-30) → QC scrapes the Jivo-priced subsets, NOT anchors. Amazon platforms have no `pincodes.daily.json` → stay on anchors. Rollback: `crontab -e`, remove `COVERAGE_DAILY=1` (backup in `backups/crontab.pre-daily-coverage.*`).
- **Daily set goes stale** unless refreshed: a **weekly `COVERAGE_FULL` pass** rebuilds `pincodes.daily.json` (= price_captured pincodes from the fresh census). Regenerate the daily configs from the ledger after a full run.
- Configs: `pincodes.daily.json` (daily) · `pincodes.full25.json` (full; regen `python3 tools/pincodes/gen_full_configs.py`). NEVER edit `pincodes.json` (anchor = rollback).
- Ledger: `data/coverage/ledger.csv` — status per `(platform,pincode)`: `price_captured|serviceable_no_jivo|not_serviceable|error`.
- Scrapers hardened: checkpoint/resume (`.progress.<date>.json`), polite block-backoff (no evasion), partial-run tolerance. ⚠️ `.progress.<date>.json` is shared per-date — `rm platforms/<p>/.progress.*.json` before a fresh full run if the cron already populated it that day.
- **Amazon Wave 2** (fresh=acct 259, now=acct 520 — **kept strictly separate, never summed/co-scraped**): full per-pincode via `tools/coverage/amazon_chunked.sh <p>` (per-city resilient resume) → `amazon_merge.py` → `amazon_ledger.py`. Must NOT run while the cron scrapes Amazon (account-global location clobbers); see `tools/cron/babysit_20260630.sh`.

## Add a new platform (the workflow)
1. `cp -r platforms/blinkit platforms/<new>` and read `platforms/<new>/SKILL.md`
2. Adapt `scrape.js`: the site URL, the location-setting mechanism, the product-card selectors. Keep the same output JSON shape so `build_excel.py` works unchanged.
3. Test: `./run.sh <new>` — watch the log. **This is the "does it catch us" test** (datacenter VPS IP).
4. If it returns 0 rows / captcha / 403 → that platform blocks the datacenter IP → needs a residential proxy.
5. Commit + push.

## Route/risk map — VPS serial chain plus Mac/drop collectors
| Platform | Status | Notes |
|---|---|---|
| blinkit | ✅ LIVE (Mac/drop, auth-required) | Runs on the Mac Pro residential IP via `/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh`, drops JSON to `platforms/blinkit/ingest.sh`, and is spooled by `run_all.sh` from `output/`. Auth state must exist at `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`; the wrapper exports `BLINKIT_REQUIRE_AUTH=1`, `BLINKIT_OOS_PROBE=1`, `BLINKIT_PDP_OOS_PROBE=1`, and `BLINKIT_PDP_PRICE_PROBE=1`, and ingest runs with `BLINKIT_REQUIRE_AUTH_DROP=1`. The VPS `./run.sh blinkit` path refuses unless `ALLOW_BLINKIT_VPS=1`. Scrape is gated on verified store re-resolution; quality gates reject unauthenticated, unprobed, partial, wrong-config, low-row, low-store, blocked, false-OOS, stale-price, or missing-not-listed-report drops. |
|  | ❌ REMOVED from cron chain 2026-06-06 (was ⚠️ BLOCKED) | stealth context + POST to /api//search/v2 (WAF bypass). **2026-06-05 (c0bc409):** now paginates by offset (full Jivo catalogue, not just page 0); 403 fail-safe preserved (first-page non-200 → 0 rows + "search status" marker → review BROKEN). **STILL blocked by an IP-level 403** (currently 0 rows) — needs a residential proxy OR a logged-in  session (parked; see docs/PROXY.md + platforms//LOGIN-COOKIES.md). |
| zepto | ✅ LIVE | reached via bff-gateway.zeptonow.com BFF API (CloudFront on website still 403s) |
| flipkart-minutes | ✅ LIVE | HYPERLOCAL store; GPS "use my location"; scaled to 345 pincodes |
| flipkart | ✅ LIVE | marketplace, national pricing, 1 row/SKU |
| amazon | ✅ LIVE | guest interstitial bypass on /dp; targeted scrape of 314 ASINs; NO account location |
| amazon-fresh | ✅ LIVE | logged-in (cookie transplant), i=freshstore raw POST+HTML; 332 pincodes, ~63 SKUs, ~13k rows; in cron |
| bigbasket | ✅ LIVE (national + pincode team) | National workbook is the small `Jivo-Bigbasket-Live` diagnostic. Pincode production runs `platforms/bigbasket/team_run_pincode.sh` at 03:00 across VPS + Mac Pro + KVM1 with logged-in cookies, merges `result_pincode.json`, writes `Jivo-BigBasket-Pincode-Report` only to `output/private-no-group/`, and direct-sends from the configured direct-recipient secret. It must not be attached to the Ecom group batch. |
| amazon-now | ✅ LIVE | logged-in on its OWN dedicated account; **genuine Amazon Now** via `scrape.ctnow.js` (`/s?k=jivo&almBrandId=ctnow`, real "in 10 min"/overnight/tomorrow speed tiers). The old `i=nowstore` surface (legacy Prime-Now/marketplace SEARCH, 0 real ETAs) is FROZEN — see ROOTCAUSE-AmazonNow-2026-06-01.md. Now's account is now distinct from Fresh's (proven by cookie compare), so they CAN in principle run in parallel, but the shared .amazon-account.lock is KEPT until a supervised concurrent run proves non-interference. Cron PAUSED during rebuild; rebuilt + scale-validated 2026-06-03 (65-pincode representative run, 42 serviceable, badge-gated, no marketplace contamination). |

## Pipeline (run.sh, per platform)
`scrape.js` → `build_excel.py` → `tools/predict.py` (Predictions sheet) → `tools/review.py` → *(Amazon only: if held SOLELY on `shared_price_dup`, `tools/autoheal_amazon.py` merges truncated-title stub SKUs identity-only and re-reviews → SUSPECT can flip OK — see below)* → `tools/vault_note.py` (+ rollups)
→ **Telegram delivery (VERDICT-GATED: only verdict==OK ships to stakeholders; BROKEN/SUSPECT is held back + the owner is alerted)** → git commit+push. Every step after the scrape is best-effort and
never aborts the run. Excel/logs/result.json are gitignored; the Markdown vault, `data/`
history, and review verdicts/baselines are what get committed each run. In `run_all.sh` each
scrape is then re-evaluated by the **guardian auto-heal** (below).

## Cron (IST) — DEADLINE-ALIGNED (owner requirement 2026-06-06)
> **2026-06-30: the daily batch now runs `COVERAGE_DAILY=1`** — QC platforms scrape the Jivo-priced per-pincode subsets instead of anchors. Blinkit runs off-box from the Mac Pro daily config (902 pins in the 2026-07-06 auth-corrected run); VPS-run Zepto/FKM use zepto 693 / fkm 340. Amazon stays on anchors (no daily config). First-run review may flag `SUSPECT` (row-count vs old baseline; non-blocking) until baselines are rescaled.

Reports must all **LAND at the slot time (10:00 AM IST)** — the pipeline was cut from
2×/day to **one deadline-aligned sweep** on 2026-06-28 (the 15:00 sweep + 16:00 mailer were
retired). The deadline mechanism is **LIVE and PROVEN since 2026-06-06**: batches land at the
slot to the second (self-aligning chain + barrier). Cron fires
`tools/cron/deadline_sweep.sh 10:00` at **00:30 IST** (predicts its lead and sleeps to land at 10:00; the watchdog polls from 00:00-09:00 and only takes over after the 00:35 primary-launch grace); it predicts the chain runtime
(`tools/cron/predict_lead.py` — p90 of last 10 per-platform durations in
`tools/cron/durations.jsonl`, self-learning, `LEAD_MAX=32400`), sleeps to `T − lead`, then
runs `./run_all.sh` with `DEFER_DELIVERY=1 SWEEP_ID=… SWEEP_DEADLINE=…`. run.sh then SPOOLS
each OK report (`output/.batch/<sweep>/<p>.json`) instead of curling; after the loop
`tools/cron/send_batch.py` sleeps until the deadline (barrier) and ships ONE batch — header,
all summaries + Excels in canonical order, footer with held/late. BROKEN-run owner alerts
still send immediately. Failures fall back to immediate send (a report can be early, never
lost). Plain `./run_all.sh` without the env = old behavior. An **18:00 daily guardian
deep-dive** (`./tools/guardian_daily.sh`) is unchanged. The daily sweep scrapes the VPS-run
platforms SERIALLY — one platform at a time — in this order:
flipkart-minutes, flipkart, zepto, amazon, amazon-fresh, amazon-now.
**Blinkit and Swiggy are NOT in this serial chain — they run off-box on the
Mac Pro/residential IP and drop JSON into their `ingest.sh`; the 10:00 batch spools the
resulting workbooks from `output/`. BigBasket pincode is also outside the serial chain:
root cron runs `team_run_pincode.sh run` at 03:00 in tmux across VPS + Mac Pro + KVM1,
then keeps the pincode workbook private/direct-only. The smaller national BigBasket
workbook can still be spooled from `output/`.** ** was REMOVED from the chain
2026-06-06** (WAF-dead, ~40m heal-retry waste per sweep; rebuild pending — owner).
The sweep fires early in the small hours and self-aligns so the batch lands AT 10:00 AM.
Now that there is a single daily sweep, the old two-sweep overlap concern is moot; the
`.sweep-chain.lock` guard remains as a harmless backstop (see crontab.proposed.txt's comments
for the historical two-slot analysis).
SIM testing: `PLATFORMS_OVERRIDE`/`RUNNER_OVERRIDE` trip SIM MODE in run_all.sh
(guardian/healthcheck/vault/git all skipped — never reaches live scrapes); see
`tools/cron/tests/`.

**Why serial, not parallel:** running all VPS-hosted scrapers at once STARVED each scraper (CPU/network
contention → thin, partial data the hardened review.py correctly rejects) and made the
3 Amazon storefronts thrash their one shared account/server-side location. Serial gives
each platform full resources + correct store re-resolution, and the Amazon trio
(amazon, amazon-fresh, amazon-now — run consecutively) can never overlap. `run_all.sh`
holds the authoritative platform list. Each run.sh git-push critical section is
flock-serialized (.gitpush.lock) so commits don't collide. setup_cron.sh is re-runnable
and touches only "# ecom-intel"-tagged lines.

## Auto-heal guardian (tools/guardian.py + tools/guardian_daily.sh) — nothing breaks silently
- **Per-scrape (wired into run_all.sh):** after each platform's pipeline, `tools/guardian.py
  <p> --heal` re-evaluates the fresh result.json. It combines TWO verdicts — it CALLS
  `tools/review.py` for the shared hardened checks AND runs its own independent
  **11-bug-class deep-check** (worst verdict wins). On BROKEN it **QUARANTINEs** (keeps the
  last-good snapshot `result.last-good.json`, nothing published — Telegram is already
  verdict-gated), runs **bounded SELF-HEAL retries** (cap 2, re-run `./run.sh <p>` under the
  shared `.heal-<p>.lock`), then **ALERTs the owner** if still BROKEN. Failure-proof: a
  guardian hiccup can never fail the sweep (`|| true`).
- **Daily 18:00 deep-dive (tools/guardian_daily.sh):** read-only DETECT pass — runs the
  11-class audit over every platform, writes `reviews/guardian/health-<date>.md`, and
  Telegram-alerts only on a NEW bug class vs yesterday. Owns the standing diagnosis +
  trend; the inline hook owns the self-heal.

## Amazon canonical auto-heal (tools/autoheal_amazon.py) — LIVE 2026-06-13 (cad3a0ec)
Reactive, **identity-only** fix for the recurring Amazon `shared_price_dup` HOLD. Amazon
returns a TRUNCATED product title for a few pincode cards, so the SAME listing gets a second,
shorter `canonical` (a "stub", e.g. `…mustard-d-na` vs the full
`…mustard-daily-cooking-oil-1-litre-1l`); same ASIN + same `(sale,mrp)` → the gate reads it as
"distinct products, one price" = fabrication → SUSPECT → the whole report is held. (It also
silently inflates `unique_skus`.) The hook lives in `run.sh`, right after the verdict and
**before** the delivery gate: when an **Amazon** report is about to be held *solely* on
`shared_price_dup` and **nothing hard-fails**, it wakes Claude (`claude -p`, model chain
fable-5 → CLI default → haiku, so a model outage can't disable it) to decide, per colliding
pair, **same product** (merge) / **distinct** / **suspect**. It merges each stub into its
survivor in `result.json` (rewrites `canonical`/`item` ONLY — **never** `sale`/`mrp`/`discount`;
a priced-multiset **tripwire + snapshot rollback** enforce that), rebuilds the xlsx, and
re-runs `review.py` so the verdict flips **SUSPECT→OK** on the normal path (history.csv then
appends clean). **Fail-safe:** Claude unreachable / merges nothing → the report stays HELD,
exactly as today; one Telegram note per action; audit in `logs/autoheal.log`; reversible
snapshots in `backups/autoheal/` (gitignored). **Scoped:** Amazon family + the
`shared_price_dup` class only — other failure types and other platforms are untouched. Disable
by removing the script (the `run.sh` hook is a no-op without it); override model via
`AUTOHEAL_MODEL`. Tests `tools/tests/test_autoheal_amazon.py`; spec
`docs/superpowers/specs/2026-06-13-amazon-canonical-autoheal-design.md`.

**amazon-now and amazon-fresh now use SEPARATE dedicated Amazon accounts** (as of
2026-06-02; proven by comparing the storageState identity cookies — Now greets "Kanhaiya"
on `ubid-acbin 520-…`, Fresh on `259-…`; previously they shared ONE account, preserved as
`amazon-now.storageState.OLDACCT.bak.json`). Amazon's delivery location is account-global
(server-side). Since the 2026-06-05 switch to a **serial** sweep, the whole Amazon trio
(amazon, amazon-fresh, amazon-now) runs one-at-a-time and consecutively, so their per-pincode
location switches can never overlap by construction — the serial loop is the primary guarantee.
The per-platform `.${P}.lock` (and the legacy shared `.amazon-account.lock`) are still kept as
belt-and-suspenders so a platform can't overlap its OWN previous run (e.g. two run_all windows
stacking). Each login is its own cookie-transplant session; if either expires, that platform
goes BROKEN and the guardian/self-heal Telegram-alerts you to re-import cookies (independent —
one expiring no longer breaks the other). See platforms/amazon-now/PLAN.md.

Self-heal (tools/selfheal.sh, at the end of each sweep): re-runs a platform ONCE (under
logs/.heal-<p>.lock) only on a BROKEN verdict / staleness / row-collapse vs baseline;
SUSPECT is recorded (reviews/ + vault note) but NOT re-run. Escalates to Telegram + logs/health.log if still broken.

Blinkit production is Mac/drop-fed and auth-required. The Mac wrapper
`/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh` runs under LaunchAgent
`com.danny.blinkit-mac-to-vps` at 06:30 IST, loads
`/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`, and exports
`BLINKIT_REQUIRE_AUTH=1`, `BLINKIT_OOS_PROBE=1`, and
`BLINKIT_PDP_OOS_PROBE=1`, plus `BLINKIT_PDP_PRICE_PROBE=1`. VPS ingest defaults to `BLINKIT_REQUIRE_AUTH_DROP=1`; drops
must carry `summary.auth_session`, `summary.auth_required`, and
`summary.auth_verified` with `summary.auth_verified_pincodes == summary.pincodes_total`,
and unauthenticated/any-pincode unverified-auth Blinkit drops are rejected. VPS emergency/manual shards use
`/opt/ecom-intel/secrets/blinkit-auth-state.json`. Corrected 2026-07-06 run: 902 pins,
870 resolved, 468 Jivo pins, 1915 rows, 0 blocked, 303 stores.

Blinkit stock and price are determined by the resolved dark store from coordinates,
not just the visible pincode string. Treat `Listed - Out of stock` as a listed SKU
whose PDP/nearby probes verified no stock; treat `Not listed` as an expected SKU
absent from that resolved store. Treat `Listed - Stock unverified` as a fail-closed
intermediate state only: it may appear in raw/workbook diagnostics, but ingest and
quality delivery reject it. PDP price probing covers the screenshot canaries plus
high-value/plain-search rows without offer evidence so stale card prices do not ship.
The main workbook includes both `Listing Status`
and `Not Listed Pincodes`; the standalone not-listed workbook is direct-sent to
`917703818227@s.whatsapp.net` only after the main Blinkit workbook passes quality.
`platforms/blinkit/ingest.sh --deliver` calls
`tools/whatsapp/send_blinkit_not_listed_direct.sh` immediately, and the 10:00
mailer plus `*/15 6-12` cron retry idempotently if
`logs/blinkit-not-listed-wa-YYYY-MM-DD.sent` is absent.

## Review (tools/review.py) — never ship garbage, stay cheap
Deterministic checks ALWAYS run (free): zero/low rows, price/MRP/discount sanity,
captcha/403 markers, coverage collapse vs baseline, schema, freshness — these alone
decide BROKEN. **Hardened 2026-06-05 (4433756 + 439595e)** with four new checks:
- **geo_consistency** — one store_id spanning >2 cities → BROKEN (catches blinkit
  default-store contamination, e.g. id 31719 spanning 10 cities at one price).
- **priced_floor_block** — floors in-stock priced rows + scans status/block text +
  block_rate_pct (catches row-padding-on-block false-green and undetected blocks).
- **per_litre_sanity** — flags per_litre inflated by an under-counted combo volume,
  plus an absolute **₹6000/L oil ceiling** (catches name-hidden combo ₹/L inflation;
  gated to oil SKUs so a tiny saffron pack's huge nominal ₹/L isn't false-flagged).
- **shared_price_dup** — a discounted (sale,mrp) pair shared by several distinct SKUs
  (catches cross-sell / fabricated prices). For the **Amazon family**, a SUSPECT triggered
  *solely* by this check is now auto-healed — see **Amazon canonical auto-heal** above.

Baselines now only seed on a clean run — **SUSPECT/BROKEN runs no longer update the
rolling baseline** (the sole exception is a SUSPECT that is staleness-only, which still
has healthy counts). An OPTIONAL tiny LLM judgment (Claude Haiku) can only downgrade
OK→SUSPECT, runs only when not already BROKEN, and is FAILURE-PROOF: if the model is
unreachable or rate-limited it logs and the verdict stands on the deterministic checks.
Backend: uses ANTHROPIC_API_KEY if set, else `claude -p` headless on the logged-in Max
subscription (no per-token cost). Rate-limited subscription = deterministic-only, never a
crash. **The verdict GATES Telegram delivery in run.sh** (only OK ships to stakeholders).

## Memory vault (vault/) + history (data/)
After each run, tools/vault_note.py writes an Obsidian note vault/runs/<p>/<p>-<RUN_ID>.md
from result.json + the review verdict, upserts the platform hub (vault/platforms/<p>.md)
and the day's note (vault/daily/<date>.md), and appends one row per SKU×location to
data/<p>/history.csv. tools/vault_rollup.py builds daily/weekly/monthly trend notes.
Notes link into an Obsidian graph via body [[wikilinks]]; generators are deterministic,
stdlib-only, idempotent per RUN_ID. Design + conventions: vault/VAULT-SPEC.md.

## Proxy (residential Indian IPs) — see docs/PROXY.md
**NOT bought** — VPS-hosted platforms run without a paid proxy from the datacenter IP
(direct/no-login or on a transplanted logged-in cookie session). Blinkit is the exception:
it runs from the Mac Pro residential session with saved Blinkit auth state, not
anonymously from the VPS. Zepto was unlocked 2026-05-29 via its
bff-gateway.zeptonow.com BFF API (the CloudFront-fronted website still 403s the DC IP,
but the gateway is reachable direct). **'s stealth-POST path is
now IP-blocked again (403 → 0 rows, 2026-06-05): it is the one platform that now WANTS a
proxy** — a residential Indian IP OR a logged-in  session (see
platforms//LOGIN-COOKIES.md). tools/proxy.js + setup remain wired (the zepto
pattern) for exactly this, and as insurance if Amazon ever escalates to a captcha. Free
public proxies are OFF-LIMITS (MITM risk). Provider plan if ever needed: IPRoyal
residential, pay-as-you-go (~$10–25/mo at ~8 GB/month). amazon-now's hold-back is a
manual-only/account constraint, not an IP block.

## Known gaps (2026-07-06)
- **Blinkit auth freshness** — stock correctness depends on the saved Blinkit login/auth
  state. If the auth file is missing or expires, the run must fail before scraping and
  alert; it must not fall back to anonymous Blinkit.
- **Blinkit delivery gating nuance** — `blinkit_quality_monitor.sh poll` alerts on its
  own; batch/mailer/WhatsApp callers set `BLINKIT_MONITOR_EXIT_CODE=1` so the same
  checks become hard delivery blockers.
- **Blinkit unresolved pins** — the corrected auth run resolved 870 of 902 configured
  pins. Any unresolved pins are recorded honestly rather than contaminated with a default
  store.
- ** IP-level 403** — currently 0 rows; the WAF blocks the datacenter IP at the
  network level. Needs a residential proxy OR a logged-in  session (parked; see
  docs/PROXY.md + platforms//LOGIN-COOKIES.md).

## Hard lessons
- This repo IS the backup. After any VPS wipe: `git clone` + `npm install` per platform + `npx playwright install chromium`. Never lose the code again.
- Never reinstall Hermes via Hostinger's catalog on this box — it triggers a full OS recreate (wipes the disk).
