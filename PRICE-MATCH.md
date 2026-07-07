# PRICE-MATCH v2 — spec (locked with owner, 2026-06-05)

> Cross-platform Jivo SKU price reconciliation + **agreed-price compliance**.
> **VIOLATIONS ENGINE LIVE 2026-06-06** (fleet pmengine/pmsheets/pmverify, 204 checks 0 fail):
> `tools/pricematch/pricematch_core.py` (regime calendar Mon–Thu BAU / Fri–Sun SVD / ART via
> regime.json overrides; ₹1 tolerance; modal in-stock basis; EVERY-store violation scan) →
> per-platform "Price Match" sheet appended by run.sh (RED diff = live below agreed, GREEN =
> above — owner's display rule) + `build_pricematch.py` master workbook (sheet 1 = Ecom Head
> view) riding the daily 12:00 noon batch LAST. First real run: 85 BELOW, ₹5,804 exposure.
> Status: **spec locked in brainstorm session, dry-run mapping validated + adversarially
> verified (3-agent fleet), build not started.**
> v1 of this doc assumed we'd invent a SKU master from scratch — superseded the day the
> e-com dept's two Excels arrived (now at `tools/pricematch/`, dry-run artifacts in
> `tools/pricematch/dryrun/`).

## What it is
The e-com dept maintains a master price sheet (96 SKUs) with three **agreed prices** per SKU:

| Regime | When (default) | Meaning |
|---|---|---|
| **BAU** | Mon–Thu | business-as-usual price |
| **SVD** | Fri–Sun | Super Value Days price |
| **ART** | festivals/sale events | festival pricing — applied only when owner announces (~1 day ahead) |

The calendar is a default, not a law — owner can shift regimes (e.g. SVD on a Monday); a
`regime.json` override file captures announcements.

> **Agreed-price updates (SVD/BAU are refreshed here, not one-off):** these live in
> `tools/pricematch/master_v2.json`, the single source of truth the daily build reads
> (`pricematch_core.py`). When the e-com team sends a new Amazon price pass
> (`amazon_price_updated` format), overwrite **only** `svd`/`bau` for the listed ASINs in
> `master_v2.json` — the next daily run picks them up automatically, no code change.
> Leave `art`/`asp`/`mrp` alone unless told. If you ever re-run `extend_map.py` (full
> master rebuild from a team sheet), feed it the *latest* sheet or it will clobber these.
> _Last refresh: **2026-07-07** — SVD/BAU for 18 Amazon SKUs. Provenance:_
> `tools/pricematch/amazon_svd_bau_update_2026-07-07.xlsx`. _Prior backup:_
> `master_v2.json.bak-2026-07-07`.

**The deliverable:** every run, for every SKU × platform — does the live price match the
agreed price for *today's regime*? Below agreed = **red, −loss** (we fund that gap → MAP
violation, e.g. gave Amazon ₹249, it lists ₹239). Above = **blue, +diff**. Plus the
cross-platform matrix (same bottle side-by-side everywhere) and gap/spread analytics.
One agreed price applies to ALL platforms (owner-confirmed).

## Inputs (verified)
1. `platforms/<p>/result.json` → `allRows[]` — never re-scrape.
2. **`Amazon Price Match.xlsx`** (e-com dept master, 96 rows): PRODUCT (internal SKU name),
   ASIN, MRP/ASP/Margin/Tax/Cost, **SVD/BAU/ART prices (100% filled)**, partial cross-platform
   URLs (FK 39,  20, JioMart 14, Zepto 13, Blinkit 6). The empty columns (URL PRICE,
   STOCK, SELLER, per-platform prices, "Price Match") are what we automate.
3. `amazon_price_updated.xlsx` — the manual Amazon pass (URL PRICE 53/96, STOCK 96/96,
   RK World Infocom vs Jivo Mart seller prices) = ground truth to validate our build against.
