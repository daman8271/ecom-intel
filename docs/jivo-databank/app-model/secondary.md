# Secondary — sell-through to consumers (units + litres)

> **Domain owner:** W1. **Scope:** the **Secondary** workspace page (all per-platform Secondary
> leaves), the **"Secondary" toggle** on Home's Category Split, plus the geographic and SKU
> drill-downs that hang off sell-out: `state-sales`, `state-sales-detail`, `top-skus`,
> `category-sku-breakdown`, and the secondary time-series (`secondary-years`,
> `secondary-yoy-growth`, `secondary-monthly`, `month-on-month-sale`).
> All numbers below are mined from the SSOT (`store/versioned/...`), anchored to **June 2026**.

---

## 1. Purpose

**Secondary = what actually SELLS THROUGH to end consumers on each platform.** It is the *last*
link of the value chain and the only one measured at the **consumer** end:

```
Wellness Billing 811,616 L @ ₹180/L   (Jivo Wellness makes/bills the oil)
   → JM Primary    672,739 L @ ₹192.6/L   (Jivo Mart's own primary sales)
   → Primary       484,975 L @ ₹210.3/L   (Jivo SHIPS this TO the platforms = sell-IN)
   → Secondary     560,048 L @ ₹218.2/L   (platforms SELL this TO consumers = sell-OUT)   ← THIS PAGE
```

Where **Primary** answers *"how much did we ship onto Amazon/Swiggy/Blinkit/…?"*, **Secondary**
answers *"how much did shoppers actually buy off those platforms?"* — measured in **units (Qty)**
and **litres**, valued at **MRP/realised consumer price** (the highest per-litre in the chain,
₹218.2/L). It is the demand signal that everything upstream (inventory, primary orders, marketing
spend) ultimately serves.

The page is **per-platform** (each marketplace reports sell-out in its own native format), then
rolled up into a combined secondary master.

---

## 2. Key metrics / KPIs (with real June-2026 numbers)

Per-platform Secondary dashboard (`secondary__<platform>`) headline fields:

| Field (`detail_labels`) | Meaning |
|---|---|
| `shipped_units` / "Done Qty" | Units sold through to consumers in the month |
| `shipped_ltr` / "Done Liters" | Litres sold through (units × pack litres) |
| `shipped_value` / "Done Value" | Consumer-side value (= `SecMaster.sales_amt` / GMV) |
| `per_liter_shpd` / "Per Unit" | Realised ₹ per litre (value ÷ litres) |
| `last_month` | Prior-month litres, for MoM context |
| `item_head` summary | **PREMIUM vs COMMODITY vs OTHER** split (the headline mix axis) |

**Example — Swiggy Secondary, June 2026** (`secondary__swiggy`, `source: "SecMaster"`):
- Summary total: **146,668 L / 122,457 units / ₹2.89 cr** @ **₹197.1/L**.
- Mix: **PREMIUM 78,642 L @ ₹230.4/L** vs **COMMODITY 68,026 L @ ₹158.6/L** (premium-mix ≈ 54%).
- Top SKUs: GROUNDNUT 1L 51,362 L (₹1.0 cr), MUSTARD 1L 25,242 L, SUNFLOWER 1L 18,408 L.
- Per-litre confirms the premium thesis: GROUNDNUT/OLIVE @ ₹195–530/L, MUSTARD/SUNFLOWER @ ₹158/L.

**Premium-mix** (premium % of litres) is the single most-watched KPI — it appears on every
secondary view and on the Home cards, because premium oils carry the margin.

### Secondary totals across all platforms (`secondary-yoy-growth`, metric = litres)

| Year | Total secondary litres | YoY growth | Units | Note |
|---|---|---|---|---|
| 2024 | 138,505 L | — | — | only Amazon + Blinkit reporting |
| 2025 | 295,936 L | **+113.7 %** | — | Flipkart, BigBasket added |
| 2026 (to Jun-24) | **526,138 L** | **+77.8 %** | — | projected month-end **642,901 L**; Swiggy/Zepto/FK-Grocery now live |

