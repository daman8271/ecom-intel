# ecom-intel — Jivo multi-platform price intelligence

A deterministic price- and stock-intelligence pipeline for the **Jivo** brand. It
tracks Jivo SKU prices, MRP, discount %, per-litre cost and in-stock status across
India's quick-commerce apps and marketplaces — at **national scale, hundreds of
pincodes per quick-commerce platform** (≈332–798, scaled up from the original top-20
cities) — and emits a clean **branded Excel report per platform** (6 sheets + an
appended Predictions sheet) plus an **Obsidian-style Markdown "memory vault"**. Runs
unattended on a Hostinger VPS via **cron — two full sweeps daily, DEADLINE-ALIGNED so all
reports LAND together at 12:00 + 15:00 IST** (the serial chain starts early — per-platform
runtimes predicted from history — and finished reports wait at a barrier, then ship as ONE
batch at the slot time) **plus an 18:00 guardian deep-dive** — with an automated review, an
auto-heal guardian, self-heal, and verdict-gated Telegram delivery. Built and pitched to
Jivo's head of e-commerce.

> Companion docs: [`CLAUDE.md`](CLAUDE.md) (operator quick-reference, auto-loads in
> Claude Code) · [`REPORT.md`](REPORT.md) (platform-coverage map) ·
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (design deep-dive).

---

## The one architecture rule: ZERO LLM in the scrape loop

**Scraping is 100% deterministic Node + Playwright.** No language model is ever
called inside the per-pincode scrape loop. The only place an LLM is allowed is a
**cheap, end-of-run review** and the **narrative reports** — never in the hot path.

**Why this is non-negotiable — cost.** A run touches hundreds of pincodes × N platforms ×
many product cards, multiple times a day, forever. Putting an LLM call in that loop
makes every datapoint an API call: that is **100×–10,000× the cost** of a
deterministic DOM parse, for data that a CSS selector + regex extracts perfectly.
Selectors are free, instant, and reproducible. So:

- **Scrape loop** → Playwright navigates, sets the delivery location, reads product
  cards with geometry/regex heuristics. Pure JS. No LLM.
- **End of run** → a *single* cheap-model **review** sanity-checks the result
  (described at DESIGN level below) and a Markdown/narrative report is written.
- **Self-heal** → if a run looks broken, **one** Claude Code invocation diagnoses
  and (when safe) repairs the scraper — outside the loop, after the fact.

If you only remember one thing about this repo, remember this rule.

---

## Platform coverage

The core question this project answers from a datacenter VPS IP is *"does the site
catch us?"* Current state (see [`REPORT.md`](REPORT.md) for the full map):

