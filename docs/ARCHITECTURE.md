# Architecture — ecom-intel

Design deep-dive. For operating instructions see the top-level
[`README.md`](../README.md); for the live platform-coverage map see
[`REPORT.md`](../REPORT.md).

> **Status (2026-05-31):** the full pipeline is now **WIRED and running on cron** —
> `scrape → build_excel → predict → review → vault/history → telegram → commit/push`
> all execute inside `run.sh`, and `run_all.sh` drives a 3×/day parallel sweep of all
> **7 live platforms** with a self-heal pass. The "BUILT but not yet wired / orchestrator
> will insert it later" caveats that earlier drafts of this doc carried are obsolete.

---

## 1. The prime directive: deterministic scraping, ZERO LLM in the loop

The scrape loop is **pure Node + Playwright**. No model call ever happens per
pincode, per product card, or per platform iteration.

**Why (cost).** Each datapoint is one product card in one pincode on one platform,
collected several times a day, indefinitely. The volume is
`platforms × hundreds of pincodes × many cards × runs/day`. A deterministic DOM read +
regex parse costs effectively nothing and is byte-for-byte reproducible. Routing
each of those through an LLM would cost **~100×–10,000× more** for output a CSS
selector already produces perfectly — and would add latency, nondeterminism, and a
new failure mode. So the rule is absolute: **selectors and regex in the loop; LLMs
only at the edges.**

**Where the LLM is allowed (the edges only):**

| Use | Stage | Status |
|---|---|---|
| **Self-heal** — diagnose a broken scraper and, if safe, repair it | after the parallel sweep, via `run_all.sh` → `tools/selfheal.sh` (+ `healthcheck.sh`) | WIRED |
| **Automated review** — single *optional* tiny Haiku call on the finished `result.json` | in `run.sh`, after build/predict, via `tools/review.py` | WIRED |
| **Narrative / vault notes** — human-readable rollups | in `run.sh` / post-sweep rollup | deterministic, **no LLM** (`tools/vault_*`) — WIRED |

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
├── pincodes.json      # the pincode set for this platform (≈332–798 for quick-comm;
│                      #   national marketplaces skip the loop)
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
5. When live, add it to the platform loop in `run_all.sh` (the **authoritative** cron
   list) and keep `setup_cron.sh` / `healthcheck.sh` in sync, then commit + push.

---

## 3. Location strategy differs by platform type

This is the single biggest source of per-platform code difference:

- **Quick-commerce (Blinkit, , Zepto, Flipkart Minutes, Amazon Fresh)** is
  *hyperlocal* — price/stock depend on the dark store serving a pincode, so we **loop
  every pincode** (332–798 depending on platform, scaled up from the original top-20-city
  set) and set the delivery location each time:
  - **Blinkit** — write `localStorage.location` directly, no login. (Proven reference.)
  - **** — stealth POST to its public search API `/api//search/v2`
    (WAF bypass), location in the request body — no page render.
  - **Zepto** — reached via the **`bff-gateway.zeptonow.com` BFF API** directly; the
    CloudFront-fronted website still 403s the datacenter IP, but the app gateway is
    reachable and takes lat/long per request. (The old "blocked at CloudFront" state was
    resolved 2026-05-29.)
  - **Flipkart Minutes** — `HYPERLOCAL` marketplace; drive the GPS "use my location" click.
  - **Amazon Fresh** — logged-in session (cookies transplanted from a clean IP). Per
    pincode it raw-POSTs `glow/address-change` to move the GLOW location, then GETs
    `/s?k=jivo&i=freshstore` as HTML and parses the search cards — no page render. This
    is the logged-in capability that finally made per-pincode Amazon location reliable.
  - **Amazon Now** — same logged-in account/mechanism as Fresh, but **manual-only**:
    Amazon resolves location server-side per account, so Now and Fresh can't run
    concurrently, and Now is a far thinner catalog. Kept off cron.
- **Marketplaces (Flipkart, Amazon)** price **nationally** — the same listing costs
  the same everywhere — so we **scrape the catalog once**, tag rows "All India",
  and skip the pincode loop. Their value is **catalog breadth + price/MRP/discount**
  (Amazon ~163 in-stock Jivo SKUs vs ~8–11 on quick-comm). This is why their Excel
  city-matrix is a single column **by design**, not a bug.

The guest **Amazon** marketplace scraper needs an **interstitial bypass**: a datacenter
IP gets HTTP 202 + a "Continue shopping" button (and raw `/s?k=` hits get 503 throttles);
the scraper clicks through it before searching. It sets **no account location**, so it is
safe to run alongside Amazon Fresh in the parallel sweep.

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

After the workbook is built, **`tools/predict.py` appends a 7th "Predictions" sheet**
computed from `data/<platform>/history.csv` (deterministic, openpyxl + stdlib, no LLM).
**Amazon Fresh** ships a Fresh-specific `build_excel.py` variant that adds a *Now
Serviceability* sheet on top of the standard layout.

---

