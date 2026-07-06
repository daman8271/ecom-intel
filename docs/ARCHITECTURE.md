# Architecture — ecom-intel

Design deep-dive. For operating instructions see the top-level
[`README.md`](../README.md); for the live platform-coverage map see
[`REPORT.md`](../REPORT.md).

> **Status (updated 2026-07-06 — now 1×/day):** the full pipeline is **WIRED and running on cron** —
> `scrape → build_excel → predict → review → vault/history → telegram → commit/push`
> all execute inside `run.sh` for VPS-hosted platforms, and `run_all.sh` drives a
> **SERIAL** sweep (one platform at a time; ~2h chain after 's 2026-06-06 removal).
> Off-box/team collectors feed vetted outputs where required:
> Blinkit runs on the Mac Pro residential session at **03:45 IST** with authenticated
> Blinkit state, while BigBasket pincode runs at **03:00 IST** through the
> `team_run_pincode.sh` VPS + Mac Pro + KVM1 runner and writes private/direct-only
> output. The sweep has a
> **per-scrape auto-heal guardian** and a self-heal backstop. Cron is **DEADLINE-ALIGNED**
> (owner requirement 2026-06-06): `tools/cron/deadline_sweep.sh` fires **early in the small
> hours** (predicts its lead and sleeps so the batch lands at 10:00 — cut from 2×/day to one
> sweep on 2026-06-28), predicts the chain runtime from per-platform
> duration history, sleeps so the chain
> **finishes at the slot (10:00 AM IST)**, spools each verdict-gated report
> (`DEFER_DELIVERY=1` → `output/.batch/<sweep>/`), and `tools/cron/send_batch.py` holds a
> barrier until the deadline, then ships ONE batch (BROKEN-run owner alerts still immediate;
> any spool failure falls back to immediate send). Plus an **18:00 guardian deep-dive**.
> Telegram delivery is **verdict-gated** (only OK ships). The "BUILT but not yet wired"
> caveats from earlier drafts are obsolete.

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
| **Auto-heal guardian** — combine review.py + an independent 11-bug-class deep-check; quarantine + bounded self-heal + alert | inline per scrape in `run_all.sh` → `tools/guardian.py --heal`; daily deep-dive `tools/guardian_daily.sh` | WIRED (2026-06-05) |
| **Self-heal backstop** — diagnose a broken scraper and, if safe, repair it | after the serial sweep, via `run_all.sh` → `tools/selfheal.sh` (+ `healthcheck.sh`) | WIRED |
| **Automated review** — deterministic checks + single *optional* tiny Haiku call on the finished `result.json` | in `run.sh`, after build/predict, via `tools/review.py` | WIRED |
| **Amazon canonical auto-heal** — adjudicate truncated-title stub SKUs vs real products; merge identity-only (never prices) & re-review so a `shared_price_dup`-only SUSPECT can flip OK | in `run.sh`, after review (Amazon only), via `tools/autoheal_amazon.py` (`claude -p`, model fallback chain) | WIRED (2026-06-13) |
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
  - **Blinkit** — Mac Pro/residential Playwright collector. It must hydrate an
    authenticated Blinkit session (`localStorage.auth`, `localStorage.deviceId`, and
    `gr_1_accessToken` / `gr_1_deviceId` cookies) before writing
    `localStorage.location`; anonymous/headless Blinkit can return false Out of Stock
    for live SKUs. Production runs with `BLINKIT_REQUIRE_AUTH=1` using
    `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json` on the Mac collector
    or `/opt/ecom-intel/secrets/blinkit-auth-state.json` for VPS emergency/manual
    shards. Summaries must carry `auth_session` and `auth_required`; ingest defaults
    to `BLINKIT_REQUIRE_AUTH_DROP=1` and rejects unauthenticated drops.
  - **** — stealth POST to its public search API `/api//search/v2`
    (now **offset-paginated** for the full Jivo catalogue, c0bc409), location in the
    request body — no page render. **Currently 403-blocked at the IP level (0 rows,
    2026-06-05)**; the 403 fail-safe records 0 rows + a marker so review marks it BROKEN
    and nothing ships. Needs a residential proxy or a logged-in  session.
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
the scraper clicks through it before searching. It sets **no account location**; in the
serial sweep it runs consecutively with Amazon Fresh/Now (one at a time), so the three
Amazon storefronts never overlap.

---

## 4. The report: 6-sheet Excel

`build_excel.py` (openpyxl) produces a Jivo-branded workbook
`Jivo-<Platform>-Live-Report-<date>.xlsx`:

1. **Summary** — title, capture stamp, KPI cards (unique SKUs, pincodes-with-Jivo,
   datapoints, cities with zero Jivo), cheapest-pincode-per-SKU table, and a
   **whitespace** callout listing cities with *zero* Jivo (distribution-gap intel).
2. **Master Data** — every row, auto-filtered, frozen header; out-of-stock cells
   shaded red, high discounts shaded green. BigBasket's variant adds a **SKU Code**
   column (the platform product id from `sku_id`, BB's ASIN-equivalent) after the
   SKU name — cross-checkable against `platforms/bigbasket/bb_sku_master.json`.
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
cron (IST: fire early → slot 10:00 AM; + 03:00 BigBasket pincode team runner; + 03:45 Blinkit Mac collector; 18:00 guardian deep-dive)
  ├─ BigBasket team runner at 03:00
  │    └─ platforms/bigbasket/team_run_pincode.sh run
  │       ├─ shards pincodes_jivo.json across VPS + Mac Pro + KVM1 (default 5:4:1)
  │       ├─ each worker runs scrape_pincode_browser.js in tmux with logged-in cookies
  │       ├─ merge_team_pincode.py → result_pincode.json
  │       └─ build_excel_pincode.py → output/private-no-group/ + direct-only send
  ├─ Mac Pro launchd com.danny.blinkit-mac-to-vps
  │    └─ /Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh
  │       ├─ BLINKIT_REQUIRE_AUTH=1 with /Users/danny./VPS-Migration/secrets/blinkit-auth-state.json
  │       └─ VPS ingest with BLINKIT_REQUIRE_AUTH_DROP=1 → build/review/deliver
  └─ tools/cron/deadline_sweep.sh 10:00 — predict chain runtime (durations.jsonl p90),
  │    sleep to T−lead, export DEFER_DELIVERY=1 SWEEP_ID SWEEP_DEADLINE
  └─ run_all.sh — scrape VPS-hosted LIVE platforms SERIALLY ( removed 2026-06-06; ~2h chain)
       ├─ tools/cron/record_duration.sh <p> <secs>  (per platform — self-learning ledger)
       ├─ tools/cron/send_batch.py — barrier: sleep to deadline, deliver ALL reports as ONE batch
       └─ run.sh <platform>   (per platform, all steps WIRED)
       │    ├─ node scrape.js             → result.json   (deterministic, no LLM)
       │    ├─ python3 build_excel.py     → Jivo-*.xlsx → output/
       │    ├─ tools/predict.py           → append "Predictions" sheet to the workbook
       │    ├─ tools/review.py            → reviews/<run>.json verdict (exit 2 = BROKEN)
       │    ├─ tools/autoheal_amazon.py   → Amazon only: shared_price_dup-only SUSPECT → Claude merges stub SKUs (identity-only) → re-review → may flip OK
       │    ├─ tools/vault_note.py --csv-only → append data/<p>/history.csv
       │    ├─ Telegram delivery          → VERDICT-GATED: only OK ships; else owner alert
       │    └─ git add vault data reviews baselines → commit → push (flock-serialized)
       └─ tools/guardian.py <p> --heal    → auto-heal hook (inline, per scrape):
            review.py + independent 11-bug-class deep-check (worst wins); on BROKEN →
            QUARANTINE (keep last-good, nothing published) + bounded re-run + owner alert
  └─ after the sweep: tools/selfheal.sh   self-heal backstop over live platforms
       └─ on BROKEN verdict / stale / row-collapse → re-run once (shared per-platform lock),
          escalate to Telegram if still broken
  └─ 18:00 daily: tools/guardian_daily.sh  read-only 11-class deep-dive → health report
       + alert on any NEW bug class vs yesterday
```

**Why serial (not parallel):** running all VPS-hosted scrapers at once starved each scraper (CPU/network
contention → thin, partial data the hardened review.py rejects) and made the 3 Amazon
storefronts thrash their one shared account/server-side location. Serial gives each
platform full resources + clean store re-resolution, and the Amazon trio runs
consecutively so it can never overlap. Order: light platforms first, the Amazon trio
consecutive. Blinkit is no longer a VPS serial-sweep member; the full authenticated
collector runs off-box on the Mac Pro residential session and the vetted output enters
the delivery path only after auth/session validation. BigBasket pincode is also outside
the VPS serial sweep: its team runner uses the VPS, Mac Pro, and KVM1 in parallel, then
keeps the pincode workbook private/direct-only while the smaller national workbook can
still enter the normal batch.

> Every step after `scrape.js` is best-effort (`|| true`) and can never fail the run.
> `healthcheck.sh` is the older self-heal variant (`rows<20` / `>15h` stale → `claude -p`
> diagnose → safe selector/parsing fix → re-run → commit/push, else write
> `logs/<p>-DIAGNOSIS.md` and stop); `tools/selfheal.sh` is the review-aware successor
> invoked at the end of each `run_all.sh` sweep. Neither ever puts an LLM in the scrape loop.

- **Telegram delivery is best-effort AND verdict-gated** — it runs in a subshell with
  `errexit` off and a trailing `|| true`, logging to `logs/telegram.log`. Only a clean
  `OK` run ships the report+Excel to stakeholders; a `BROKEN`/`SUSPECT` run is held back
  and the owner gets a short alert instead (4433756).
- **`tools/review.py`** runs free deterministic checks (rows vs `baselines/<p>.json`,
  implausible prices, coverage drop, schema drift), writes
  `reviews/<platform>-<RUN_ID>.json`, updates the baseline **on OK runs only**
  (SUSPECT/BROKEN no longer seed it), and exits 2 on BROKEN so `run.sh`/the guardian can
  react. **Hardened 2026-06-05 (4433756 + 439595e)** with four checks: `geo_consistency`
  (one store_id across >2 cities → BROKEN, default-store contamination), `priced_floor_block`
  (row-padding-on-block + undetected blocks), `per_litre_sanity` (combo-volume per-litre
  inflation + an absolute ₹6000/L oil ceiling), and `shared_price_dup` (cross-sell/fabricated
  prices). The optional single Haiku call is the only LLM touch and is failure-proof.
- **Amazon canonical auto-heal** (`tools/autoheal_amazon.py`, 2026-06-13) is a reactive,
  identity-only repair wired into `run.sh` right after review (Amazon family only). When a
  report is about to be held *solely* on `shared_price_dup`, it wakes Claude (`claude -p`,
  model fallback chain) to adjudicate truncated-title **stub** canonicals vs real products,
  merges each stub into its survivor (rewrites `canonical`/`item` ONLY — **never** a price; a
  priced-multiset tripwire + snapshot rollback enforce it), rebuilds the report, and re-reviews
  so the verdict flips SUSPECT→OK. Fail-safe: Claude unreachable / nothing to merge → stays
  held; one Telegram note per action. Spec
  `docs/superpowers/specs/2026-06-13-amazon-canonical-autoheal-design.md`.
- **Auto-heal guardian** (`tools/guardian.py`, 2026-06-05) is the inline second opinion:
  it CALLS review.py for the shared checks AND runs an independent **11-bug-class deep-check**,
  takes the worst verdict, and on BROKEN quarantines (keeps `result.last-good.json`, nothing
  published), runs bounded self-heal re-runs (cap 2), then alerts the owner. Failure-proof —
  a guardian crash never aborts a sweep. `tools/guardian_daily.sh` is the 18:00 read-only
  11-class deep-dive (health report + NEW-bug-class alert).
- **Self-heal backstop signals** — `healthcheck.sh` thresholds: `MIN_ROWS=20`, `MAX_AGE_H=15`.
  `tools/selfheal.sh` adds two more signals (review **verdict** BROKEN/SUSPECT, and
  row **collapse** vs baseline), re-runs once under the same per-platform `.heal-<p>.lock`
  the guardian uses (so they can never double-heal), and escalates to Telegram if still
  broken. All are forbidden from putting an LLM in the scrape loop and from editing code
  when the cause is a captcha / IP block / login wall.

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
| Scrape cadence | **1 deadline-aligned sweep/day — lands 10:00 AM IST** (cut from 2×/day 2026-06-28) + an **18:00 guardian deep-dive** |
| Driver | one `./run_all.sh` per sweep — scrapes the **7 live platforms SERIALLY** (one at a time, ~2h;  removed 2026-06-06); BigBasket pincode is a separate 03:00 team runner |
| Auto-heal | inline per scrape (`tools/guardian.py --heal`) + the self-heal backstop at the sweep's end (`tools/selfheal.sh`) |
| Timezone | `Asia/Kolkata` (set by `setup_cron.sh`) |

The live crontab is one `run_all.sh` sweep + one `tools/guardian_daily.sh` line
(+ the 03:00 BigBasket pincode team runner; the live line lives in
`tools/cron/doctor.crontab.txt` and the root crontab).
`run_all.sh` runs the platforms **serially** (commit 8ef79d4 — parallel starved the
scrapers and thrashed the shared Amazon account/location) and holds the authoritative
live-platform list; each `run.sh`'s git-push is `flock`-serialized so concurrent commits
(a heal re-run, the post-sweep vault rebuild) don't collide. The script is idempotent
(rewrites only `# ecom-intel` lines) and supports `--print` / `DRY_RUN=1` to preview.
**amazon-now is now in the serial sweep**; the serial loop is what guarantees it never
co-runs with amazon-fresh (Amazon's delivery location is account-global server-side).

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

The end-to-end system is **live in production** (7 platforms on a **serial** cron — one
deadline-aligned sweep daily + an 18:00 guardian deep-dive). The items earlier drafts listed as "open for
the orchestrator" are done:

- ✅ **Pipeline wired into `run.sh`** — `scrape → build_excel → predict → review →
  vault_note (--csv-only) → telegram → commit/push`, every post-scrape step best-effort,
  review's exit code honored, none entering the scrape loop.
- ✅ **Review/baseline** — `baselines/` bootstrap on first runs; collapse detection +
  the optional Haiku path are failure-proof and off unless model access is configured.
- ✅ **Vault + history** — generated each run; `data/<p>/history.csv` de-dups per run;
  rollups rebuilt by `tools/vault_rollup.py`.
- ✅ **git-tracked backup** — `vault/`, `data/`, `reviews/`, `baselines/` are committed
  every run (not caught by the `*.xlsx`/`result.json` ignore patterns).
- ✅ **Crontab applied + deadline mechanism PROVEN live (2026-06-06)** — real deadline batches land at the slot to the second (chain + barrier self-aligning). Cut from 2×/day to a single **10:00 AM** sweep on 2026-06-28 (15:00 sweep + 16:00 mailer retired); the live cron line lives in `tools/cron/doctor.crontab.txt`. Plus the 18:00 `guardian_daily.sh` deep-dive.
- ✅ **Auto-heal guardian** (2026-06-05) — inline per-scrape quarantine + bounded self-heal + owner alert, plus the daily 11-class deep-dive; review.py hardened (geo/block/per-litre/dup) and Telegram verdict-gated.

Remaining / ongoing:

- **`docs/PROXY.md` + `tools/proxy.js`** — proxy is **not bought**; the other platforms
  run without one. ** now WANTS a proxy** — its stealth-POST path is 403-blocked
  again at the IP level (0 rows, 2026-06-05), so it needs a residential Indian IP or a
  logged-in  session. `proxy.js` (the zepto pattern) is wired for exactly this, and
  stays as insurance if Amazon ever escalates to a captcha on the datacenter IP.
- **Amazon cookie freshness** — the Fresh/Now logged-in session relies on transplanted
  cookies (valid ~to May 2027); they must be re-imported on a clean IP if Amazon expires
  the session. Watch for Fresh runs collapsing to 0 rows as the signal.
- **Experimental** — a `tools/whatsapp/` delivery channel is in early development
  (untracked, not wired into `run.sh`).
