# BigBasket — Integration Spec

## Current production contract — 2026-07-06

BigBasket is already integrated. The old sections below are retained as build
history, but the production pincode path is now:

```bash
cd /opt/ecom-intel/platforms/bigbasket
./team_run_pincode.sh run
```

Current facts:
- Pincode scrape is universal/team-run: VPS + Mac Pro + KVM1, default weights
  `5:4:1`, worker sessions detached in `tmux`.
- Inputs are `pincodes_jivo.json` plus logged-in member cookies from
  `secrets/bb_cookies.pincode.json`.
- Worker output is merged by `merge_team_pincode.py` into `result_pincode.json`.
- `build_excel_pincode.py` creates `Jivo-BigBasket-Pincode-Report-YYYY-MM-DD.xlsx`.
- Both workbooks' **Master Data** sheets carry a **SKU Code** column (2026-07-06) —
  BigBasket's own product id (`sku_id`, the BB equivalent of an ASIN), captured by
  the scrapers on every row. The owner's 32-code SKU master is checked in as
  `bb_sku_master.xlsx` / `bb_sku_master.json` (code → SAP code + item name) for
  cross-referencing; the 2026-07-06 run matched it 27/27 (pincode) and 21/21
  (national) with zero blanks.
- The pincode workbook is copied to `output/private-no-group/`, removed from normal
  `output/`, and direct-sent only from `BB_TEAM_DIRECT_JID` or the gitignored
  `secrets/bigbasket-direct-jid` file.
- The national `scrape.js` / `build_excel.py` flow is separate and produces the
  smaller `Jivo-Bigbasket-Live-Report-YYYY-MM-DD.xlsx` workbook.

Do not re-add BigBasket pincode to `run_all.sh` or the Ecom group batch. The live
cron source is `tools/cron/doctor.crontab.txt`; the installed root crontab runs
the team runner at 03:00 IST.

**Purpose:** Precise contracts and build checklist for adding BigBasket as the 8th
live platform in the ecom-intel pipeline. Do NOT write the scraper until this spec
is digested. Two agents can build independently against it without guessing.

---

## 1. result.json CONTRACT

Every scraper in this repo emits a single `result.json` in its platform directory.
The shape is identical across all grocery platforms (blinkit, zepto, ).
BigBasket MUST produce the same shape — `build_excel.py`, `review.py`, `predict.py`,
and `vault_note.py` all depend on it.

### Top-level shape

```json
{
  "summary": { ... },
  "perPin":  [ ... ],
  "allRows": [ ... ]
}
```

All three keys are REQUIRED.

### `summary` object — REQUIRED keys

| Field | Type | Notes |
|---|---|---|
| `pincodes_total` | `int` | Count of entries in `perPin` (how many pincodes were attempted) |
| `pincodes_with_jivo` | `int` | Count of `perPin` entries where `rows.length > 0` |
| `total_rows` | `int` | `allRows.length` |
| `unique_skus` | `int` | Count of distinct `canonical` values in `allRows` |
| `wall_s` | `int` | Elapsed seconds for the whole scrape |
| `captured_at` | `string` | UTC ISO-8601 timestamp, e.g. `"2026-05-31T10:48:51.255Z"` |

`review.py` checks `captured_at` for freshness (must be < 15 h old) and `pincodes_total`
to detect national vs per-pincode shape.

### `perPin` array — one entry per pincode attempted

Each entry mirrors the pincodes.json record plus scrape results:

| Field | Type | Required? | Notes |
|---|---|---|---|
| `city` | `string` | REQUIRED | e.g. `"Delhi"` |
| `tier` | `int` | REQUIRED | 1 or 2 (from pincodes.json) |
| `pincode` | `string` | REQUIRED | 6-digit string, e.g. `"110001"` |
| `locality` | `string` | REQUIRED | e.g. `"Connaught Place"` |
| `landmark` | `string` | REQUIRED | full landmark string from pincodes.json |
| `lat` | `float` | REQUIRED | from pincodes.json |
| `lon` | `float` | REQUIRED | from pincodes.json |
| `represents` | `int` | optional | only present if pincodes.json has this key |
| `pincodes` | `array` | optional | only present if pincodes.json has this key |
| `store_id` | `string` | REQUIRED | BigBasket store/hub id, or `""` if unavailable |
| `store_name` | `string` | REQUIRED | BigBasket store/hub name, or `""` if unavailable |
| `rows` | `array` | REQUIRED | list of row objects (may be empty `[]`) |