4. `platforms/amazon/products.json` — 314-ASIN catalog: asin → internal item name + sap_code
   (SAP FG codes). 95/96 agreement with master PRODUCT names (1 typo: BLACK PAPER/PEPPER).
5. Flipkart scraper is already catalog-seeded: every row carries internal `item` name + `fsn` + sap_code.

## SKU identity — dry-run validated 2026-06-05 (`/tmp/pricematch/dryrun.py`)
Layered, deterministic, **no LLM in the hot loop**:

| Layer | Rule | Validated result |
|---|---|---|
| 1. ID join | asin (amazon/fresh/now), fsn + catalog `item` (flipkart), pvid (zepto), master URL ids | amazon **96/96**, fresh 22/28, now 20/21, fk 88/268, zepto 13/23 |
| 2. Name match | `(brand, line, vol_ml, combo-flag, pouch-flag)` parsed from sku_raw+pack via ordered keyword ladder | blinkit 9/9 ✓, fk-minutes 9/10, bigbasket 14/23, zepto +5 |
| 3. **MRP anchor (mandatory for layer-2)** | auto-accept ONLY if listing MRP == master MRP; else → Review sheet | caught **every** seeded error: Desi Ghee≠A2 Ghee (₹1499 vs ₹4000), zepto GOLD-blend≠RICE BRAN 5L (₹1050 vs ₹1425), Sano Pomace 3L≠1L (₹2997 vs ₹999) |
| 4. Collision rule | two listings on one platform → same master SKU = conflict → Review | catches Fizzy Lemon vs Spring Water (same ₹55 MRP) |
| 5. Review sheet | everything else — **never silently matched**; confirmed mappings persist to `sku_map.json` forever | ~10 residuals total across q-commerce |

Known ladder traps (encoded): GOLD = "rice bran + sunflower blend", SO OLIVE = "rice bran +
olive blend" → blend detection BEFORE rice-bran; BLACK OLIVE before olive; SANO/DiSano is a
sister brand, never cross-matches Jivo; Desi Ghee ≠ A2 Ghee; combos detected via
`+ / combo / pack of N / N PCS / with <product>` and matched only to combo SKUs
(CANOLA 1+1L is its own master row — 1L can never swallow 1+1L).
**Combo-composition rule:** a combo listing matches a master combo SKU only if its parts are
the SAME product (CANOLA 1+1L = two canolas; "Canola 1L + Mustard 1L" must NOT match it).

### Adversarial verification (3-agent fleet, 2026-06-05 — `dryrun/verify_results.json`)
83 name-based matches independently re-judged: 57 CORRECT, 18 WRONG, 8 RISKY.
**All 18 WRONG are caught by the production rules** — 16 by the MRP anchor (Desi Ghee×6,
Sano 3L, zepto GOLD-blend, mixed-oil combos×4, mustard+makki-atta, sunflower-seeds size swap,
BB Canola-pouch), the rest by combo-composition + the collision rule (Fizzy Lemon, MRP tie).
With rules ON: zero known silent mismatches; WRONG+RISKY (~26 listings) land on the Review
sheet for one-time human confirmation. ID joins (~239 listings) are exact and need no review.
Bonus: verification already surfaced real MRP-drift red flags — flipkart Pomace 1L MRP ₹745
vs official ₹1049, bigbasket EV 1L MRP ₹1799 vs ₹1499, amazon duplicate EL-3L ASIN at MRP
₹2997 vs ₹2200 — exactly the MRP-consistency deliverable.

### Identity-capture patches (2026-06-06, fleet pricecron W3 — live from the next cron run)
Scrapers now additionally record (additive, fail-safe, contract unchanged):
- flipkart-minutes: `fk_pid` + `listing_url` (defensive extraction from productInfo.action)
- blinkit: `prid` + `listing_url` (PDP anchor → /prn/<slug>/prid/<id>)
- bigbasket: `ean` (ONLY a true GS1-India EAN-13, `/^890\d{10}$/` — the 8-digit ean_code echo
  of sku_id is rejected)