> Home's Secondary KPI card reads **560,048 L** for Jun 2026 — slightly above the
> `secondary-yoy-growth` MTD figure of 526,138 L because the YoY view is anchored to **June 24–25**
> (a partial month, ~24/30 days elapsed) while the card uses a fuller/projected basis. Treat
> 526k as MTD-actual and ~643k as the projection.

---

## 2.5 Independent verification (computed from raw `changelog.jsonl`, not the dashboard docs)

I re-derived the dashboards from the raw row data to test the model. `state.jsonl` holds only row
**hashes** (`first_seen/hash/key/version`) — the actual rows live in `changelog.jsonl` `.row`, and
changelog count == state count for every platform (no version duplication: swiggySec 537,624 =
537,624, blinkitSec 128,749 = 128,749, etc.).

**✅ Units & litres reconcile exactly — these are trustworthy:**
- swiggySec June-2026 raw `UNITS_SOLD` = **122,220** vs dashboard summary 122,457 (−0.2%, combo rounding).
- blinkitSec June-2026 raw `qty_sold` = **54,334** — *exactly* matches `secondary-yoy-growth` Blinkit-2026 units = 54,334.
- `flipkart_secondary_all` June `ltr_sold` = PREMIUM 14,446 + COMMODITY 4,840 + OTHER 0 = **19,286 L** — *exactly* matches yoy Flipkart-2026 = 19,286 L.
- The eight per-platform yoy-2026 litres sum to **526,138.2 L** = `totals.2026.actual` 526,138.15. Cross-platform roll-up confirmed.