### `allRows` array — the canonical flat list

`allRows` is the authoritative flat list. It is the concatenation of all
`perPin[i].rows`. Every downstream tool (review.py, build_excel.py, predict.py,
vault_note.py) reads from `allRows` first.

#### Per-row schema — REQUIRED fields (review.py enforces these via `REQUIRED_ROW_FIELDS`)

```
REQUIRED_ROW_FIELDS = ("sku_raw", "canonical", "sale", "mrp", "discount_pct", "in_stock")
```

Full canonical row schema (all fields that build_excel.py reads):

| Field | Type | Required | Notes |
|---|---|---|---|
| `city` | `string` | REQUIRED | city name, e.g. `"Delhi"` |
| `pincode` | `string` | REQUIRED | 6-digit string |
| `locality` | `string` | REQUIRED | locality name |
| `store_id` | `string` | REQUIRED | store identifier or `""` |
| `store_name` | `string` | REQUIRED | store/hub display name or `""` |
| `sku_raw` | `string` | REQUIRED | product name as shown on BigBasket |
| `canonical` | `string` | REQUIRED | normalized slug, e.g. `"jivo-pomace-olive-oil-1l"` |
| `pack` | `string` | REQUIRED | pack size string, e.g. `"1 l"`, `"500 ml"` |
| `vol_ml` | `int\|null` | REQUIRED | volume in ml (1 L = 1000), `null` if unparseable |
| `sale` | `int\|float` | REQUIRED | sale/current price in INR; `0` if OOS and no price shown |
| `mrp` | `int\|float` | REQUIRED | MRP in INR; `0` if unavailable |
| `discount_pct` | `float\|null` | REQUIRED | `(mrp-sale)/mrp*100`, rounded to 1 dp; `null` if MRP=0 |
| `per_litre` | `int\|null` | REQUIRED | `round(sale / vol_ml * 1000)` if vol_ml>0, else `null` |
| `eta_min` | `int\|null` | REQUIRED | delivery ETA in minutes if shown, else `null` |
| `in_stock` | `int` | REQUIRED | `1` if in stock, `0` if out of stock |

**Type notes:**
- `in_stock` is an `int` (`1`/`0`), not a bool. `review.py` and `predict.py` accept
  both `int` and `bool`; emit `int` to be safe.
- `sale` and `mrp` for out-of-stock rows: use `0` (or the last known price if BigBasket
  shows it). Do NOT emit `None` for price fields — `build_excel.py` does arithmetic
  on them.
- `discount_pct`: emit `null` (Python `None`) if MRP is 0 or unparseable. Do NOT emit
  negative values. The review.py check `discount_in_range` flags values outside [0, 100].

**Canonical slug algorithm** (copy from blinkit/scrape.js):
```js
function canonical(name, pack) {
  const base = (name || '').toLowerCase()
    .replace(/\(.*?\)/g, '')
    .replace(/[^a-z0-9 ]/g, '')
    .replace(/\s+/g, ' ').trim()
    .replace(/\s/g, '-');
  const vol = parseVolMl(pack);
  const volTag = vol ? (vol >= 1000 ? (vol / 1000) + 'l' : vol + 'ml') : 'na';
  return `${base}-${volTag}`.replace(/--+/g, '-');
}
```

---

## 2. build_excel.py — Copy-verbatim? YES

`platforms/blinkit/build_excel.py` and `platforms/zepto/build_excel.py` are
**byte-for-byte identical** (confirmed by reading both). The platform name is
derived generically:

