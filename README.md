# ecom-intel — Jivo multi-platform price intelligence

A deterministic price- and stock-intelligence pipeline for the **Jivo** brand. It
tracks Jivo SKU prices, MRP, discount %, per-litre cost and in-stock status across
India's quick-commerce apps and marketplaces — covering the **top-20 cities (~40
pincodes)** — and emits a clean **6-sheet Excel report per platform** plus an
**Obsidian-style Markdown "memory vault"**. Runs unattended on a Hostinger VPS via
**cron, multiple times a day**, with an automated self-heal and Telegram delivery.
Built and pitched to Jivo's head of e-commerce.

> Companion docs: [`CLAUDE.md`](CLAUDE.md) (operator quick-reference, auto-loads in
> Claude Code) · [`REPORT.md`](REPORT.md) (platform-coverage map) ·
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (design deep-dive).

---

## The one architecture rule: ZERO LLM in the scrape loop

**Scraping is 100% deterministic Node + Playwright.** No language model is ever
called inside the per-pincode scrape loop. The only place an LLM is allowed is a
**cheap, end-of-run review** and the **narrative reports** — never in the hot path.

**Why this is non-negotiable — cost.** A run touches ~40 pincodes × N platforms ×
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
| **Blinkit** | quick-comm | ✅ LIVE | 27–28/40 pincodes carry Jivo | ~8 | proven; `localStorage` location override, no login |
| **Flipkart Minutes** | quick-comm | ✅ LIVE | 26/40 pincodes carry Jivo | ~10 | `HYPERLOCAL` store; GPS "use my location" click |
| **Flipkart** | marketplace | ✅ LIVE | national | ~61 | national pricing → 1 row/SKU, tagged "All India" |
| **Amazon** | marketplace | ✅ LIVE | national | ~163 | richest catalog; requires interstitial bypass |
| **Zepto** | quick-comm | ⛔ BLOCKED | — | — | CloudFront **403** on datacenter IP → needs **residential proxy** |
| **Amazon Now** | quick-comm | 🔒 GATED | — | — | reachable but **location/login-gated** → needs Amazon OTP login |

- **Marketplaces (Flipkart / Amazon)** price nationally, so we scrape the catalog
  once and tag rows "All India" rather than looping 40 pincodes. Their value is
  **catalog breadth + price/MRP/discount** (Amazon lists ~163 Jivo SKUs vs ~8–10 on
  quick-comm). That's why their Excel city-matrix is a single column *by design*.
- **Zepto** is staged to proxy: `platforms/zepto/scrape.js` has a 403 guard and
  GPS-based location; add `proxy:{...}` and re-run. See `platforms/zepto/BLOCKED.md`.
- **Amazon Now** needs a logged-in session with saved addresses (one-time OTP). See
  `platforms/amazon-now/BLOCKED.md`.

---

## How to run

```bash
./run.sh <platform>     # blinkit | flipkart-minutes | flipkart | amazon
                        # (zepto | amazon-now are staged/blocked — see above)
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
| `tools/` | Cross-platform pipeline steps: `review.py`, `vault_note.py`, `vault_rollup.py`, `selfheal.sh`, `proxy.js` | tracked |

---

## The pipeline

Each `./run.sh <platform>` executes this chain. Most steps now exist as code; the
status column reflects how far the wiring has landed (this repo is being built by
several agents in parallel — the orchestrator does the final `run.sh` wiring + cron
swap, so verify the marked items before relying on them).

```
scrape.js (Node+Playwright)         IN run.sh    — deterministic, no LLM → result.json
   → build_excel.py (openpyxl)      IN run.sh    — result.json → 6-sheet Excel
   → tools/review.py                BUILT*       — sanity-check run, write reviews/<run>.json
   → tools/selfheal.sh              BUILT*       — heal if verdict BROKEN/SUSPECT or collapse
   → tools/vault_note.py            BUILT*       — write Obsidian run note + append data/ CSV
   → Telegram delivery              IN run.sh    — deterministic summary + Excel to the bot
   → git push                       (orchestrator) — code + vault/ + data/ committed