**⚠️ "Value" / "Done Value" is NOT consumer GMV — it's a realised/net figure ≈ 40 % of gross MRP:**
- swiggySec June raw `GMV` (= units × `BASE_MRP`, gross) = **₹67.41 M**, but dashboard "Done Value" (`SecMaster.sales_amt`) = **₹28.91 M** → ratio **0.43**.
- blinkitSec June raw gross MRP = **₹41.69 M** vs SecMaster value **₹16.75 M** → ratio **0.40**.
- The factor is *systematic* (~0.40 across platforms) ⇒ SecMaster applies a realisation/margin haircut to sticker MRP (mirrors Amazon's `shipped_revenue_after_margin`, which deducts the 25 % `margin_pct`). The exact `SecMaster.sales_amt` formula is **not reproducible from raw alone** (server-side).
- **This independently *confirms* the value-chain ₹/L:** realised per-litre lands at ₹197 (Swiggy) – ₹240 (Blinkit), bracketing Home's Secondary **₹218.2/L** — i.e. the value-chain card uses realised price, not MRP.

**🔬 Taxonomy refinement — `item_head` is SKU-level, NOT a pure category lookup.** In
`flipkart_secondary_all`, **MUSTARD and BLENDED appear under BOTH PREMIUM and COMMODITY**
(yellow/premium mustard vs kacchi-ghani mustard split per-SKU). PREMIUM = {CANOLA, COCONUT, GHEE,
GROUNDNUT, OLIVE, SESAME, +premium MUSTARD/BLENDED}; COMMODITY = {SUNFLOWER, SOYABEAN, RICE BRAN,
+commodity MUSTARD/BLENDED}; OTHER = non-oils. So CONTEXT's "premium=X, commodity=Y" is right *as
a tendency* but the real classifier is per-SKU `item_head`, not category.

---

## 3. Data behind it

### 3a. Raw per-platform secondary tables (the SSOT, one schema per marketplace)

Each platform delivers sell-out in its **own native grain** — this is the defining feature of
Secondary (Primary is comparatively uniform):

| Table | Rows | Grain | Date coverage | Key fields |
|---|---:|---|---|---|
| `swiggySec` | 537,624 | order line: **date × city × area × store × SKU** | 2025-08-10 → 2026-06-25 | `CITY`, `AREA_NAME`, `STORE_ID`, `ITEM_CODE`, `UNITS_SOLD`, `GMV`, `BASE_MRP`, `L1/L2/L3_CATEGORY` |
| `blinkitSec` | 128,749 | **date × city × item** | 2024-01-01 → 2026-06-25 | `city_name`, `item_name`, `qty_sold`, `mrp`, `manufacturer_name` |
| `zeptoSec` | 43,656 | **date × city × SKU** | 2025-10-01 → 2026-06-25 | `City`, `SKU Name`, `Sales (Qty) - Units`, `MRP`, `Gross Merchandise Value`, `EAN` |
| `bigbasketSec` | 17,651 | **date_range × city × SKU** | 2024-12-31 → 2026-06-25 | `source_city_name`, `sku_description`, `total_quantity`, `total_mrp`, `total_sales` |
| `flipkartSec` | 21,430 | **order date × location × SKU** | 2025-01-01 → 2026-06-24 | `Location Id`, `SKU ID`, `Gross Units`, `GMV`, `Cancellation/Return/Final Sale Units+Amount`, `Fulfillment Type` |
| `jiomartSec` | 9,434 | **order/invoice line** (full tax detail) | 2025-07-31 → **2026-04-15 (stale)** | `ORDER_DATE`, `BILLING_STATE`, `DELIVERY_STATE`, `DELIVERY_PINCODE`, `ITEM_QUANTITY`, `FINAL_INVOICE_AMOUNT`, GST/TCS/TDS cols |
| `citymallSec` | **0 (empty)** | — | — | table exists, never populated |
| `zomatoSec` | **0 (empty)** | — | — | table exists, never populated |

Amazon is special — it reports at **ASIN** grain with shipped/ordered/returned splits, and gets a
margin-aware **master view** layer:

| Table | Rows | Grain | Notes |
|---|---:|---|---|
| `amazon_sec_daily` | 2,749 | ASIN × **report_date** | 2026-05-01 → 2026-06-24 (recent daily only); `ordered/shipped_revenue`, `ordered/shipped_units`, `customer_returns`, `shipped_cogs` |
| `amazon_sec_range` | 4,240 | ASIN × **from_date→to_date** | range/period aggregates (longer history) |
| `amazon_sec_range_margins` | 114 | ASIN → `margin_pct` | margin lookup (e.g. "Canola 5L" → 25%, "A2 Ghee 1kg" → 20%) |
| `amazon_sec_daily_master_view` | 2,749 | enriched daily | adds `item`, `item_head`, `category`, `sub_category`, `unit_size`, `ordered/shipped_litres`, `per_unit`, `distributor_margin`, `tax` |
| `amazon_sec_range_master_view` | 4,240 | enriched range | adds `shipped_litres`, `margin_pct`, `shipped_revenue_after_margin`, `realise`, `selling_price` — this is what feeds Amazon's secondary dashboards & YoY |
| `flipkart_secondary_all` | 21,430 | enriched flipkartSec | adds `item`, `item_head`, `mapped_category`, `sub_category`, `per_ltr`, `ltr_sold`, `ltr_ordered`, `cancellation_ltr`, `return_ltr`, settlement/packaging cols |

**Enrichment pattern (raw → analyzable):** the native tables carry only platform SKU strings and
units. The `*_master_view` / `flipkart_secondary_all` layers map each SKU to JIVO's taxonomy
(`item`, `item_head` PREMIUM/COMMODITY, `category`, `sub_category`), convert **units → litres**
via `unit_size`/`per_ltr`, and apply margins to get realised value. Example rows:
- `amazon_sec_range_master_view`: ASIN `B0CGN9Y3PT` → `COCONUT 500ML`, PREMIUM, unit_size 0.5,
  729 units → **364.5 L**, margin 25%, `shipped_revenue_after_margin` ₹136,328, `realise` ₹374/L.
- `flipkart_secondary_all`: `Canola 5+1L` → `CANOLA 5+1L`, PREMIUM, `per_ltr` 6, 16 units → **96 L**.

### 3b. Computed secondary dashboards (what the PAGE actually renders)

| Dashboard | What it shows | Source | Grain |
|---|---|---|---|
| `secondary__<platform>` (amazon, bigbasket, blinkit, flipkart, flipkart_grocery, swiggy, zepto) | the per-platform Secondary page: detail rows + PREMIUM/COMMODITY summary + top items | `SecMaster` (Amazon: `*_range_master_view`) | month, per-platform |
| `secondary-yoy-growth` | all-platform 2024/2025/2026 sell-out with YoY % + month-end projection | `SecMaster` + platform masters | year × platform |
| `secondary-years__<platform>` | which years are available per platform (filter metadata) | — | per-platform |
| `secondary-monthly__amazon`, `secondary-monthly__flipkart` | month-by-month trend within a year (shipped vs ordered L, category split, MoM growth) | platform master | month |
| `month-on-month-sale__bigbasket`, `__flipkart_grocery` | current month vs prior-4-months + target + day-pace projection | platform master | month, sub_category/SKU |

**SecMaster** is the combined secondary master (server-side) that fuses the per-platform Sec
tables into one taxonomy-aligned source — every `secondary__*` summary note states *"VALUE uses
`SecMaster.sales_amt`"*.

---

## 4. Drill-down / structure

**Navigation:** Secondary page → pick a **platform** leaf → see that platform's monthly sell-out,
split **PREMIUM / COMMODITY / OTHER**, with **detail rows by `category` × `sub_category` × pack
size (`per_ltr`)** and a **top-items** list. Each detail row carries units, litres, value,
per-litre, and last-month litres.

The conceptual hierarchy (per CONTEXT) is **Category → Sub-category → Platform → SKU (by month)**:
e.g. GROUNDNUT → Swiggy → `GROUNDNUT 1L` 51,362 L / 51,362 units, `GROUNDNUT 5L` 12,800 L / 2,560
units (Jun 2026). The native tables go even finer — down to **city / store / order line / date**
— so sell-out can be sliced geographically or daily when needed.

**Two cross-platform drill-downs sit on top of sell-out:**

- **`state-sales` / `state-sales-detail` — geographic sell-out** (units, **all platforms pooled**,
  35 states, metric = units). Each state row carries a `by_platform` breakdown.
  *June→May 2026 (latest fully-populated = May): total **435,152 units** across 6 channels
  (Amazon, BigBasket, Blinkit, Flipkart, Swiggy, Zepto).* Top states:
  1. **Maharashtra 64,368** (Swiggy 20,653 · Amazon 19,866 · Zepto 16,268)
  2. **Delhi 62,441** (Zepto 23,508 · Amazon 16,163 · Blinkit 11,601)
  3. **Karnataka 45,487** · 4. **Uttar Pradesh 42,253** · 5. **Haryana 40,224**.
  History runs 2024-01 (9,461 units, Blinkit-only) → present — a clean record of channel
  diversification. `state-sales-detail` is the per-state drill template (queried with a `state`
  param at runtime; the changelog holds only the empty template).

- **`top-skus` / `category-sku-breakdown` — SKU leaderboard & category drill.**
  ⚠️ **Both carry `source: "primary"`** — i.e. they currently render **primary (sell-in) litres**,
  not secondary. Top SKUs (June 2026, all-platform): MUSTARD 1L 84,108 L, GROUNDNUT 1L 83,361 L,
  SUNFLOWER 1L 54,411 L, with MoM deltas (mostly steep negatives because June is mid-month).
  `category-sku-breakdown` is **defined for all 10 platforms but never populated** (every snapshot
  = a single "Uncategorized" row, 0 SKUs). See Anomalies.

---

## 5. CONNECTIONS (the important part)

### Secondary ↔ Primary — the sell-in vs sell-out gap
Same units (litres), opposite ends of the pipe. **Primary 484,975 L shipped onto platforms vs
Secondary 560,048 L sold to consumers (Jun 2026).** Secondary > Primary this month means platforms
are **drawing down the stock** they were previously loaded with (selling faster than Jivo is
re-shipping). The **per-litre rises ₹210.3 → ₹218.2** across the boundary = the platform/consumer
markup. The gap, tracked over time, is the truest read on real demand vs channel-stuffing:
- If Primary >> Secondary persistently → inventory piles up on-platform (over-shipping).
- If Secondary >> Primary → platforms are running down stock; primary needs to refill or stockouts
  follow. This is exactly what `month-on-month-sale` projects (e.g. BigBasket June est. 11.1k L vs
  17.0k L target = **−35% to target** → a sell-out shortfall feeding back to primary planning).

### Secondary → Inventory — sell-out depletes stock (the demand side of DOH)
Every unit counted here **leaves** platform/warehouse inventory. Secondary is the **consumption
rate** that the Inventory pages (SOH/DOH, expiry-alerts, `region-doh`) divide *into* stock to get
**Days-on-Hand**: `DOH = Stock ÷ daily secondary run-rate`. So Secondary is the denominator of the
inventory health KPI. High sell-out (e.g. Maharashtra/Delhi) burns DOH fast → replenishment
trigger; weak sell-out + high SOH → **expiry risk** on oil (limited shelf life). Geographic
sell-out (`state-sales`) maps directly onto where stock should be positioned.

### Secondary → Marketing — ad spend driving sell-out
Marketing (platform ad/coupon/brand-fund spend: `*_ads`, `*_coupon`, `*_brandfund`) exists to
**move the Secondary number**. Sell-out is the return side of marketing ROAS: ad spend on a
platform/SKU should show up as lifted `shipped_units`/`shipped_ltr` here. The premium-mix angle
matters — marketing that lifts PREMIUM sell-out (GROUNDNUT/OLIVE @ ₹195–530/L) is worth far more
than commodity (MUSTARD/SUNFLOWER @ ₹158/L) at equal litres. Per-platform secondary value
(`SecMaster.sales_amt`) is the natural numerator for platform-level ROAS.

### Secondary → Targets / Home
`month-on-month-sale` compares current sell-out to **target** and to the trailing 4 months, with a
day-pace **projection** (BigBasket Jun est. 11.1k L; FK-Grocery est. 20.1k L vs 54k target =
−63%). These projections roll into the **Home** Secondary KPI card and the **Target sheet**.
Home's **Category Split "Secondary" toggle** flips the category/premium-mix breakdown from
primary-basis to this sell-out basis (the secondary counterpart of `category-breakdown` /
`category-litres`, which are `source: "primary"`).

### Per-platform growth signals (`secondary-yoy-growth`, litres, vs June anchor)
| Platform | 2024 | 2025 | 2026 (MTD) | YoY | Source |
|---|---|---|---|---|---|
| Amazon | 115,716 | 194,997 | 195,294 | **+0.15%** | `amazon_sec_range_master_view` |
| Blinkit | 22,789 | 64,666 | 69,794 | **+7.93%** | `SecMaster` |
| Swiggy | — | — | 146,668 | new | `SecMaster` |
| Zepto | — | — | 64,852 | new | `SecMaster` |
| BigBasket | — | 9,295 | 9,294 | −0.01% | `SecMaster` |
| Flipkart | — | 26,978 | 19,286 | **−28.51%** | `flipkart_secondary_all` |
| Flipkart Grocery | — | — | 16,129 | new | `flipkart_grocery_master` |
| Amazon MP | — | — | 4,820 | new | `amazon_mp_master` |

Story: Amazon is the mature, flat anchor (~195k L); Blinkit/Swiggy/Zepto are the quick-commerce
growth engine; Flipkart is **declining (−28.5%)** and BigBasket is flat — both worth flagging.

---

## 6. Anomalies / caveats

1. **`citymallSec` and `zomatoSec` are empty** (0 rows) — no secondary page leaf exists for them,
   even though both have `secondary-years` filter files (zomato also has a `category-litres`
   dashboard, but it is `source: "primary"`). CityMall/Zomato sell-out is effectively un-tracked.
2. **`top-skus` & `category-breakdown` / `category-litres` are `source: "primary"`** — they render
   sell-**in**, not sell-out, despite living near the Secondary surface. Don't read top-skus litres
   as consumer sell-through. The true secondary SKU detail is inside `secondary__<platform>`
   (`details` / `top_items`).
3. **`category-sku-breakdown` never populated** — schema supports Category→Sub-cat→Platform→SKU,
   but every snapshot (2023→2026) is a single "Uncategorized" row with 0 SKUs. Feature is dormant.
4. **Partial-month distortion (June 2026).** Most June numbers are MTD (max_date 2026-06-24/25,
   ~24–25/30 days). Hence the large negative MoM deltas in `top-skus`/`secondary-monthly` and the
   gap between the YoY MTD total (526,138 L) and Home's 560,048 L card. Use the `projection` fields
   (e.g. all-platform 642,901 L) for full-month comparisons.
5. **`jiomartSec` is stale** — last order date **2026-04-15** (vs 2026-06-25 for the live
   platforms). JioMart secondary is ~2.5 months behind; it has no `secondary__jiomart` page and is
   absent from `secondary-yoy-growth`.
6. **`state-sales` metric is units only** (`units == value` in the rows; no litres, no premium
   split, no revenue) and **caps at 6 platforms** — Swiggy/Amazon/Zepto/Blinkit/BigBasket/Flipkart.
   JioMart/CityMall/Zomato are excluded. June 2026 state rows read 0 (not yet populated → use May).
7. **Heterogeneous native grains** make cross-platform sell-out non-trivial: Swiggy/Blinkit/Zepto
   give clean date×city×SKU units; BigBasket uses `date_range`; Flipkart splits
   gross/cancellation/return/**final-sale**; JioMart is invoice-level with full GST. The
   `*_master_view` / `SecMaster` layers exist precisely to normalize this — trust those for
   roll-ups, the raw tables for forensics.
8. **"Value" ≠ consumer GMV (≈40% of MRP).** Confirmed by computation (§2.5): every `*Sec` raw
   table stores **gross MRP** value (`GMV`/`mrp`/`total_sales` = qty × sticker), while the
   dashboards' "Done Value" uses `SecMaster.sales_amt` ≈ 0.40× that. Anyone summing raw GMV will
   overstate revenue ~2.3×. Use realised value (₹/L ≈ 197–240) for money, raw units/litres for volume.
9. **`blinkitSec.mrp` is an aggregate, not a unit price** — `mrp` = `qty_sold` × per-unit-MRP
   (e.g. 33 units × ₹1499 = 49,467). Do not read it as a price. (zepto `MRP`/swiggy `BASE_MRP` *are*
   per-unit; their `GMV` is the aggregate.) Column semantics differ per platform — read each schema.
10. **Amazon range master views are NOT additively summable.** `amazon_sec_range_master_view`
    June-2026 rows sum to **2,082,801 L** — ~10× the true Amazon-2026 figure of 195,294 L — because
    the table holds **multiple overlapping `from_date→to_date` range snapshots**. The dashboards
    de-overlap by selecting the correct range; a naive `SUM(shipped_litres)` massively double-counts.
    (`amazon_sec_daily` and `flipkart_secondary_all` *are* line-additive; the *range* views are not.)
11. **`flipkart_secondary_all.mapped_category` carries junk OTHER values** — alongside real non-oils
    (HONEY, SEEDS, SPICES, TEA, DRINKS, RICE) the OTHER bucket contains garbage strings (`Crypto`,
    `Ferrero`, `FlipPRo`, `Casserole`, `LUNCH BOX`, `ELEGANCE`). Volume is ~0 L so it doesn't distort
    totals, but the category mapper is imperfect on Flipkart's free-text SKU strings.

---

## 7. UNDERSTANDING COVERAGE

Self-assessment of how well each artifact is understood, with the evidence that grounds it.
**FULLY** = grain + semantics verified against raw data; **PARTIAL** = structure known, some
semantics inferred; **UNCLEAR** = cannot reproduce / unverifiable from the extract.

### Tables
| Table | Status | Evidence / why |
|---|---|---|
| `swiggySec` | **FULLY** | grain date×city×area×store×SKU confirmed; June units 122,220 ≈ dash 122,457; GMV=units×MRP verified |
| `blinkitSec` | **FULLY** | June units 54,334 == dashboard exactly; `mrp`=aggregate semantics nailed down |
| `zeptoSec` | **FULLY** | grain date×city×SKU; `GMV`==`MRP`×units verified on samples |
| `bigbasketSec` | **PARTIAL** | grain/fields clear; `date_range` (single date vs span?) and `total_sales` realisation not reconciled to a dashboard |
| `flipkartSec` | **FULLY** | gross/cancel/return/final-sale split clear; superseded by `flipkart_secondary_all` |
| `flipkart_secondary_all` | **FULLY** | enriched layer; June ltr_sold 19,286 == yoy exactly; item_head/category mapping inspected (junk noted) |
| `jiomartSec` | **PARTIAL** | invoice/GST grain clear, but **stale to 2026-04-15**, no dashboard, excluded from yoy — can't reconcile |
| `amazon_sec_daily` / `_daily_master_view` | **PARTIAL** | ASIN×date grain + enrichment fields clear; only 2026-05→06 daily history; not reconciled to a daily dashboard |
| `amazon_sec_range` / `_range_master_view` | **PARTIAL** | feeds Amazon yoy (195,294 L) which ties out, BUT raw rows are **overlapping ranges, non-additive** (sum=2.08M L) — must de-overlap, logic not fully reproduced |
| `amazon_sec_range_margins` | **FULLY** | simple ASIN→`margin_pct` lookup (e.g. Canola 5L 25%, A2 Ghee 20%); drives after-margin value |
| `citymallSec`, `zomatoSec` | **FULLY** (as empty) | 0 rows confirmed; no secondary page exists for them |
| `SecMaster` (combined master) | **UNCLEAR** | not in the 41-table extract (server-side); its `sales_amt` realisation (~0.40× MRP) is the one figure I can't reproduce |

### Pages / dashboards
| Page | Status | Evidence / why |
|---|---|---|
| `secondary__<platform>` (7 leaves) | **FULLY** | structure, PREMIUM/COMMODITY summary, top_items, detail rows all parsed; units tie to raw |
| `secondary-yoy-growth` | **FULLY** | per-platform 2024/25/26 + projection; sums verified to total 526,138 L |
| `secondary-years__<platform>` | **FULLY** | confirmed = filter metadata (available years), not totals |
| `secondary-monthly__{amazon,flipkart}` | **PARTIAL** | monthly shipped/ordered + MoM read off; only 2 platforms have it; ordered-vs-shipped definition inferred |
| `month-on-month-sale__{bigbasket,fk_grocery}` | **PARTIAL** | target + 4-month + day-pace projection clear; only 2 platforms; target source is another domain |
| `state-sales` | **FULLY** | units-only, 6 platforms, `by_platform` split; May-2026 435,152 u, top Maharashtra 64,368 verified in doc |
| `state-sales-detail` | **PARTIAL** | drill template only; changelog holds empty template (runtime `state` param) — couldn't see populated output |
| `top-skus` | **PARTIAL→caveat** | structure clear & values read, but `source:"primary"` ⇒ it shows sell-IN, not secondary; mislabelled for this page |
| `category-sku-breakdown` | **UNCLEAR** | schema defined for 10 platforms but **never populated** (single "Uncategorized", 0 SKUs) — intent inferred, behaviour unseen |
| Home "Secondary" toggle / Category Split | **PARTIAL** | secondary counterpart of `category-breakdown`/`category-litres` (which are `source:"primary"`); exact toggle wiring owned by Home (W-Home) |

### Metrics
| Metric | Status | Evidence / why |
|---|---|---|
| `shipped_units` / Done Qty | **FULLY** | reconciles to raw units across platforms |
| `shipped_ltr` / Done Liters | **FULLY** | ties out (flipkart 19,286; cross-platform 526,138); = units × pack litres via `unit_size`/`per_ltr` |
| `shipped_value` / Done Value | **PARTIAL** | = `SecMaster.sales_amt` ≈ 0.40× gross MRP; realised not gross — factor measured, formula UNCLEAR |
| `per_liter_shpd` (₹/L) | **FULLY** | = value÷litres; ₹197–240 brackets value-chain ₹218.2/L — cross-confirms the chain |
| premium-mix (`item_head`) | **FULLY** | PREMIUM/COMMODITY/OTHER split verified; classifier is **per-SKU**, not per-category (MUSTARD/BLENDED in both) |
| YoY / MoM growth % | **FULLY** | recomputable from yearly actuals (e.g. Blinkit 64,666→69,794 = +7.93%) |
| month-end `projection` | **FULLY** | = actual × days_in_month ÷ elapsed_day **per platform**, then summed (Amazon 195,294×30/24 = 244,118 ✓; Blinkit 69,794×30/25 = 83,753 ✓; Σ = 642,901) |
| `state-sales` "value" | **UNCLEAR** | rows have `units == value` (no separate revenue/litres) — metric is unit count mislabelled "value" |