```python
PLATFORM = os.path.basename(os.getcwd()).replace('-', ' ').title()
```

For BigBasket this produces `"Bigbasket"` → Excel title will read
`"Jivo x Bigbasket - Live Pricing Intelligence"` and filename will be
`Jivo-Bigbasket-Live-Report-<date>.xlsx`.

**Copy the file verbatim. There are ZERO lines to change.**

### City-matrix layout

BigBasket is a grocery/quick-commerce platform with per-pincode delivery zones.
The city-matrix layout (Sheets 3–5: Pricing Matrix, Stock Status, Discount Analysis)
uses `cities_with = sorted(set(r['city'] for r in rows))` as column headers — one
column per city with Jivo data. This is the correct layout for BigBasket (same as
blinkit/zepto/). The national single-column layout is only for Flipkart/Amazon
(where `pincodes_total == 1`).

### Exact lines in build_excel.py that are NOT hardcoded to any platform

- Line 14: `PLATFORM = os.path.basename(os.getcwd()).replace('-', ' ').title()`
  — auto-derives `"Bigbasket"` from the folder name. No change needed.
- Line 172: `fname = f"Jivo-{PLATFORM.replace(' ', '')}-Live-Report-{datetime.date.today()}.xlsx"`
  — produces `Jivo-Bigbasket-Live-Report-2026-05-31.xlsx`. No change needed.

**Action:** `cp platforms/blinkit/build_excel.py platforms/bigbasket/build_excel.py`

---

## 3. pincodes.json — Recommended content

### Existing file to reuse

`platforms/blinkit/pincodes.40.bak.json` is a clean **40-entry top-city pincode
list** with exactly the shape needed:

```json
[
  {"city": "Delhi", "tier": 1, "pincode": "110001", "locality": "Connaught Place",
   "landmark": "Connaught Place, New Delhi, 110001, India", "lat": 28.633, "lon": 77.219},
  ...
]
```

It covers 20 distinct cities × ~2 pincodes each = 40 entries:
Delhi (3), Gurgaon (2), Noida (2), Ghaziabad (1), Faridabad (1),
Mumbai (4), Pune (2), Bengaluru (3), Hyderabad (2), Chennai (2),
Kolkata (2), Ahmedabad (2), Surat (1), Vadodara (1), Jaipur (1),
Lucknow (1), Chandigarh (1), Indore (1), Bhopal (1), Coimbatore (1),
Nagpur (1), Visakhapatnam (1), Kanpur (1), Ludhiana (1), Patna (1), Mysuru (1).

All entries have `city`, `tier`, `pincode`, `locality`, `landmark`, `lat`, `lon`.
No `represents`/`pincodes` keys (those are the 332-entry deduplicated format).

**This file is the recommended `pincodes.json` for BigBasket.** It is exactly
the "top-20 cities, ~40 pincodes" goal stated in CLAUDE.md/README.md.

BigBasket's location API needs at minimum a pincode string (plus city context).
The `lat`/`lon` fields are present in case the scraper discovers BigBasket also
accepts coordinate-based location setting (as blinkit does via localStorage,
or zepto does via geolocation context). Include them — they cost nothing and
make the file forward-compatible.

**Action:**
```bash
cp platforms/blinkit/pincodes.40.bak.json platforms/bigbasket/pincodes.json
```

### Format compatibility note

BigBasket's web UI uses pincode-based location selection (the user types a pincode
into the delivery location dialog). The scraper should set location by pincode string.
The `lat`/`lon` can additionally be used for `geolocation` context injection if
BigBasket's API accepts coordinates. The `perPin` entries in result.json should include
whichever fields from pincodes.json are present (all 7 keys for the .40.bak format).

---

## 4. Registration Checklist

### 4a. run_all.sh — ADD bigbasket to the LIVE array

**File:** `/opt/ecom-intel/run_all.sh`

**Current line 15:**
```bash
for P in blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh; do
```

**Change to:**
```bash
for P in blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh bigbasket; do
```