```

`*BUILT` = the tool exists and is self-contained, but is **not yet wired into
`run.sh`** — the orchestrator inserts these steps. `healthcheck.sh` already invokes
self-heal on its own cron entry today; `tools/selfheal.sh` is the richer
review-aware successor.

What is **wired into `run.sh` today**:

1. **Scrape** — `platforms/<p>/scrape.js` drives Playwright, sets the per-pincode
   delivery location, extracts Jivo product cards, writes `result.json` as
   `{summary, perPin, allRows}`. Pure deterministic JS.
2. **Build Excel** — `platforms/<p>/build_excel.py` (openpyxl) turns `result.json`
   into a branded **6-sheet** workbook: *Summary · Master Data · Pricing Matrix ·
   Stock Status · Discount Analysis · Coverage & Gaps*. Platform name is derived
   from the folder, so the script is identical across platforms.
3. **Telegram delivery** — `run.sh` builds a short **Markdown summary
   deterministically from `result.json`** (cheapest in-stock SKU by ₹/L, top
   discount, coverage) — *no LLM* — and sends it plus the Excel to the bot. This
   step is best-effort and can never fail the run (wrapped, logged to
   `logs/telegram.log`).
4. **Self-heal** — `healthcheck.sh` (separate cron entry) checks each live
   platform's latest `result.json`: if `total_rows < 20` or the file is `> 15h`
   old, it invokes **Claude Code** (`claude -p ...`) to read the SKILL + scraper,
   re-run it, and — only if it's a safe selector/parsing fix — repair, re-run,
   confirm, then commit + push. If it can't be safely fixed (captcha / IP block /
   login wall) it writes `logs/<p>-DIAGNOSIS.md` and stops. **It is explicitly
   instructed to never put an LLM inside the scrape loop.**

What is **built but not yet wired into `run.sh`** (parallel work — verify the wiring):

- **Automated review** — `tools/review.py <platform> <RUN_ID>` runs **free
  deterministic** sanity checks over the finished `result.json` (row count vs
  baseline, implausible prices, coverage drops, schema drift) and writes a verdict
  to `reviews/<platform>-<RUN_ID>.json`; it updates `baselines/<platform>.json` on
  OK runs. An optional single tiny **Claude Haiku** call is the *only* LLM touch and
  is failure-proof (never crashes the run, never enters the scrape loop). Exit code:
  0 = OK/SUSPECT, 2 = BROKEN.
- **Self-heal** — `tools/selfheal.sh` heals on three signals (review verdict
  BROKEN/SUSPECT · stale/missing result · row collapse vs baseline), re-runs the
  platform once under a lock, and escalates to Telegram if still broken. It is the
  review-aware successor to `healthcheck.sh`.
- **Vault note + history** — `tools/vault_note.py <platform> <RUN_ID>` writes the
  Obsidian run note, upserts the platform hub + daily note, and appends to
  `data/<platform>/history.csv`. `tools/vault_rollup.py <daily|weekly|monthly>`
  rebuilds the time-rollups. Both are stdlib-only, deterministic, **no LLM**.

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

**Schedule that `setup_cron.sh` installs** — **3× per day, IST**, with each platform
staggered a few minutes so four Chromium instances don't launch the same second:

| Window (IST) | Jobs (in order) |
|---|---|
| **09:00–09:12** | blinkit `:00` · flipkart-minutes `:04` · flipkart `:08` · amazon `:12` |
| **09:30** | self-heal sweep (after the batch finishes) |
| **12:00–12:12** | same staggered batch |
| **12:30** | self-heal sweep |
| **16:00–16:12** | same staggered batch |
| **16:30** | self-heal sweep |

> **Note on the live crontab:** `setup_cron.sh` was updated to this **3×/day
> (09/12/16)** cadence, but the *currently installed* crontab may still be the older
> **2×/day (09:00 & 19:00)** — the **orchestrator applies the new crontab after
> end-to-end testing**. Preview without installing via `./setup_cron.sh --print`
> (or `DRY_RUN=1`). The script is idempotent (rewrites only `# ecom-intel` lines)
> and sets the timezone (`timedatectl set-timezone Asia/Kolkata`).

Self-heal: a run that returns too few rows / is stale / fails its review verdict
triggers a single Claude Code (or `tools/selfheal.sh`) recovery — diagnose, safe-fix,
re-run, confirm, commit; if it can't be safely fixed (captcha / IP block / login
wall) it logs a diagnosis and stops. It is forbidden from ever putting an LLM in the
scrape loop.

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
for p in blinkit flipkart-minutes flipkart amazon; do
  ( cd "platforms/$p" && npm install && npx playwright install chromium )
done
# (also: sudo npx playwright install-deps  — system libs for headless Chromium)

# 3. Recreate secrets (NOT in git — see below)
cat > secrets.env <<'EOF'
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
chmod 600 secrets.env

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
├── REPORT.md              # platform-coverage map (4 live, Zepto blocked, Amazon Now gated)
├── run.sh                 # ./run.sh <platform> — scrape → Excel → Telegram deliver
├── healthcheck.sh         # daily self-heal: detect broken runs → Claude Code repair
├── setup_cron.sh          # (re)install cron jobs (idempotent, 3x/day IST), set timezone
├── secrets.env            # Telegram creds (gitignored — recreate after wipe)
├── .gitignore             # node_modules/, output/, logs/, result.json, *.xlsx, secrets.env
│
├── tools/                 # cross-platform pipeline steps (orchestrator wires into run.sh)
│   ├── review.py          # result.json → reviews/<run>.json verdict (deterministic + optional Haiku)
│   ├── selfheal.sh        # review/stale/collapse → re-run + escalate to Telegram
│   ├── vault_note.py      # per-run Obsidian note + append data/<p>/history.csv
│   ├── vault_rollup.py    # (re)build daily/weekly/monthly rollup notes
│   └── proxy.js           # residential-proxy helper (see docs/PROXY.md)
│
├── platforms/
│   ├── blinkit/                  # ✅ LIVE — proven reference implementation
│   │   ├── SKILL.md              # the scraping recipe: selectors, location trick, quirks
│   │   ├── scrape.js             # Playwright scraper → result.json (deterministic, no LLM)
│   │   ├── build_excel.py        # result.json → 6-sheet branded Excel
│   │   ├── pincodes.json         # 40 pincodes, top-20 cities
│   │   ├── package.json          # playwright dep
│   │   └── package-lock.json     # pinned for restore-after-wipe
│   ├── flipkart-minutes/         # ✅ LIVE — quick-comm, HYPERLOCAL store, GPS location
│   ├── flipkart/                 # ✅ LIVE — marketplace, national pricing
│   ├── amazon/                   # ✅ LIVE — marketplace, interstitial bypass, ~163 SKUs
│   ├── zepto/                    # ⛔ BLOCKED — CloudFront 403; BLOCKED.md + ready-to-proxy scaffold
│   └── amazon-now/               # 🔒 GATED — reachable but login/location-gated; BLOCKED.md
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
    ├── ARCHITECTURE.md    # design deep-dive
    └── PROXY.md           # residential-proxy setup (owned by another agent)
```

> Every platform folder is **self-contained** and follows the same shape, so adding
> a platform is "copy `blinkit/`, adapt the URL + location mechanism + card
> selectors, keep the `result.json` row shape identical." Full recipe in each
> `platforms/<p>/SKILL.md` and in [`CLAUDE.md`](CLAUDE.md).
