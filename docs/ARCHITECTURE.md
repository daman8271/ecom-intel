# Architecture — ecom-intel

Design deep-dive. For operating instructions see the top-level
[`README.md`](../README.md); for the live platform-coverage map see
[`REPORT.md`](../REPORT.md).

> **Status legend used throughout:** **WIRED** = present in `run.sh`/cron and
> running today · **BUILT** = the tool exists and is self-contained but is not yet
> wired into `run.sh` (the orchestrator inserts it) · **DESIGN** = intended only.
> This repo is built by several agents in parallel, so verify BUILT items' wiring
> before relying on the end-to-end flow.

---

## 1. The prime directive: deterministic scraping, ZERO LLM in the loop

The scrape loop is **pure Node + Playwright**. No model call ever happens per
pincode, per product card, or per platform iteration.

**Why (cost).** Each datapoint is one product card in one pincode on one platform,
collected several times a day, indefinitely. The volume is
`platforms × ~40 pincodes × many cards × runs/day`. A deterministic DOM read +
regex parse costs effectively nothing and is byte-for-byte reproducible. Routing
each of those through an LLM would cost **~100×–10,000× more** for output a CSS
selector already produces perfectly — and would add latency, nondeterminism, and a
new failure mode. So the rule is absolute: **selectors and regex in the loop; LLMs
only at the edges.**

**Where the LLM is allowed (the edges only):**

| Use | Stage | Status |
|---|---|---|
| **Self-heal** — diagnose a broken scraper and, if safe, repair it | after a run, via `healthcheck.sh` (and `tools/selfheal.sh`) | WIRED (healthcheck) / BUILT (selfheal.sh) |
| **Automated review** — single *optional* tiny Haiku call on the finished `result.json` | end of run, before delivery, via `tools/review.py` | BUILT |
| **Narrative / vault notes** — human-readable rollups | end of run / rollup | deterministic, **no LLM** (`tools/vault_*`) — BUILT |

Note: even the **review** and **vault** steps are LLM-light. `tools/review.py` does
**free deterministic** checks first and only *optionally* makes one tiny Haiku call
when configured (failure-proof, never in the loop); the vault generators
(`tools/vault_note.py`, `tools/vault_rollup.py`) are **stdlib-only, no LLM at all**.
Even the Telegram summary that ships with each run is built **deterministically in
Python from `result.json`** (cheapest in-stock SKU by ₹/L, top discount, coverage)
— there is no model in the delivery path either.

---

## 2. Per-platform module contract

Every platform is a self-contained folder under `platforms/<name>/` with the same
five-file shape:

```
platforms/<name>/
├── SKILL.md           # the scraping recipe: site, location mechanism, selectors, quirks
├── scrape.js          # Playwright scraper → result.json   (deterministic)
├── build_excel.py     # result.json → 6-sheet Excel         (platform-agnostic)
├── pincodes.json      # 40 pincodes across the top-20 cities
└── package.json/-lock # pinned playwright dep
```

The **contract that makes this scale** is a fixed output shape. Every scraper
writes `result.json` as:

```jsonc
{
  "summary": {
    "pincodes_total":     40,
    "pincodes_with_jivo": 27,
    "total_rows":         125,
    "unique_skus":        8,
    "wall_s":             99,
    "captured_at":        "2026-05-21T08:47:42.124Z"   // UTC ISO
  },
  "perPin":  [ { "city", "pincode", "locality", "store_name", "rows": [ ... ] } ],
  "allRows": [ /* every row, flattened */ ]
}
```

Each **row** carries:

```
city · pincode · locality · store_id · store_name · sku_raw · canonical ·
pack · vol_ml · sale · mrp · discount_pct · per_litre · eta_min · in_stock
```

Because the shape is identical across platforms, `build_excel.py` is the **same
script everywhere** — it derives the platform name from the folder
(`os.path.basename(os.getcwd())`). Adding a platform never touches the reporting
code.

### Adding a platform (the workflow)

1. `cp -r platforms/blinkit platforms/<new>` and read `platforms/<new>/SKILL.md`.
2. Adapt **only** `scrape.js`: the base URL, the location-setting mechanism, the
   product-card selectors. Keep the `result.json` row shape identical.
3. `./run.sh <new>` and watch the log — this **is** the "does it catch us"
   datacenter-IP test.
4. **0 rows / captcha / 403 / 503** → the platform blocks the datacenter IP →
   document it in a `BLOCKED.md` and route through a residential proxy (see
   `docs/PROXY.md`, owned by another agent).
5. When live, add it to the `PLATFORMS=` lists in `setup_cron.sh` **and**
   `healthcheck.sh` (keep them in sync), then commit + push.

---

## 3. Location strategy differs by platform type

This is the single biggest source of per-platform code difference:

