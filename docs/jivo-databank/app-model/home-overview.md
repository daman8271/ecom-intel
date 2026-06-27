# Home, Insights, Reports, Target Sheet, Data & Uploaders — the overview + the glue

> **Domain W4.** This file covers the pages that *tie the app together*: **Home** (the roll-up
> dashboard), **Insights** (the analytical dashboards), **Reports** (exports/rendered views),
> **Target Sheet** (targets vs actual), **Data** (the 41 raw tables + schemas), and **Uploaders**
> (the write-only ingestion surface). The single most important section is the
> [**PAGE CONNECTION MAP**](#page-connection-map) at the end — how every page feeds every other.
>
> Evidence base: `store/raw/2026-06-27/dashboards/*.json` (the app's own computed views),
> `store/versioned/` SSOT, `registry/{tables,endpoints,taxonomy}.json`, `recon/2026-06-26/`.
> All numbers below are **June 2026** unless stated.

---

## 1. HOME — the roll-up of the whole business

### 1.1 Purpose
Home is the executive overview. It does not own any data of its own — it is a **roll-up** that
re-states, in one screen, the four stages of JIVO's value chain plus the three things leadership
checks daily: *what's the category mix, what's moving, and are we actually filling orders.* Every
tile on Home is a doorway into a deeper domain page.

Home has four blocks:
1. **The 4 KPI cards** — the value chain (Wellness Billing → JM Primary → Primary → Secondary).
2. **Category Split** — Premium vs Commodity, by Category/Sub-category, toggleable Primary/Secondary.
3. **Top Movers** — top SKUs by litres + MoM Δ, with the biggest single riser and faller.
4. **Fulfilment Health** — fill-rate per platform (are POs being delivered?).

### 1.2 The 4 KPI cards — the value chain (decoded)

Everything is measured in **LITRES**, and **price rises at every step down the chain** (each stage
adds margin). Premium vs Commodity is split *inside every card*. June 2026:

| # | KPI card | Litres (Jun '26) | ₹/Litre | What it means | Whose data |
|---|----------|------------------|---------|---------------|------------|
| 1 | **Wellness Billing** | 811,616 L | ₹180/L | Jivo **Wellness** (the parent company that *makes* the oil) bills Jivo. This is production/supplier-side volume — the top of the funnel. | PO tables `total_po` / `master_po` (W2) |
| 2 | **JM Primary** | 672,739 L | ₹192.6/L | **Jivo Mart (JM)** — Jivo's own distribution entity/warehouse — takes stock in (its "primary" intake). | PO tables incl. `total_po_zbs` (W2) |
| 3 | **Primary** | 484,975 L | ₹210.3/L | What Jivo **ships TO the platforms** (sell-in / POs delivered). | `primary-po-litres`, `category-trend` (W2) |
| 4 | **Secondary** | 560,048 L | ₹218.2/L | What actually **sells through to consumers** on the platforms (sell-out). | `secondary-*` tables (W1) |

**The chain reads left-to-right as the physical flow of oil and money:**

```
 Jivo Wellness (parent, makes oil)        Jivo Mart (JM, distribution)        Platforms (Amazon, Swiggy…)        Consumers
        │ bills                                  │ primary intake                    │ sell-in (Primary)              │ sell-out (Secondary)
        ▼                                        ▼                                   ▼                               ▼
  811,616 L @ ₹180   ───────────────►    672,739 L @ ₹192.6   ──────────►    484,975 L @ ₹210.3   ─────────►   560,048 L @ ₹218.2
   (Wellness Billing)                      (JM Primary)                        (Primary)                        (Secondary)
        └──────────────── +₹12.6/L ──────────────┴────────────── +₹17.7/L ──────────┴───────────── +₹7.9/L ──────────┘
                         the margin ladder: each stage marks the oil up ~₹8–18/L
```

**Reading the card values carefully (grounded in the captured dashboards):**
- **Primary = 484,975 L** but the captured `primary-po-litres` and `category-trend` Jun totals are
  **458,703.7 L** — they match each other *exactly* (`SWIGGY 125,838 + ZEPTO 88,599.2 + BLINKIT
  30,198 + ZOMATO 26,495 + BIG BASKET 21,246 + FLIPKART GROCERY 20,166 + CITY MALL 17,715 + AMAZON
  128,446.5 = 458,703.7`). The ~26,271 L gap (484,975 − 458,703.7) is the **OTHER / non-oil** head
  (seeds, spices, juices, beverages, honey): `category-trend`/`category-breakdown` only report
  **PREMIUM + COMMODITY oils**, so the Primary *card* includes OTHER while the category charts don't.
  This is the single most important reconciliation note on Home.
- **Litres are NOT monotonic down the chain** — Secondary (560,048) > Primary (484,975). That's
  expected: Secondary draws down platform stock that was shipped in *earlier* months, so in any
  single month sell-out can exceed that month's sell-in. The price ladder (₹180→218.2) *is*
  monotonic and is the reliable signal.
- **Premium-mix** (premium % of volume) is a headline KPI inside each card. For Primary oils Jun '26
  the split is PREMIUM 233,401.7 L vs COMMODITY 225,302.0 L → **premium-mix ≈ 50.9%** of oil litres.

> The exact card litres (811,616 / 672,739 / 484,975 / 560,048) and ₹/L come from the live Home
> screen (owner + screenshots). The four *sources* are owned by other workers — Home is purely the
> roll-up. See the connection map for who computes each.

### 1.3 Category Split (Premium vs Commodity)
The donut/bar block on Home. Source dashboards: **`category-breakdown__<YYYY-MM>`** (premium +
commodity, each with `categories[]` and `sub_categories[]`), **`category-litres__<YYYY-MM>`**
(per-head litre ranking), and **`category-platform-breakdown__<YYYY-MM>`** (the same split fanned
out by platform). All carry a **`source`** field that is the **Primary/Secondary toggle**
(`"source":"primary"` by default; switch to `"secondary"` to see the same split on sell-out).

June 2026 Primary, Premium head (`category-breakdown__2026-06`, total **233,401.7 L**):

| Category | Litres | | Sub-category | Litres |
|----------|-------:|--|--------------|-------:|
| GROUNDNUT | 123,669.2 | | GROUNDNUT | 123,669.2 |
| OLIVE | 75,372.5 | | JIVO POMACE | 35,957.0 |
| CANOLA | 26,809.0 | | CANOLA | 26,809.0 |
| SESAME OIL | 3,680.0 | | SANO POMACE | 17,045.0 |
| MUSTARD (yellow) | 2,837.0 | | EXTRA LIGHT | 16,061.0 |
| BLENDED | 1,034.0 | | EXTRA VIRGIN / SESAME / Y.MUSTARD / SO OLIVE | … |

Commodity head (total **225,302.0 L**): MUSTARD KACCHI GHANI 104,808 · SUNFLOWER 89,681 · SOYABEAN
16,010 · GOLD (blended) 9,776 · RICE BRAN 5,027. This is the **premium-vs-commodity** story:
premium = value oils (canola, groundnut, pomace/olive, sesame, ghee); commodity = staples (mustard
kacchi ghani, sunflower, soyabean, rice bran, gold).

**Drill-down:** Category → Sub-category → **Platform** → **SKU**. Home's Category Split is the entry
point; clicking a category opens `category-platform-breakdown` (split by platform), then
`category-sku-breakdown__<platform>__<YYYY-MM>` (SKU-level, requires `--platform` + a category
`name`/`head`/`dimension` — the captured default call returns `"name":"Uncategorized"` with an empty
`skus[]` because no category was selected). e.g. *Groundnut → Swiggy → `GROUNDNUT 1L (390730)`,
`GROUNDNUT 5L (401502)`* with Apr/May/Jun litres + units.

### 1.4 Top Movers
Source: **`top-skus__<YYYY-MM>`** (optionally `__<platform>`). Returns `skus[]` ranked by litres
with `prev_ltrs`, `delta_pct`, `is_new`, plus two singled-out tiles: **`top_riser`** and
**`top_faller`**. June 2026 (vs May):

| Rank | SKU | Head | Jun L | May L | Δ% |
|------|-----|------|------:|------:|----:|
| 1 | MUSTARD 1L | COMMODITY | 84,108 | 111,558 | −24.6% |
| 2 | GROUNDNUT 1L | PREMIUM | 83,361 | 118,991 | −29.9% |
| 3 | SUNFLOWER 1L | COMMODITY | 54,411 | 69,064 | −21.2% |
| 4 | SUNFLOWER 5L | COMMODITY | 35,270 | 68,290 | −48.4% |
| 5 | GROUNDNUT 5L | PREMIUM | 29,000 | 59,465 | −51.2% |

- **`top_riser`**: `EXTRA VIRGIN 500ML` +343.8% (8 → 35.5 L) — premium, tiny base.
- **`top_faller`**: `EXTRA LIGHT 5L` −98.6% (6,855 → 95 L).

Note the whole top-5 is **down MoM** — consistent with Jun being a lighter month (`category-trend`
shows Jun primary 458,703.7 L vs May's 938,377.65 L, roughly half). Top Movers is on the **Primary**
source by default (`"source":"primary"`).

### 1.5 Fulfilment Health
Source: **`fulfilment-health`** (plain, no month arg — it uses a rolling **30-day window with a
7-day lag**: `2026-05-21 → 2026-06-20`). Answers "are the platforms' POs actually being filled?"

**Total:** ordered 964,560 L · filled 542,343 L · missed 151,757 L · **fill-rate 56.2%** ·
miss-rate 15.7% · 1,031 POs. By platform (fill-rate, ordered L):

| Platform | Ordered L | Filled L | Fill-rate | POs |
|----------|----------:|---------:|----------:|----:|
| ZOMATO | 37,747 | 31,848 | **84.4%** | 45 |
| CITY MALL | 21,028 | 17,715 | 84.2% | 6 |
| BIG BASKET | 26,869 | 22,097 | 82.2% | 39 |
| FLIPKART GROCERY | 22,008 | 17,806 | 80.9% | 30 |
| ZEPTO | 94,787 | 67,847 | 71.6% | 134 |
| SWIGGY | 222,359 | 114,430 | 51.5% | 504 |
| **AMAZON** | 429,242 | 180,540 | **42.1%** | 108 |

**Caveat:** Amazon (the biggest order book, 429k L) has the worst fill-rate (42.1%), dragging the
total down to 56.2%. Fill-rate here is a **Primary-side** health metric (PO delivered ÷ PO ordered),
so it links Home directly to the Primary domain and the PO tables. (Fill-rate ≠ the
"fill_rate"/achieved on the Target sheet — different denominators.)

### 1.6 Home anomalies / caveats
- The four KPI-card *exact* values aren't in any single captured dashboard — Home composes them from
  four different domains. Treat the card litres as the source of truth and the per-domain dashboards
  as the breakdowns underneath.
- Primary card (484,975) includes OTHER non-oils; the category charts (458,703.7) don't. Always
  reconcile via the ~26k OTHER gap.
- `category-platform-breakdown__2026-06` (default call) returns empty (`platforms:[]`,
  `"name":"Uncategorized"`) — it needs a selected head/dimension/category, so the captured snapshot
  looks empty but the endpoint is live.

---

## 2. INSIGHTS — the analytical dashboards

**Purpose.** Insights is *not* a data layer; it's the collection of **computed analytical views**
that slice the same Primary/Secondary/Inventory data along business questions. If Home is the
headline, Insights is the body. The CLI exposes these under the `dashboard` group (14 keys) plus the
per-platform `platform <slug>` group (19 sub-dashboards).

**The analytical dashboards (what each answers):**

| Dashboard | Question it answers | Grain | Source toggle |
|-----------|---------------------|-------|---------------|
| `category-breakdown` | Premium vs commodity mix | category / sub-category | primary∣secondary |
| `category-litres` | Litre ranking within a head | category | primary∣secondary |
| `category-platform-breakdown` | Same split, by platform | category × platform | primary∣secondary |
| `category-sku-breakdown` | SKU detail in a category (needs `--platform`) | SKU × month | primary∣secondary |
| `category-trend` | Mix over last N months | month | primary∣secondary |
| `top-skus` | Top SKUs + risers/fallers | SKU, MoM | primary∣secondary |
| `secondary-yoy-growth` | YoY sell-out growth | platform × year | secondary |
| `state-sales` / `state-sales-detail` | Geographic sell-out | state × platform | secondary |
| `fulfilment-health` | PO fill performance | platform, 30d window | primary |
| `platform-expiry-alerts` | Stock nearing expiry | platform | inventory |
| `inventory-charts` | Inventory series | platform | inventory |
| `primary-po-litres` | Primary delivered volume | platform | primary |

**Secondary YoY growth** (a flagship Insights view, `secondary-yoy-growth`): anchored on the latest
month (June), compares 2024/2025/2026 sell-out per platform with a **month-end projection**. Totals:
2024 = 138,505.5 L → 2025 = 295,936.6 L (**+113.66%**) → 2026 = 526,138.2 L actual, **642,901.2 L
projected** (+77.79% YoY). Amazon alone: 115,716.5 → 194,997.6 (+68.5%) → 195,294.2 actual /
244,117.8 projected. Each cell carries `actual` (litres), `value` (₹), `units`, `growth_pct`,
`projection`, `elapsed_day`/`days_in_month` (for the projection), and `source` table
(e.g. `amazon_sec_range_master_view`).

**State sales** (`state-sales`/`state-sales-detail`): secondary units/value by **state**, each with a
`by_platform` map. Jun '26 top states by units: Maharashtra 167,809 · Karnataka 125,421 · Delhi
109,108 — Amazon dominates each state's mix. Filterable by brand/category/sub-category; `-detail` is
the paginated row-level version.

**Per-platform Insights** (`platform <slug> ...`, 19 keys): `ads`, `coupon`, `drr` (daily run-rate),
`pendency`, `pos`, `price`, `comparison`, `marketplace`, `month-on-month-sale`, `stats`, plus the
inventory ones (`soh-doh`, `region-doh`, `inventory-match`) and the targets (`month-targets`,
`primary-month-targets`). These are the platform-scoped drill-downs the domain pages link into.

**Connections:** Insights is the analytical *lens* over W1 (Secondary), W2 (Primary/supply), W3
(Inventory) — it doesn't introduce new data, it re-aggregates theirs. Home's four blocks are the
"greatest hits" of Insights.

**Anomalies:** several Insights dashboards are **gated server-side per platform** — a 400/404 on a
sub-dashboard (e.g. `secondary` for citymall/zomato) is the API's own restriction, not a bug. Empty
platforms (citymall, zomato) return empty secondary/inventory views.

---

## 3. REPORTS — exports / rendered views

**Purpose.** Reports is the **export/rendered** surface — the same Insights numbers packaged for
download or print (month-end packs, state-sales sheets, target-vs-actual sheets, SKU breakdowns).
The CLI mirrors this with **output renderers** rather than distinct endpoints: every dashboard
supports `--json`, `--csv`, `--select`, `--compact` (per `~/JIVO-ECOM-CLI-SETUP.md`), and the
`tables data` command returns "server-shaped payloads" suitable for export.

**What feeds Reports:** there is no Reports-only data source. Reports re-renders the *Insights*
dashboards (`category-*`, `top-skus`, `state-sales`, `secondary-yoy-growth`) and the *Target sheet*
(`month-targets`, `primary-month-targets`) into tabular/exportable form, scoped by month + platform.

**Connections:** Reports ← Insights ← (Primary / Secondary / Inventory). Reports is downstream of
everything; it is the read-out, the mirror image of Uploaders (which is the read-in).

**Caveat:** because the CLI is **read-only**, Reports here = the rendered/exported *views*; we have
not captured a separate "reports" endpoint family — Reports is a presentation layer over the
analytical dashboards, confirmed by the shared `--csv`/`--select` output flags.

---

## 4. TARGET SHEET — targets vs actual

**Purpose.** The Target sheet is where the team sets **monthly volume targets** and tracks **actual
vs target** for both halves of the funnel. It has two distinct tracks, each per-platform, per
item_head (PREMIUM/COMMODITY):

| Track | Dashboard | `type` | Side of funnel |
|-------|-----------|--------|----------------|
| **Secondary targets** | `month-targets__<slug>` | `B2B` | sell-out (consumers) |
| **Primary targets** | `primary-month-targets__<slug>` | `prim` | sell-in (to platforms) |

**Secondary targets** (`month-targets`, e.g. Swiggy Jun '26):
- COMMODITY: target 80,000 L, `done_ltrs` 68,026 (**85.0% achieved**), `est_ltr` 81,631 (**102%
  projected** by month-end), `done_value` ₹10,273,283, `last_month` 80,999, `growth_pct` +0.78%.
- PREMIUM: target 60,000 L, `done_ltrs` 78,642.5 (**131% — already beat**), `est_ltr` 94,371 (157%),
  `growth_pct` +61.7% vs last month.
- Fields: `targets, done_ltrs, done_value, achieved_pct, est_ltr, est_value, est_ltr_pct,
  last_month, growth, growth_pct`.

**Primary targets** (`primary-month-targets`, Swiggy Jun '26) add **run-rate planning**:
- COMMODITY: target 200,000 L, `done_ltrs` 62,446 (**31.2%**), `drr` 2,601.9 L/day (daily run-rate),
  `require_drr` 22,925.7 (what's needed/day to hit target), `pending_ltr` 137,554, `dp_ltrs`
  (display/planned) 200,000, `est_ltr_pct` 39%.
- PREMIUM: target 110,000 L, done 53,952 (49%), `require_drr` 9,341.3, `pending_ltr` 56,048.
- The extra fields (`drr`, `require_drr`, `pending_ltr`, `dp_ltrs`) make this an **operational
  pacing tool** — "at today's run-rate, will we hit the number, and what daily rate closes the gap?"

**Connections (this is the Target sheet's whole reason to exist):**
- `month-targets` (B2B) ↔ **Secondary** page — `done_ltrs`/`done_value` are sell-out actuals.
- `primary-month-targets` (prim) ↔ **Primary** page — `done_ltrs` are PO sell-in actuals; `drr`
  links to the per-platform `drr` Insights dashboard.
- Split by **item_head** ties it straight back to Home's premium-vs-commodity Category Split.
- The `est_ltr`/projection logic mirrors `secondary-yoy-growth`'s projection (elapsed-day pacing).

**Anomalies:** targets exist per platform but there is **no captured aggregate** target view — Home's
KPI cards are actuals, not target roll-ups; the Target sheet is consumed per-platform. Targets carry
`created_at`/`updated_at` and are **editable** (set via the app/Uploaders), the one place in this
otherwise read-only surface where numbers are authored.

---

## 5. DATA — the 41 raw tables + schemas

**Purpose.** The Data page is the **raw foundation**: the 41 source tables every other page is built
from, each with its **`table-columns`** schema doc (columns + a sample row). It's the "show me the
underlying rows" layer — the SSOT made browsable. CLI: `tables counts | columns | data | distinct`.

**The 41 tables** (from `registry/tables.json`, `rows_recon` = recon count; **L1** = raw, **L2** =
master/derived view):

*Secondary / sell-out (W1):* `swiggySec` (491,250) · `blinkitSec` (128,749) · `zeptoSec` (43,471) ·
`bigbasketSec` (17,036) · `flipkartSec` (19,421) · `jiomartSec` (9,434) · `flipkart_secondary_all`
(21,430, L2) · `amazon_sec_daily` (2,749) · `amazon_sec_daily_master_view` (2,749, L2) ·
`amazon_sec_range` (3,610) · `amazon_sec_range_margins` (114) · `amazon_sec_range_master_view`
(4,240, L2) · `citymallSec` (0, empty) · `zomatoSec` (0, empty).

*Primary / PO / supply (W2):* `total_po` (8,030) · `total_po_zbs` (35,839) · `master_po`
(44,081, L2) · `flipkart_grocery_master` (4,054, L2) · `fk_grocery` (0, empty) · `prim_master_po`
(0, empty) · `test_master_po` (0, empty).

> **Verified platform coverage of the PO tables (I checked the `format` distinct on each — important
> and not obvious):** the three PO tables are **disjoint by platform**, and **none contains Amazon**:
> - `master_po` (L2, the rich view) → SWIGGY, ZEPTO, BLINKIT, BIG BASKET, CITY MALL, FLIPKART
>   GROCERY, ZOMATO (and DEAL SHARE) — i.e. *all non-Amazon primary*, with derived
>   `total_delivered_liters`, `filled_ltrs`, `missed_ltrs`, `item_head`, `category`, `sub_category`.
> - `total_po` (L1, raw) → only **BIG BASKET, FLIPKART GROCERY, CITY MALL, ZOMATO, DEAL SHARE** (the
>   marketplace-grocery archetype). 5,342/8,030 COMPLETED, 2,082 CANCELLED.
> - `total_po_zbs` (L1, raw) → only **SWIGGY (21,274), BLINKIT (10,451), ZEPTO (4,117)** — the q-comm
>   "ZBS" trio. So `master_po` = `total_po` (grocery) + `total_po_zbs` (q-comm), unified + enriched.
> - **Amazon has NO Jivo-side PO table at all.** Its primary is reconstructed server-side from
>   *vendor-central* signals in `amazon_inventory` (`net_received`, `open_purchase_order_quantity`,
>   `receive_fill_pct`). This is the archetype-A ("vendor_central") model from `taxonomy.json`.

*Inventory (W3):* `all_platform_inventory` (176,769) · `swiggy_inventory` (63,699) ·
`bigbasket_inventory` (34,816) · `zepto_inventory` (31,955) · `blinkit_inventory` (27,069) ·
`amazon_inventory` (11,446) · `jiomart_inventory` (2,223) · `citymall_inventory` (0) ·
`zomato_inventory` (0).

*Marketing / ads / price (W3):* `amazon_ads` (48,585) · `flipkart_ads` (7,965) · `blinkit_ads`
(1,073) · `swiggy_ads` (249) · `zepto_ads` (492) · `bigbasket_ads` (40) · `swiggy_brandfund` (411) ·
`zepto_brandfund` (44) · `blinkit_brandfund` (423) · `amazon_coupon` (765) · `amazon_price_data`
(192).

**Schema (`table-columns__<t>`):** each doc = `{columns:[…], sample:{…}}`. e.g. `total_po`: `id,
po_number, po_date, po_expiry_date, grn_date, vendor_name, status, sku_code, sku_name, order_qty,
delivered_qty, basic_rate, landing_rate, location, format, remark`. Grain varies: PO tables are one
row per PO-line; secondary tables are per sku/city/store/date; inventory is per date/sku/
location/format (often **finer than the exposed columns** — `all_platform_inventory` uses a
content-hash key because multiple dark-stores share a city with no store column).

**Master data** (`master products`, `master fcs`): the SKU dimension. `master products` maps
`format_sku_code` (platform listing) → `sku_sap_code` (the FG SKU-hub, e.g. `FG0000083`) → `item`
(e.g. `A2 GHEE 1L`) with `case_pack, per_unit, uom, tax_rate, item_head`. **Join model**:
`format_sku_code → sku_sap_code → item`; taxonomy (`item_head`/`brand`/`category`/`sub_category`)
comes from **`master_po` + `notifications`, NOT `master products`** (per `taxonomy.json`).
`master fcs` = the fulfilment-centre dimension.

**Connections:** Data → **every page**. The tables are the bottom layer; Insights/Home/Reports are
all aggregations of these rows. `master_po` is special — it feeds Primary *and* the taxonomy that
colours every premium/commodity split on Home.

**Anomalies:** 6 tables are **expected-empty** (`citymallSec, zomatoSec, citymall_inventory,
zomato_inventory, fk_grocery, prim_master_po, test_master_po` — the last two are placeholders/test).
`taxonomy.empty_platforms = [citymall, zomato]`. Recon counts are a snapshot; the live SSOT count is
authoritative.

---

## 6. UPLOADERS — the write-only ingestion surface

**Purpose.** Uploaders is **how data gets INTO the app** — the upload/ingestion screens where ops
staff push platform exports (CSV/Excel of secondary sales, POs, inventory, ads) into the database.
It is the **source** of everything in Data, and therefore of everything everywhere else.

**Key fact: Uploaders has NO read data of its own.** The CLI is strictly read-only — there is **no
read endpoint for Uploaders** (it is a write surface). The user record carries an explicit
**`Uploader` group** (`recon/2026-06-26/account-me.json` lists "Uploader" among the groups),
confirming it's a real role/page. The only write-shaped CLI command is `import` ("Import data from
JSONL file via API create/upsert calls") — present but out of scope for this read-only stack, and
the **Cardinal Rule** is that no mutation commands are used without explicit approval.

**What it ingests (inferred from the tables it must populate):** per-platform secondary sales files
(→ `*Sec` tables), PO files (→ `total_po`, `total_po_zbs`, `master_po`), inventory snapshots (→
`*_inventory`, `all_platform_inventory`), ads/brandfund/coupon exports, and the **targets** authored
on the Target sheet (→ `month-targets`/`primary-month-targets`).

**Connections:** Uploaders → **Data** → (everything). It is the upstream origin of the entire data
model; the **mirror image of Reports** (Uploaders = data in, Reports = data out). The freshness of
every Home KPI depends on the last upload (note `fulfilment-health`'s **7-day lag** baked into its
window — a hint that uploads lag real-world POs by ~a week).

**Anomalies:** because it's write-only, we have **zero captured payloads** for Uploaders — its
existence is established by the `Uploader` group and the `import` command, not by data. Treat any
"missing" recent data as an upload-lag question, not a model gap.

---

## PAGE CONNECTION MAP

The whole point of this domain: **which page feeds which.** Arrows = data/derivation flow.

```
                          ┌─────────────────────────────────────────────────┐
   UPLOADERS  ───ingest──►│  DATA  (41 raw tables + table-columns schemas)   │
  (write-only,            │  master_po · *Sec · *_inventory · total_po* …    │
   no read data)          └───────────────────────┬─────────────────────────┘
        ▲                                          │ rows aggregate up into…
        │ (targets authored)                       ▼
        │            ┌──────────────┬───────────────────────────┬──────────────┐
        │            ▼              ▼                           ▼              ▼
        │      JM PRIMARY  ──►  PRIMARY  ───ships to platforms──► SECONDARY   INVENTORY / JM INVENTORY
        │     (W2 supply)     (W2 sell-in)                      (W1 sell-out)   (W3 stock)
        │            ▲              │  ▲                           │  ▲            │
        │     WELLNESS BILLING      │  │ targets vs actual         │  │ targets    │ expiry / SOH / DOH
        │     (W2, top of chain)    │  │                           │  │            │
        │                     PRIMARY targets             SECONDARY targets        │
        │                    (primary-month-targets,      (month-targets, type     │
        └───── TARGET SHEET ─ type prim, drr/pending)     B2B, done/est/growth) ───┘
                     │
                     ▼  every block above rolls up into…
          ┌───────────────────────────────────────────────────────────────────────┐
          │   HOME  (the roll-up)                                                   │
          │   • 4 KPI cards = Wellness Billing → JM Primary → Primary → Secondary   │
          │   • Category Split (Primary/Secondary toggle, premium vs commodity)     │
          │   • Top Movers (top-skus + riser/faller)                                │
          │   • Fulfilment Health (PO fill-rate, from Primary/PO tables)            │
          └───────────────────────────────┬───────────────────────────────────────┘
                                           │ same numbers, sliced & packaged
                          ┌────────────────┴────────────────┐
                          ▼                                  ▼
                    INSIGHTS                              REPORTS
        (analytical dashboards: category-*,        (exports / rendered views:
         top-skus, secondary-yoy-growth,            --csv/--select over the same
         state-sales, per-platform drr/pos/…)       Insights + Target dashboards)
```

**The connections that matter most (each with its evidence):**

1. **The value chain is the spine.** `Wellness Billing → JM Primary → Primary → Secondary`, litres
   constant-ish, ₹/L rising ₹180→192.6→210.3→218.2. Home's 4 cards = the 4 stages, owned by W2
   (first three) and W1 (last). *Evidence:* CONTEXT value-chain; `primary-po-litres` = Primary oils
   458,703.7 L = `category-trend` Jun total (exact match).

2. **Home = roll-up of Primary + Secondary + Inventory.** Top Movers/Category Split = Primary or
   Secondary (toggle); Fulfilment Health = Primary/PO side; the cards span both. *Evidence:* every
   Home block's `source` field is one of primary/secondary/inventory.

3. **Category Split links to every domain.** Premium-vs-commodity by Category→Sub-cat→Platform→SKU is
   the universal axis — it appears on Home, in Insights (`category-*`), on the Target sheet (per
   item_head), and is coloured by `master_po`/`notifications` taxonomy. *Evidence:* `taxonomy.json`
   join_model; `category-breakdown` premium 233,401.7 / commodity 225,302.0.

4. **Target sheet ↔ Primary & Secondary.** `primary-month-targets` (type `prim`) = Primary actuals +
   run-rate; `month-targets` (type `B2B`) = Secondary actuals + projection. Split by item_head →
   back to Category Split. *Evidence:* the two dashboards' `type` and field sets (drr/pending_ltr vs
   done_value/growth).

5. **Data ↔ every page.** The 41 tables are the substrate; Home/Insights/Reports/Targets are all
   aggregations. `master_po` uniquely feeds Primary *and* the taxonomy on every page. *Evidence:*
   `registry/tables.json` layers (L1 raw → L2 master views); `table-columns__*`.

6. **Uploaders → everything; Reports ← everything.** Uploaders is the write-in origin (no read data,
   `Uploader` group + `import` cmd); Reports is the read-out mirror (CSV/select renders of Insights +
   Targets). The pipeline is **Uploaders → Data → domain pages → Insights → Home → Reports.**

---

### Cross-references to sibling domain files
- **W1 — Secondary** (`secondary.md`): owns the Secondary card + Secondary toggle of Category Split.
- **W2 — Primary / JM Primary / Wellness Billing** (`primary-supply.md`): owns KPI cards 1–3 + the
  PO/fulfilment mechanics behind Fulfilment Health.
- **W3 — Inventory / JM Inventory / Marketing / Distributor**: owns the inventory tables behind
  `platform-expiry-alerts`/`inventory-charts` that Home's expiry/stock context links to.