| Platform | Type | Status | Coverage | Jivo SKUs | Notes |
|---|---|---|---|---|---|
| **Blinkit** | quick-comm | ✅ LIVE | 161/332 stores carry Jivo (≈798 pincodes) | ~8 | `localStorage` location override, no proxy |
| **** | quick-comm | ⚠️ BLOCKED | 332 pincodes | ~8 | stealth POST to `/search/v2`, now **offset-paginated** for the full catalogue; but the DC IP is **403-blocked again (0 rows, 2026-06-05)** → needs a residential proxy or a logged-in  session (`platforms//LOGIN-COOKIES.md`). 403 fail-safe → review BROKEN, never ships. |
| **Zepto** | quick-comm | ✅ LIVE | 332 pincodes | ~11 | reached via `bff-gateway.zeptonow.com` BFF API (the CloudFront website still 403s — gateway is direct), no proxy |
| **Flipkart Minutes** | quick-comm | ✅ LIVE | 345 pincodes | ~10 | `HYPERLOCAL` store; GPS "use my location" |
| **Flipkart** | marketplace | ✅ LIVE | national | ~61 | national pricing → 1 row/SKU, tagged "All India" |
| **Amazon** | marketplace | ✅ LIVE | national | ~314 ASINs | guest `/dp` scrape with interstitial bypass; richest catalog; sets no account location |
| **Amazon Fresh** | quick-comm | ✅ LIVE | 332/332 pincodes serviceable | ~63 | logged-in (cookie transplant); `i=freshstore` raw POST+HTML; ~13k rows/run, ~7× richer than Now; no proxy; in cron |
| **BigBasket** | grocery (national) | ✅ LIVE | national (single "All India") | ~27 | stealth browser past Akamai + in-page `listing-svc` JSON API; national pricing → 1 row/SKU; no proxy, no login; in cron |
| **Amazon Now** | quick-comm | ✅ LIVE | — | 0–14 | genuine Amazon Now via `scrape.ctnow.js` (`almBrandId=ctnow`). **Now in the serial cron sweep** — the serial loop (one platform at a time) is what guarantees it never co-runs with amazon-fresh (Amazon's delivery location is account-global server-side). Thinner catalog than Fresh. See `platforms/amazon-now/PLAN.md` |

- **Marketplaces (Flipkart / Amazon)** price nationally, so we scrape the catalog
  once and tag rows "All India" rather than looping pincodes. Their value is
  **catalog breadth + price/MRP/discount** (Amazon tracks 314 ASINs vs ~8–11 on
  quick-comm). That's why their Excel city-matrix is a single column *by design*.
- **Zepto** went live 2026-05-29 — the public website is CloudFront-fronted and
  hard-403s the datacenter IP, but the app's BFF API gateway is reachable directly.
  No proxy needed. See `platforms/zepto/SKILL.md`.
- **Amazon Fresh** went live 2026-05-30 — the `i=freshstore` storefront, scraped on a
  **logged-in session** (no proxy). The VPS IP can't pass Amazon's signin WAF, so the
  user exports cookies on a clean IP (Cookie-Editor) and they're imported via
  `platforms/amazon-now/import_cookies.js` (session valid ~1 year). Per pincode it does
  a raw POST to `glow/address-change` then a GET of `/s?k=jivo&i=freshstore` HTML — no
  page render. It is **one Amazon account** shared with Amazon Now
  (`amazon-fresh.storageState.json` is a symlink to the amazon-now one). ~63 Jivo SKUs,
  332 pincodes, ~13k rows/run. See `platforms/amazon-fresh/SKILL.md`.
- **Amazon Now** is **now in the serial cron sweep** (the three Amazon storefronts —
  guest `amazon`, `amazon-fresh`, `amazon-now` — run consecutively, one at a time).
  Amazon resolves delivery location server-side per account, so Now and Fresh must never
  run concurrently; since the sweep went **serial** on 2026-06-05, that overlap is
  impossible by construction. Now is a far thinner catalog than Fresh. See
  `platforms/amazon-now/PLAN.md`.

---

## How to run

```bash
./run.sh <platform>     # blinkit |  | zepto | flipkart-minutes | flipkart
                        # | amazon | amazon-fresh | amazon-now | bigbasket   (9 in the serial cron sweep)
                        # the serial sweep guarantees amazon-now never co-runs with amazon-fresh
                        #  is in the loop but currently 403-blocked (0 rows → held back)
```

Examples:

```bash
./run.sh blinkit                       # scrape + build Excel + deliver, ~100s
./run.sh amazon                        # marketplace catalog, ~30s
cat platforms/blinkit/result.json | python3 -m json.tool | head   # raw data
ls output/                             # the generated Excel reports
```

### Where outputs go

| Path | Contents | Tracked in git? |
|---|---|---|
| `output/` | Generated **Excel** reports (`Jivo-<Platform>-Live-Report-<date>.xlsx`), one per platform per run | gitignored |
| `platforms/<p>/result.json` | Raw scraped data: `{summary, perPin, allRows}` | gitignored |
| `logs/` | Per-run scrape logs, `cron.log`, `health.log`, `telegram.log`, self-heal logs | gitignored |
| `vault/` | Obsidian-style linked **Markdown notes**: `runs/`, `platforms/`, `daily/`, `weekly/`, `monthly/` (+ `VAULT-SPEC.md`) | tracked |
| `data/<p>/history.csv` | Machine-readable **append-only history**, one row per (run, SKU, location); feeds a future price-intelligence model | tracked |
| `reviews/` | Per-run automated **review verdicts** (`<platform>-<RUN_ID>.json`) | tracked |
| `baselines/` | Rolling **expected** per-platform stats (updated from OK runs; used to detect collapse) | tracked |
| `tools/` | Cross-platform pipeline steps: `review.py`, `autoheal_amazon.py`, `vault_note.py`, `vault_rollup.py`, `selfheal.sh`, `proxy.js` | tracked |

---

## The pipeline

Each `./run.sh <platform>` now executes this **fully-wired** chain. Everything after
the scrape is best-effort (`|| true`) and can never fail the run:

```
scrape.js (Node+Playwright)      WIRED  — deterministic, no LLM → result.json
 → build_excel.py (openpyxl)     WIRED  — result.json → branded 6-sheet Excel
 → tools/predict.py              WIRED  — appends a "Predictions" sheet (reads data/ history)
 → tools/review.py               WIRED  — sanity-check run → reviews/<run>.json verdict
 → tools/autoheal_amazon.py      WIRED  — Amazon only: if held SOLELY on shared_price_dup, Claude merges truncated-title stub SKUs (identity-only) & re-reviews → SUSPECT can flip OK
 → tools/vault_note.py --csv-only WIRED — append data/<p>/history.csv (run notes via rollup)
 → Telegram delivery             WIRED  — VERDICT-GATED: only OK ships the report+Excel; BROKEN/SUSPECT held back + owner alerted
 → git add vault data reviews baselines → commit → push   WIRED (flock-serialized)
```

> In `run_all.sh`, each scrape is then re-evaluated by the **auto-heal guardian**
> (`tools/guardian.py --heal`): on BROKEN it quarantines (keeps last-good, nothing
> published), runs bounded self-heal retries, and alerts the owner. See *Schedule &
> self-heal* below.

Step by step:

1. **Scrape** — `platforms/<p>/scrape.js` drives Playwright, sets the per-pincode
   delivery location, extracts Jivo product cards, writes `result.json` as
   `{summary, perPin, allRows}`. Pure deterministic JS, no LLM.
2. **Build Excel** — `platforms/<p>/build_excel.py` (openpyxl) turns `result.json`
   into a branded **6-sheet** workbook: *Summary · Master Data · Pricing Matrix ·
   Stock Status · Discount Analysis · Coverage & Gaps*. Platform name is derived
   from the folder, so the script is identical across platforms (Amazon Fresh ships
   a Fresh-specific variant with a *Now Serviceability* sheet).
3. **Predictions** — `tools/predict.py <platform> <xlsx>` opens the just-built
   workbook and **appends a "Predictions" sheet** computed from `data/<p>/history.csv`
   (deterministic, stdlib + openpyxl, no LLM).
4. **Automated review** — `tools/review.py <platform> <RUN_ID>` runs **free
   deterministic** sanity checks over `result.json` (row count vs baseline,
   implausible prices, coverage drops, schema drift), writes
   `reviews/<platform>-<RUN_ID>.json`, and updates `baselines/<platform>.json` **on OK
   runs only** (SUSPECT/BROKEN no longer seed the baseline). **Hardened 2026-06-05** with
   four new checks: `geo_consistency` (one store_id across >2 cities → BROKEN, catches
   default-store contamination), `priced_floor_block` (row-padding-on-block + undetected
   blocks), `per_litre_sanity` (combo-volume per-litre inflation + an absolute ₹6000/L oil
   ceiling), and `shared_price_dup` (cross-sell/fabricated prices). An optional single tiny
   **Claude Haiku** call is the *only* LLM touch and is failure-proof (never crashes the
   run, never enters the scrape loop). Exit: 0 = OK/SUSPECT, 2 = BROKEN.
5. **Vault + history** — `run.sh` calls `tools/vault_note.py <platform> <RUN_ID>
   --csv-only` to append one row per SKU×location to `data/<platform>/history.csv`;
   the per-run Obsidian notes + daily/weekly/monthly rollups are (re)built by
   `tools/vault_rollup.py` after the sweep. Stdlib-only, deterministic, no LLM.
6. **Telegram delivery** — **verdict-gated**: only a clean `OK` run ships the polished
   Markdown summary + Excel to stakeholders. `run.sh` builds that summary **deterministically
   from `result.json`** (cheapest in-stock SKU by ₹/L, top discount, coverage) — *no LLM*. A
   `BROKEN`/`SUSPECT` run is **held back** and the owner gets a short alert instead (never the
   garbage report). Best-effort, logged to `logs/telegram.log`.
7. **Commit + push** — `git add vault data reviews baselines` → commit → push, inside a
   `flock` critical section (`.gitpush.lock`) so any concurrent `run.sh` instance (a
   guardian/self-heal re-run, or the post-sweep vault rebuild) can't collide on the commit.

**Auto-heal guardian** (`tools/guardian.py`, **new 2026-06-05**) runs **inline per scrape**
inside `run_all.sh`: it re-evaluates the fresh `result.json` by combining `tools/review.py`'s
hardened checks with its own independent **11-bug-class deep-check** (worst verdict wins). On
BROKEN it **quarantines** (keeps `result.last-good.json`, nothing published), runs **bounded
self-heal retries** (re-run `./run.sh <p>`, cap 2), and **alerts the owner** if still broken.
A separate **18:00 daily deep-dive** (`tools/guardian_daily.sh`) re-runs the 11-class audit
read-only over every platform, writes `reviews/guardian/health-<date>.md`, and alerts only on
a NEW bug class vs yesterday.

The legacy **self-heal backstop** still runs *after* the serial sweep (from `run_all.sh`):
`tools/selfheal.sh` heals on three signals — review verdict BROKEN/SUSPECT · stale/missing
`result.json` · row collapse vs baseline — re-runs the platform once under the same
per-platform `.heal-<p>.lock`, and escalates to Telegram if still broken. `healthcheck.sh` is
the older `total_rows < 20` / `> 15h`-stale variant that can invoke **Claude Code** (`claude
-p`) to apply a *safe* selector/parsing fix only; on a captcha / IP block / login wall it
writes `logs/<p>-DIAGNOSIS.md` and stops. **All are forbidden from ever putting an LLM inside
the scrape loop.**

**Amazon canonical auto-heal** (`tools/autoheal_amazon.py`, **LIVE 2026-06-13**) is a narrow,
reactive repair for the one chronic Amazon false-hold. Amazon occasionally returns a *truncated*
product title for a few pincode cards, so the same listing gets a second, shorter `canonical`
(a "stub", e.g. `…mustard-d-na` vs the full `…mustard-daily-cooking-oil-1-litre-1l`); same ASIN
+ same `(sale,mrp)` makes `shared_price_dup` read it as fabrication → SUSPECT → the whole report
held. When an **Amazon** report is about to be held *solely* on `shared_price_dup` (no
hard-fail), the hook in `run.sh` wakes Claude (`claude -p`, model fallback chain fable-5 → CLI
default → haiku) to merge each stub into its real product — **identity only**, rewriting
`canonical`/`item` and **never** a price (a priced-multiset *tripwire* + snapshot rollback
enforce this) — then rebuilds the report and re-reviews so the verdict flips SUSPECT→OK on the
normal delivery path. Like the review judge, this LLM call is **outside the scrape loop** and
**failure-proof**: if Claude is unreachable or finds nothing to merge, the report simply stays
held (today's behaviour). Owner is pinged on Telegram per action; reversible snapshots in
`backups/autoheal/`. Scoped to the Amazon family + the `shared_price_dup` class only. Spec:
`docs/superpowers/specs/2026-06-13-amazon-canonical-autoheal-design.md`.

---

## The "memory vault"

The long-term goal is a queryable history, not just today's spreadsheet. Two
linked layers — the full design (Obsidian conventions, wikilink/MOC topology, CSV
schema) is in [`vault/VAULT-SPEC.md`](vault/VAULT-SPEC.md):

- **`vault/` — human/Obsidian layer.** Linked Markdown notes whose `[[wikilinks]]`
  form a knowledge graph:
  - `vault/runs/<platform>/<platform>-<RUN_ID>.md` — one note per run (basenames are
    globally unique so wikilinks resolve cleanly).
  - `vault/platforms/<platform>.md` — per-platform hub/MOC linking every run.
  - `vault/daily/`, `vault/weekly/`, `vault/monthly/` — time rollups that link down
    to runs and up the date spine (`run → daily → weekly → monthly`), so trends and
    distribution gaps read like a research journal in Obsidian.
- **`data/<platform>/history.csv` — machine layer.** Append-only, one row per
  `(run, SKU, location)`:
  `run_id,date_ist,platform,canonical_sku,city,pincode,price,mrp,discount_pct,in_stock`.
  Idempotent within a run (de-dup key `run_id,platform,canonical_sku,pincode`). This
  is the training/feature substrate for a **future price-intelligence model**
  (predict stock-outs, detect competitor moves, recommend pricing).

Together: humans browse the vault; a model reads `data/`. Generated by
`tools/vault_note.py` / `tools/vault_rollup.py` — deterministic, stdlib-only, no LLM.

---

## Schedule & self-heal

**Schedule installed and live — DEADLINE-ALIGNED (owner requirement 2026-06-06):** reports
must all **LAND at the slot time**, not start at it. Cron fires `tools/cron/deadline_sweep.sh
<slot>` well before each slot; it predicts the serial chain's runtime (p90 of each platform's
last 10 recorded durations — `tools/cron/durations.jsonl`, self-learning via
`record_duration.sh`), sleeps until `T − lead`, then runs `./run_all.sh` with
`DEFER_DELIVERY=1`. Each platform's verdict-gated Telegram payload is **spooled**
(`output/.batch/<sweep>/`) instead of sent; after the chain, `tools/cron/send_batch.py`
**sleeps until the deadline (barrier)** and ships everything as ONE batch — header, every
platform's summary + Excel in canonical order, footer listing held/late platforms. BROKEN-run
owner alerts still fire immediately (bad news never queues). Chain overrun → batch goes when
done, marked "(late by Xm)". Any spool/batch failure falls back to the old immediate send — a
report can be early, never lost.

| Cron fire (IST) | Deadline slot | Job |
|---|---|---|
| **08:30** | **12:00** | `deadline_sweep.sh 12:00` → sleep to T−lead → `run_all.sh` (serial, spooled) → batch at 12:00 |
| **11:30** | **15:00** | same → batch at 15:00 |
| **18:00** | — | `tools/guardian_daily.sh` — read-only 11-bug-class deep-dive over every platform → alert on NEW bug class |

The morning slot moved **10:00 → 12:00** (fire 06:30 → 08:30; fire = slot − 3h30m) per the
owner's 2026-06-06 order — see `crontab.proposed.txt` (the lead installs). The mechanism is
**LIVE and PROVEN as of 2026-06-06**: the first two real batches landed at exactly 10:00:00
and 15:00:00 IST, with the serial chain at ~2h25m and the barrier sleep ~55m.
`LEAD_MAX=12600` (3h30m ceiling; observed p90 leads ~3h18–21m after 's 2026-06-06
removal). Plain `./run_all.sh` with no env vars = the old immediate-delivery behavior,
unchanged. With the slots now 3h apart, the morning sweep's barrier sleep + post-batch tail
overlap the afternoon chain — the concrete analysis (and a proposed `.sweep-chain.lock`
mitigation for the selfheal backstop) lives in `crontab.proposed.txt`'s comments.

> **Why serial, not parallel:** running all 9 at once **starved** each scraper
> (CPU/network contention → thin, partial data the hardened review.py rejects) and made
> the 3 Amazon storefronts thrash their one shared account/server-side location. Serial
> gives each platform full resources + clean store re-resolution, and the Amazon trio runs
> consecutively so it can never overlap. A full sweep is **~2h25m** (blinkit alone
> ~69 min); the two windows are 3h apart (12:00 + 15:00), which still has the headroom —
> the morning chain finishes ~11:06, before its 12:00 barrier. `run_all.sh` holds the
> **authoritative** live-platform list and runs them in this order: ,
> flipkart-minutes, flipkart, zepto, bigbasket, amazon, amazon-fresh, amazon-now, **blinkit
> last**. Each `run.sh`'s git-push is `flock`-serialized (`.gitpush.lock`). Preview the cron
> block via `./setup_cron.sh --print` (or `DRY_RUN=1`); the script is idempotent (rewrites
> only `# ecom-intel` lines) and sets the timezone (`timedatectl set-timezone
> Asia/Kolkata`). **amazon-now is in the serial sweep** but never co-runs with amazon-fresh
> (the serial loop guarantees this by construction).

Auto-heal + self-heal: each scrape is re-evaluated inline by `tools/guardian.py --heal`
(quarantine + bounded re-run + owner alert on BROKEN), and the legacy `tools/selfheal.sh`
backstop runs at the end of the sweep on review-verdict / stale / row-collapse signals. A
recovery can also invoke Claude Code — diagnose, safe-fix, re-run, confirm, commit; if it
can't be safely fixed (captcha / IP block / login wall) it logs a diagnosis and stops. None
ever puts an LLM in the scrape loop.

```bash
./setup_cron.sh --print   # preview the cron block (does NOT install)
./setup_cron.sh           # (re)install cron jobs — safe to re-run, idempotent
./healthcheck.sh          # run the self-heal sweep manually
crontab -l                # inspect what's actually installed
```

---

## Restore-after-wipe runbook

`git` is the backup. After any VPS wipe, restore the whole system with:

```bash
# 1. Get the code
git clone https://github.com/daman8271/ecom-intel.git /opt/ecom-intel
cd /opt/ecom-intel

# 2. Per-platform deps — Node packages + the Chromium browser binary
for p in blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh amazon-now; do
  ( cd "platforms/$p" && npm install && npx playwright install chromium )
done
# (also: sudo npx playwright install-deps  — system libs for headless Chromium)

# 3. Recreate secrets (NOT in git — see below)
cat > secrets.env <<'EOF'
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
chmod 600 secrets.env

# 3b. Amazon Fresh/Now need a logged-in session (NOT in git):
#     export amazon.in cookies on a clean IP (Cookie-Editor) and import them —
#     node platforms/amazon-now/import_cookies.js   (writes the shared storageState;
#     amazon-fresh.storageState.json is a symlink to it). Valid ~1 year.

# 4. Install cron (sets TZ to Asia/Kolkata, schedules runs + healthcheck)
./setup_cron.sh

# 5. Smoke-test one platform
./run.sh blinkit
```

**Prerequisites on a fresh box:** Node (tested on **v22**), Python 3 with
**openpyxl** (`pip3 install openpyxl`), `git`, `curl`, and `claude` (Claude Code CLI)
on `PATH` for self-heal. `secrets.env` holds the Telegram credentials and is
**gitignored** — recreate it by hand.

### ⚠️ THE HARD RULE — never reinstall Hermes via the Hostinger catalog

On this VPS, reinstalling **Hermes** through Hostinger's app catalog triggers a
**full OS recreate that WIPES THE DISK.** Do not do it. If something breaks at the
OS level, fix it in place. **This git repo is the only backup** — keep it pushed,
and restore via the runbook above, never via the Hostinger catalog.

---

## Repository layout

```
ecom-intel/
├── README.md              # this file
├── CLAUDE.md              # operator quick-reference (auto-loads in Claude Code)
├── REPORT.md              # platform-coverage map (9 in the serial cron sweep;  403-blocked)
├── run.sh                 # ./run.sh <p> — scrape → Excel → predict → review → vault → telegram → push
├── run_all.sh             # one cron sweep: scrape all 8 live platforms SERIALLY (~2h;  removed 2026-06-06) → per-scrape guardian auto-heal → self-heal
├── healthcheck.sh         # self-heal: detect broken runs → Claude Code safe repair
├── setup_cron.sh          # (re)install cron (idempotent: 12:00+15:00 deadline sweeps + 18:00 guardian deep-dive, IST), set timezone
├── secrets.env            # Telegram creds (gitignored — recreate after wipe)
├── .gitignore             # node_modules/, output/, logs/, result.json, *.xlsx, secrets.env
│
├── tools/                 # cross-platform pipeline steps (all wired into run.sh)
│   ├── predict.py         # appends a "Predictions" sheet to the workbook from data/ history
│   ├── review.py          # result.json → reviews/<run>.json verdict (deterministic + optional Haiku); hardened geo/block/per-litre/dup checks
│   ├── guardian.py        # auto-heal: review.py + independent 11-bug-class deep-check → quarantine + bounded self-heal + alert (inline per scrape)
│   ├── guardian_daily.sh  # 18:00 read-only 11-class deep-dive → health report + NEW-bug-class alert
│   ├── selfheal.sh        # review/stale/collapse → re-run + escalate to Telegram (legacy backstop)
│   ├── vault_note.py      # per-run Obsidian note + append data/<p>/history.csv
│   ├── vault_rollup.py    # (re)build daily/weekly/monthly rollup notes
│   └── proxy.js           # residential-proxy helper (see docs/PROXY.md)
│
├── platforms/
│   ├── blinkit/                  # ✅ LIVE — proven reference implementation
│   │   ├── SKILL.md              # the scraping recipe: selectors, location trick, quirks
│   │   ├── scrape.js             # Playwright scraper → result.json (deterministic, no LLM)
│   │   ├── build_excel.py        # result.json → 6-sheet branded Excel
│   │   ├── pincodes.json         # 332 store coords covering 798 pincodes
│   │   ├── package.json          # playwright dep
│   │   └── package-lock.json     # pinned for restore-after-wipe
│   ├── /                # ⚠️ BLOCKED — stealth POST to search API (offset-paginated); DC IP 403'd again → needs proxy/login
│   ├── zepto/                    # ✅ LIVE — quick-comm, BFF API gateway (no proxy)
│   ├── flipkart-minutes/         # ✅ LIVE — quick-comm, HYPERLOCAL store, GPS location
│   ├── flipkart/                 # ✅ LIVE — marketplace, national pricing
│   ├── amazon/                   # ✅ LIVE — marketplace, interstitial bypass, 314 ASINs (guest, no account location)
│   ├── amazon-fresh/             # ✅ LIVE — logged-in (cookie transplant), i=freshstore raw POST+HTML; ~63 SKUs, ~13k rows; in cron
│   ├── bigbasket/                # ✅ LIVE — stealth browser past Akamai + in-page listing-svc API; NATIONAL pricing, ~27 SKUs, "All India"; in cron
│   └── amazon-now/               # ✅ LIVE — genuine Now (scrape.ctnow.js, almBrandId=ctnow); in the serial sweep (never co-runs with amazon-fresh); PLAN.md
│
├── output/                # generated Excel (gitignored)
├── logs/                  # per-run + cron + telegram + self-heal logs (gitignored)
│
├── reviews/               # per-run automated review verdicts (<platform>-<RUN_ID>.json)
├── baselines/             # rolling expected per-platform stats (collapse detection)
├── vault/                 # Obsidian-style Markdown memory
│   ├── VAULT-SPEC.md      # the vault design + Obsidian conventions (read before editing generators)
│   ├── runs/<p>/          # one note per run
│   ├── platforms/         # per-platform hub/MOC notes
│   └── daily/ weekly/ monthly/   # time-rollup notes (run → daily → weekly → monthly)
├── data/<platform>/       # append-only history.csv — the future model's training table
└── docs/
    ├── ARCHITECTURE.md       # design deep-dive
    ├── PROXY.md              # residential-proxy setup (owned by another agent)
    └── DESKTOP-OBSIDIAN.md   # opening the vault/ knowledge graph in Obsidian desktop
```

> Every platform folder is **self-contained** and follows the same shape, so adding
> a platform is "copy `blinkit/`, adapt the URL + location mechanism + card
> selectors, keep the `result.json` row shape identical." Full recipe in each
> `platforms/<p>/SKILL.md` and in [`CLAUDE.md`](CLAUDE.md).