No other change to run_all.sh is needed. BigBasket is an independent site with no
shared account or server-side location coupling (unlike amazon-now/amazon-fresh).
It can safely run in the parallel sweep.

### 4b. setup_cron.sh — NO change needed for scheduling

`setup_cron.sh` generates a single `0 H * * * ./run_all.sh` line per hour — it
doesn't list platforms individually (the `PLATFORMS=` line in setup_cron.sh is
documentation only and NOT read by the cron generator `build_block()`). run_all.sh
already contains the authoritative list.

Optional: update the documentation comment on line 31 of setup_cron.sh:
```bash
# Current line 31:
PLATFORMS="blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh"
# Update to:
PLATFORMS="blinkit  flipkart-minutes flipkart amazon zepto amazon-fresh bigbasket"
```
This is cosmetic only — it has no effect on the cron installation.

### 4c. run.sh — NO change needed

`run.sh` is fully generic. It:
1. Accepts any `<platform>` argument
2. `cd`s to `platforms/<platform>/`
3. Runs `node scrape.js` (no platform-specific case switches)
4. Runs `python3 build_excel.py`
5. Pipes through predict, review, vault, Telegram, git push

BigBasket uses the same `node scrape.js` entry point. No case/switch logic exists
in run.sh that would need a new entry.

**Verify:** `platforms/bigbasket/scrape.js` must exist and must emit `result.json`
in the platform directory before `./run.sh bigbasket` is called.

### 4d. REPORT.md — ADD row to the working-platforms table

**File:** `/opt/ecom-intel/REPORT.md`

Add a row to the "Working platforms (current cron)" table:

```markdown
| **BigBasket** | quick-comm | ~40 pincodes | ~8–12 (TBD) | pincode-based location |
```

Exact row count and SKU count to be filled in after the first successful run.
Update the TL;DR section's platform count (currently "7 platforms are LIVE") to 8.

### 4e. README.md — ADD row to the platform coverage table

**File:** `/opt/ecom-intel/README.md`

Add a row to the Platform coverage table after the Amazon Fresh row:

```markdown
| **BigBasket** | quick-comm | 🔧 WIP | ~40 pincodes | ~8–12 | pincode-based delivery zone |
```

Change status from `WIP` to `✅ LIVE` after the first confirmed run.

Also update CLAUDE.md line 24 (the `platforms/` layout comment) to include bigbasket
in the LIVE list once it goes live.

### 4f. data/ and baselines/ directories — AUTO-CREATED on first run

`tools/vault_note.py` creates `data/bigbasket/history.csv` on first run
(via `os.makedirs` + csv writer). No pre-creation needed.

`tools/review.py` creates `baselines/bigbasket.json` on the FIRST OK run
(via `update_baseline()`). No pre-creation needed.

### 4g. Per-platform deps — npm install + playwright

After creating `platforms/bigbasket/scrape.js`, run:
```bash
cd platforms/bigbasket && npm install && npx playwright install chromium
```
The `package.json` already exists (with playwright dependency). Just run install.

---

## 5. First-run / review.py behavior

### No baseline on first run — safe, not BROKEN

When `baselines/bigbasket.json` does not exist, `review.py` calls `load_baseline()`
which returns `None`. `normalize_baseline()` returns `{"platform": "bigbasket", "samples": []}`.
`baseline_expected()` returns `None` when samples is empty.

All baseline-comparison checks (`rows_vs_baseline`, `skus_vs_baseline`,
`pincode_coverage`) gracefully degrade:

```python
# rows_vs_baseline (check #3): when expected is None, passes with note:
add("rows_vs_baseline", True, "no baseline yet (first OK run seeds it)")

# skus_vs_baseline (check #4): same:
add("skus_vs_baseline", True, f"{n_skus} unique SKUs (no baseline yet)")

# pincode_coverage (check #10): when no baseline, passes IF pin_jivo > 0:
ok = pin_jivo > 0
add("pincode_coverage", ok,
    f"{pin_jivo} pincodes w/ Jivo (no baseline yet)"
    if ok else "0 pincodes carry Jivo",
    severity="broken" if not ok else "suspect")
```