## 5. Pipeline & orchestration

```
cron (setup_cron.sh — 3x/day, IST: 09:00 / 12:00 / 16:00)
  └─ run_all.sh — scrape all 7 LIVE platforms IN PARALLEL, then self-heal pass
       └─ run.sh <platform>   (per platform, all steps WIRED)
            ├─ node scrape.js             → result.json   (deterministic, no LLM)
            ├─ python3 build_excel.py     → Jivo-*.xlsx → output/
            ├─ tools/predict.py           → append "Predictions" sheet to the workbook
            ├─ tools/review.py            → reviews/<run>.json verdict (exit 2 = BROKEN)
            ├─ tools/vault_note.py --csv-only → append data/<p>/history.csv
            ├─ Telegram delivery          → deterministic summary + Excel (best-effort)
            └─ git add vault data reviews baselines → commit → push (flock-serialized)
       └─ after the sweep: tools/selfheal.sh   self-heal pass over live platforms
            └─ on BROKEN verdict / stale / row-collapse → re-run once (per-platform lock),
               escalate to Telegram if still broken
```

> Every step after `scrape.js` is best-effort (`|| true`) and can never fail the run.
> `healthcheck.sh` is the older self-heal variant (`rows<20` / `>15h` stale → `claude -p`
> diagnose → safe selector/parsing fix → re-run → commit/push, else write
> `logs/<p>-DIAGNOSIS.md` and stop); `tools/selfheal.sh` is the review-aware successor
> invoked at the end of each `run_all.sh` sweep. Neither ever puts an LLM in the scrape loop.

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

## 6. The memory vault (LIVE)

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
`tools/vault_note.py` (per run, called with `--csv-only` from `run.sh` to append history;
notes are (re)built by the rollup) and `tools/vault_rollup.py` (daily/weekly/monthly
rollups) — Python 3 stdlib only, deterministic, **no LLM**, safe inside the cron loop.
`vault/`, `data/`, `reviews/`, and `baselines/` are committed every run (`git add` in
`run.sh`) as part of the backup. To browse the graph in Obsidian desktop, see
[`DESKTOP-OBSIDIAN.md`](DESKTOP-OBSIDIAN.md).

---

## 7. Schedule

| Item | Installed & live (verified via `crontab -l`) |
|---|---|
| Scrape cadence | **3×/day — 09:00 / 12:00 / 16:00 IST** |
| Driver | one `./run_all.sh` per window — scrapes all **7 live platforms in parallel** |
| Self-heal | runs at the **end** of each `run_all.sh` sweep (`tools/selfheal.sh`) |
| Timezone | `Asia/Kolkata` (set by `setup_cron.sh`) |

The live crontab is exactly three `run_all.sh` entries. `run_all.sh` runs the platforms
**in parallel** (the VPS has headroom — ~15 GB RAM / 4 CPU) and holds the authoritative
live-platform list; each `run.sh`'s git-push is `flock`-serialized so concurrent commits
don't collide. `setup_cron.sh` still carries a per-platform stagger/offset block, but it
is a **legacy doc-mirror** — the installed sweep is parallel. The script is idempotent
(rewrites only `# ecom-intel` lines) and supports `--print` / `DRY_RUN=1` to preview.
**amazon-now is intentionally excluded** (manual-only — shares amazon-fresh's account +
server-side location, so the two must never co-run).

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

## Status — what shipped, what's left

The end-to-end system is **live in production** (7 platforms on 3×/day parallel cron).
The items earlier drafts listed as "open for the orchestrator" are done:

- ✅ **Pipeline wired into `run.sh`** — `scrape → build_excel → predict → review →
  vault_note (--csv-only) → telegram → commit/push`, every post-scrape step best-effort,
  review's exit code honored, none entering the scrape loop.
- ✅ **Review/baseline** — `baselines/` bootstrap on first runs; collapse detection +
  the optional Haiku path are failure-proof and off unless model access is configured.
- ✅ **Vault + history** — generated each run; `data/<p>/history.csv` de-dups per run;
  rollups rebuilt by `tools/vault_rollup.py`.
- ✅ **git-tracked backup** — `vault/`, `data/`, `reviews/`, `baselines/` are committed
  every run (not caught by the `*.xlsx`/`result.json` ignore patterns).
- ✅ **3×/day crontab applied** — installed and verified (parallel `run_all.sh`).

Remaining / ongoing:

- **`docs/PROXY.md` + `tools/proxy.js`** — proxy is **not bought and not needed** today
  (all 7 platforms run without one); `proxy.js` stays as insurance if Amazon ever
  escalates to a captcha on the datacenter IP.
- **Amazon cookie freshness** — the Fresh/Now logged-in session relies on transplanted
  cookies (valid ~to May 2027); they must be re-imported on a clean IP if Amazon expires
  the session. Watch for Fresh runs collapsing to 0 rows as the signal.
- **Experimental** — a `tools/whatsapp/` delivery channel is in early development
  (untracked, not wired into `run.sh`).