- **Quick-commerce (Blinkit, Flipkart Minutes, Zepto, Amazon Now)** is *hyperlocal*
  — price/stock depend on the dark store serving a pincode, so we **loop all ~40
  pincodes** and set the delivery location each time:
  - **Blinkit** — write `localStorage.location` directly, no login. (Proven.)
  - **Flipkart Minutes** — `HYPERLOCAL` marketplace; drive the GPS "use my
    location" click.
  - **Zepto** — GPS geolocation; **blocked at CloudFront before the SPA loads**.
  - **Amazon Now** — ignores GPS, resolves location from its GLOW widget; the
    headless pincode modal is too fragile to drive across 40 pincodes → needs a
    logged-in session with saved addresses.
- **Marketplaces (Flipkart, Amazon)** price **nationally** — the same listing costs
  the same everywhere — so we **scrape the catalog once**, tag rows "All India",
  and skip the pincode loop. Their value is **catalog breadth + price/MRP/discount**
  (Amazon ~163 Jivo SKUs vs ~8–10 on quick-comm). This is why their Excel
  city-matrix is a single column **by design**, not a bug.

Amazon additionally needs an **interstitial bypass**: a datacenter IP gets HTTP 202
+ a "Continue shopping" button (and raw `/s?k=` hits get 503 throttles); the scraper
clicks through it before searching.

---

## 4. The report: 6-sheet Excel

`build_excel.py` (openpyxl) produces a Jivo-branded workbook
`Jivo-<Platform>-Live-Report-<date>.xlsx`:

1. **Summary** — title, capture stamp, KPI cards (unique SKUs, pincodes-with-Jivo,
   datapoints, cities with zero Jivo), cheapest-pincode-per-SKU table, and a
   **whitespace** callout listing cities with *zero* Jivo (distribution-gap intel).
2. **Master Data** — every row, auto-filtered, frozen header; out-of-stock cells
   shaded red, high discounts shaded green.
3. **Pricing Matrix** — avg sale price per SKU × city, green→red color scale.
4. **Stock Status** — % in-stock per SKU × city (green/yellow/red).
5. **Discount Analysis** — avg discount % per SKU × city (higher = greener).
6. **Coverage & Gaps** — per-pincode store assignment and Jivo-SKU count
   (zero = red).

For marketplaces the city dimension collapses to a single "All India" column — the
matrices still render, the breadth lives in Master Data.

---

## 5. Pipeline & orchestration

```
cron (setup_cron.sh — 3x/day staggered, IST)
  └─ run.sh <platform>
       ├─ node scrape.js              WIRED  → result.json   (deterministic, no LLM)
       ├─ python3 build_excel.py      WIRED  → Jivo-*.xlsx → output/
       ├─ tools/review.py             BUILT  → reviews/<run>.json verdict (exit 2 = BROKEN)
       ├─ tools/vault_note.py         BUILT  → vault run note + append data/<p>/history.csv
       └─ Telegram delivery           WIRED  deterministic summary + Excel (best-effort)

cron (separate :30 entry per window)
  └─ healthcheck.sh                   WIRED  self-heal sweep over live platforms
       └─ if rows<20 or stale → claude -p (diagnose → safe-fix → re-run → commit/push,
                                            else write logs/<p>-DIAGNOSIS.md and stop)
  └─ tools/selfheal.sh                BUILT  review-aware successor (3 signals, re-run + Telegram)
```

> The middle two steps (`review.py`, `vault_note.py`) and `selfheal.sh` are **BUILT
> but not yet wired into `run.sh`** — the orchestrator inserts them. `healthcheck.sh`
> already runs self-heal on its own cron entry today.

- **Telegram delivery is best-effort** — it runs in a subshell with `errexit` off
  and a trailing `|| true`, logging to `logs/telegram.log`, so a network/API hiccup
  can never fail the scrape.
- **`tools/review.py`** runs free deterministic checks (rows vs `baselines/<p>.json`,
  implausible prices, coverage drop, schema drift), writes
  `reviews/<platform>-<RUN_ID>.json`, updates the baseline on OK runs, and exits 2 on
  BROKEN so `run.sh`/self-heal can react. The optional single Haiku call is the only
  LLM touch and is failure-proof.
- **Self-heal signals** — `healthcheck.sh` thresholds: `MIN_ROWS=20`, `MAX_AGE_H=15`.
  `tools/selfheal.sh` adds two more signals (review **verdict** BROKEN/SUSPECT, and
  row **collapse** vs baseline), re-runs once under a per-platform lock, and escalates
  to Telegram if still broken. Both are forbidden from putting an LLM in the scrape
  loop and from editing code when the cause is a captcha / IP block / login wall.

---

## 6. The memory vault (DESIGN)