**Conclusion:** On first run, if the scraper returns >= 20 rows from at least 1
pincode, with valid schema and fresh timestamps, the verdict will be **OK** and
`baselines/bigbasket.json` will be created automatically.

### What can still make first run BROKEN

These deterministic checks have no baseline dependency and fire on every run:

| Check | BROKEN trigger |
|---|---|
| `non_zero_rows` | 0 rows total |
| `rows_above_floor` | fewer than 20 rows total |
| `no_block_markers` | captcha/403/CloudFront marker in any field |
| `schema_integrity` | any of `sku_raw, canonical, sale, mrp, discount_pct, in_stock` missing from rows |
| `freshness` | `captured_at` absent or > 15 h old |
| `pincode_coverage` | `pincodes_with_jivo == 0` (no pincode carries Jivo at all) |

The most likely first-run failure mode is **IP block** (BigBasket behind Cloudflare
or similar WAF). If `row count = 0` or block markers appear, the run will be BROKEN
and self-heal will trigger. Check `logs/bigbasket-<RUN_ID>.log` for 403/captcha signs.

### First-run verdict escalation path

```
review.py verdict BROKEN
  -> run.sh exits with || true (run itself does not fail)
  -> tools/selfheal.sh sees BROKEN in reviews/bigbasket-<RUN_ID>.json
  -> re-runs ./run.sh bigbasket once under logs/.heal-bigbasket.lock
  -> if still BROKEN: escalates to Telegram + logs/health.log
```

SUSPECT is recorded but does NOT trigger a re-run (only BROKEN does).

---

## 6. vault_note.py and predict.py — fully platform-agnostic

Both tools are driven entirely by the `<platform>` argument and `result.json`:

- `vault_note.py <platform> <RUN_ID>`: reads `platforms/<platform>/result.json` and
  `reviews/<platform>-<RUN_ID>.json`. Writes to `vault/runs/bigbasket/`,
  `vault/platforms/bigbasket.md`, `vault/daily/<date>.md`, and
  `data/bigbasket/history.csv`. No platform-specific code path. Pass-through
  guaranteed as long as result.json matches the contract above.

- `predict.py bigbasket <xlsx_path>`: reads `data/bigbasket/history.csv` (may not
  exist on run 1 — handled gracefully: "thin history" path) and
  `platforms/bigbasket/result.json`. Appends a "Predictions" sheet. Handles missing
  history.csv gracefully (degrades to current-state-only output).

No changes to either tool are needed.

---

## 7. Amazon-fresh / amazon-now concurrency note

BigBasket has **no Amazon account dependency**. It is a completely independent site
with its own location API. It can safely run in parallel with ALL other platforms
in `run_all.sh`, including amazon-fresh. There is no equivalent of the
"server-side account location" conflict that makes amazon-now and amazon-fresh
mutually exclusive.

---

## 8. Anti-bot risk assessment

BigBasket is known to use Cloudflare. The recon script at
`platforms/bigbasket/recon_step1.js` already probes the site from this VPS IP to
determine whether headless Chromium is blocked. Run it first:

```bash
cd platforms/bigbasket && node recon_step1.js 2>&1 | tee recon_step1.log
```

If the recon shows a 403 / JS challenge / CAPTCHA, BigBasket will need the same
BFF-API approach used for Zepto (bypass the CloudFront-fronted website and call the
internal search API directly). BigBasket's internal API is documented as
`https://www.bigbasket.com/listing-svc/v2/products/` (category + search listing).
A pincode is set via the `cs` (city-store) cookie or via a pre-flight POST to
`/api/v2/auth/address-serviceability/` — the recon output will confirm which.