**Post-deploy gate (W4-required, run BEFORE folding new ids into sku_map.json):** on the first
post-patch run assert blinkit prids are 5–7 digits AND stable per canonical across pincodes,
and every fk_pid matches `/^[A-Z0-9]{13,16}$/` and is not `itm/lst`-prefixed; any violation →
strip the field and keep the slug mapping. These ids fill the map's 12 missing URLs.

### Unpriced-listings census (from the same fleet)
169 combo/multipack listings + unpriced single families: WHEATGRASS JUICE 200/500ML (7 on
bigbasket alone — bigbasket-exclusive vs other q-commerce), CANOLA 2L & 15L TIN, RICE BRAN 2L,
SUNFLOWER 2L, MUSTARD 2L, GROUNDNUT 2L/200ML, HONEY, TEA 250G, MINERAL WATER, TONIC WATER,
GIFT BOXES, MAKKI ATTA, ENERGY DRINK, RICE 5KG. Junk to exclude: FLIP PRO / JIVO-INFI-*
internal scheme codes, kitchenware (CASSEROLE/LUNCH BOX/ROTI BOX → separate sheet if wanted).

**Master coverage visible in our scrapes: 96/96.** Per platform: amazon 96, flipkart 69,
fresh 22, now 20, zepto 18, bigbasket 12, blinkit 9, fk-minutes 9.  = "not listed" (WAF).

**Listings with NO master row** (amazon ~204, flipkart ~143, rest ~15): mostly combos/multipacks
+ unpriced families (wheatgrass juices, honey, tea, gift boxes, tonic/mineral water, 2L sizes,
15L tins, Desi Ghee). These go to an **UNPRICED LISTINGS sheet** — e-com dept extends the master
or ignores; we never guess a reference price.

## Build plan — `tools/pricematch/`
1. `ingest_master.py` — master.xlsx → `master.json` (re-runnable on every new sheet drop).
2. `sku_map.json` — auto-seeded by layers 1–4; review confirmations appended; committed.
3. `regime.json` — `{defaults: {mon..thu: BAU, fri..sun: SVD}, overrides: [{date, regime, note}]}`.
4. `build_pricematch.py` — result.json × master × sku_map × regime → `Jivo-Price-Match-<date>.xlsx`:
   - **Violations summary** (top sheet): every SKU below today's agreed price, ranked by loss, city named
   - Per-platform sheets: PRODUCT | agreed(regime) | live | diff (blue above/red below) | stock | MRP-check
   - **Cross-platform matrix**: SKU × platform, cheapest/dearest highlight, spread %, "not listed" gaps
   - Unpriced-listings sheet + Review sheet
   - Jivo-green / Leadership View styling (mirror `platforms/*/build_excel.py`)

### Price basis (per SKU × platform cell)
Quick-commerce prices vary per dark-store (live example: Blinkit Extra Light 2L = 28 distinct
prices ₹1135–₹1338 across 112 stores). **v1: modal price in the cell + min–max range; the
violation engine checks EVERY store** so a single undercutting store still flags (city named).
Owner to confirm after seeing v1.
- zepto: compare `price_source=SUPER_SAVER` price (what the app shows).
- amazon: buybox price; SELLER column shown (RK vs JM per-seller = phase 2).
- OOS rows: shown as OOS, price not compliance-checked.

## Phase 2 (parked — do not build now)
Auto-emailing platforms on violations (owner: only after v1 is accurate). Per-seller RK/JM
breakdown. JioMart scraper (in master, unscraped). Barcode/EAN extraction as identity fallback
for new platforms. Predictions. Competitor brands (Figaro/Borges/Oleev).

## Constraints
Read result.json only (no re-scrape). Deterministic + idempotent. NO LLM in the hot loop.
Never silently match — Review sheet or nothing. Commit local; owner authorizes pushes.
Cookies/secrets never committed.