Goal: a **queryable history**, not just today's spreadsheet — two linked layers.
The authoritative design (Obsidian conventions, wikilink/MOC topology, CSV schema)
lives in [`../vault/VAULT-SPEC.md`](../vault/VAULT-SPEC.md). Summary:

- **`vault/` (human / Obsidian).** Linked Markdown forming a knowledge graph:
  - `vault/runs/<platform>/<platform>-<RUN_ID>.md` — one note per run; basenames are
    **globally unique** because Obsidian resolves wikilinks by basename.
  - `vault/platforms/<platform>.md` — per-platform hub/MOC linking every run.
  - `vault/daily/`, `vault/weekly/`, `vault/monthly/` — time-rollup MOCs along the
    spine `run → daily → weekly → monthly` (each links up; rollups link down). Week
    id is ISO-8601 (`%G-W%V`). All structural relationships are **body wikilinks**
    (graph edges work on every Obsidian version, no plugins); frontmatter is flat
    metadata only; tags are facets.
- **`data/<platform>/history.csv` (machine).** Append-only, one row per
  `(run, SKU, location)`:
  `run_id,date_ist,platform,canonical_sku,city,pincode,price,mrp,discount_pct,in_stock`.
  National-shape platforms emit `city="All India", pincode="-"`. Idempotent within a
  run (de-dup key `run_id,platform,canonical_sku,pincode`); deterministic row sort
  for clean git diffs. This is the **future model's training table**.

Humans browse `vault/`; a model reads `data/`. Both are generated by
`tools/vault_note.py` (per run) and `tools/vault_rollup.py` (rollups) — Python 3
stdlib only, deterministic, **no LLM**, safe inside the cron loop. The directories
now exist in the repo and should be tracked in git as part of the backup.

---

## 7. Schedule

| Item | `setup_cron.sh` installs | Currently-installed crontab (pending swap) |
|---|---|---|
| Scrape cadence | **3×/day — 09:00 / 12:00 / 16:00 IST** | may still be **2×/day — 09:00 & 19:00 IST** |
| Per-platform stagger | blinkit `:00` · flipkart-minutes `:04` · flipkart `:08` · amazon `:12` | n/a |
| Self-heal | `:30` of each window (after the batch) | 09:30 daily |
| Timezone | `Asia/Kolkata` (set by `setup_cron.sh`) | — |

`setup_cron.sh` now targets **3×/day** with platforms staggered minutes apart so four
Chromium instances never launch the same second. It is idempotent (rewrites only
`# ecom-intel` lines) and supports `--print` / `DRY_RUN=1` to preview without
installing. The **orchestrator applies the new crontab after end-to-end testing**, so
the live crontab may lag the script.

---

## 8. Backup & disaster recovery

- **`git` is the only backup.** Code restores via the runbook in
  [`README.md`](../README.md#restore-after-wipe-runbook): clone → per-platform
  `npm install` + `npx playwright install chromium` → recreate `secrets.env` →
  `./setup_cron.sh`.
- **Hard rule:** never reinstall **Hermes** via the Hostinger catalog on this VPS —
  it triggers a full OS recreate that wipes the disk. Fix the box in place; restore
  from git, never from the catalog.
- **Gitignored / not in backup:** `node_modules/`, `output/`, `logs/`,
  `**/result.json`, `**/Jivo-*.xlsx`, `*.log`, `secrets.env`. Secrets must be
  recreated by hand after a wipe.

---

## Open items for the orchestrator to finalize

The tools below now **exist** (parallel work landed); the remaining job is mostly
**wiring + verification**, which the orchestrator owns:

1. **Wire the pipeline into `run.sh`** — insert, after `build_excel.py` and before
   Telegram delivery: `tools/review.py <platform> <RUN_ID>` → (on non-OK)
   `tools/selfheal.sh` → `tools/vault_note.py <platform> <RUN_ID>`. Confirm none of
   them enter the scrape loop and that review's exit code is honored.
2. **Verify review/baseline behavior** — first runs bootstrap `baselines/`; confirm
   collapse detection and the optional Haiku path are failure-proof and off by
   default unless model access is configured.
3. **Verify vault + history generation** — run `tools/vault_note.py` and
   `tools/vault_rollup.py` against a real `result.json`; confirm idempotent
   regeneration and that `data/<p>/history.csv` de-dups per run.
4. **git-track vault/data/reviews/baselines** — ensure these are committed (and not
   caught by the broad `*.xlsx`/`result.json` `.gitignore` patterns) so they're part
   of the backup; update `.gitignore` accordingly.
5. **Apply the 3×/day crontab** — `setup_cron.sh` already targets 09/12/16 IST
   staggered; install it after E2E testing and confirm the live crontab matches.
6. **`docs/PROXY.md`** — owned by another agent; this doc only references it. Also
   note `tools/proxy.js` exists for routing Playwright through a residential proxy
   (primarily for Zepto / Amazon hardening).