If direct scrape works: use localStorage or cookie injection (similar to blinkit).
If blocked: target the listing API directly (similar to zepto's bff-gateway approach).

---

## 9. Build checklist (sequential)

```
[ ] 1. cp platforms/blinkit/pincodes.40.bak.json platforms/bigbasket/pincodes.json
[ ] 2. cp platforms/blinkit/build_excel.py       platforms/bigbasket/build_excel.py
[ ] 3. Run recon: node platforms/bigbasket/recon_step1.js > recon.log  (assess block)
[ ] 4. Write platforms/bigbasket/scrape.js  (location mechanism TBD from recon output)
       - MUST emit result.json with the exact schema in Section 1
       - MUST write result.json to cwd (platforms/bigbasket/result.json)
       - MUST use pincodes.json as input (PFILE = __dirname + '/pincodes.json')
       - pincode-based location setting (see Section 3 / recon output)
[ ] 5. Write platforms/bigbasket/SKILL.md  (recipe, quirks, selectors)
[ ] 6. npm install in platforms/bigbasket/ && npx playwright install chromium
[ ] 7. Test: ./run.sh bigbasket  — check logs/, result.json, output/Jivo-Bigbasket-*.xlsx
[ ] 8. Verify review verdict: cat reviews/bigbasket-<RUN_ID>.json | python3 -m json.tool
[ ] 9. Edit run_all.sh line 15: add "bigbasket" to the platform list
[  ]   (setup_cron.sh PLATFORMS comment line 31: cosmetic update, optional)
[ ] 10. Update REPORT.md: add BigBasket row to working-platforms table, bump count to 8
[ ] 11. Update README.md: add BigBasket row to coverage table
[ ] 12. Update CLAUDE.md line 24: add bigbasket to the LIVE list
[ ] 13. Commit + push
[ ] 14. After 1–2 live cron runs: verify baselines/bigbasket.json was created
```

---

## 10. Summary — copy-paste reference

### result.json row schema (JSON)

```json
{
  "city":         "Delhi",
  "pincode":      "110001",
  "locality":     "Connaught Place",
  "store_id":     "BB-123",
  "store_name":   "BigBasket Delhi Central",
  "sku_raw":      "Jivo Pomace Olive Oil",
  "canonical":    "jivo-pomace-olive-oil-1l",
  "pack":         "1 l",
  "vol_ml":       1000,
  "sale":         405,
  "mrp":          1049,
  "discount_pct": 61.4,
  "per_litre":    405,
  "eta_min":      null,
  "in_stock":     1
}
```

### result.json summary schema (JSON)

```json
{
  "pincodes_total":     40,
  "pincodes_with_jivo": 25,
  "total_rows":         200,
  "unique_skus":        8,
  "wall_s":             180,
  "captured_at":        "2026-05-31T10:48:51.255Z"
}
```

### Files to create

| File | Action |
|---|---|
| `platforms/bigbasket/pincodes.json` | `cp platforms/blinkit/pincodes.40.bak.json platforms/bigbasket/pincodes.json` |
| `platforms/bigbasket/build_excel.py` | `cp platforms/blinkit/build_excel.py platforms/bigbasket/build_excel.py` |
| `platforms/bigbasket/scrape.js` | Write from scratch (see Section 4 + recon output) |
| `platforms/bigbasket/SKILL.md` | Write after scraper is proven |

### Files to edit

| File | Edit |
|---|---|
| `run_all.sh` line 15 | Add `bigbasket` to the platform loop |
| `REPORT.md` | Add row + bump live count to 8 |
| `README.md` | Add row to coverage table |
| `CLAUDE.md` | Add bigbasket to LIVE list (line 24 area) |
| `setup_cron.sh` line 31 | Cosmetic PLATFORMS comment update (optional) |

### Files auto-created by pipeline on first run

| File | Created by |
|---|---|
| `baselines/bigbasket.json` | `tools/review.py` (on first OK run) |
| `data/bigbasket/history.csv` | `tools/vault_note.py` |
| `vault/platforms/bigbasket.md` | `tools/vault_note.py` |
| `vault/runs/bigbasket/` | `tools/vault_note.py` |
| `reviews/bigbasket-<RUN_ID>.json` | `tools/review.py` |
