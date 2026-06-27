# JIVO — Inventory & Marketing, 2026 (current state + trend), with a price-competitiveness read

> **Scope.** Deep-dive into JIVO's platform **inventory health**, **marketing spend/return**, and a
> **price-competitiveness** read for 2026. **Primary source:** the extracted SSOT under
> `/root/jivo-intel/store/versioned/` (tables `*.changelog.jsonl` = full rows; `dashboards/*.changelog.jsonl`
> = the app's own computed page views), all from the **2026-06-27 pull**. Price-competitiveness also
> cross-references the **live competitor pricematch** at `/opt/ecom-intel/data/pricematch/` (refreshed
> through **2026-06-27**). Model context: `/root/jivo-intel/docs/app-model/inventory-marketing-distributor.md`.
> **All figures recomputed from the rows for this doc** (not copied from the model); deltas and broken bits flagged inline.
>
> **Read-me on grain.** Inventory tables carry many dated snapshots in one extract — "latest" = max
> `inventory_date` per table; "trend" = last snapshot of each month. SOH is reported in the unit each
> platform exposes (Amazon = units + ₹ value; Swiggy/Zepto/Blinkit = units; BigBasket = units + ₹;
> the unified `all_platform_inventory` = **litres**). Litres and units are different measures — don't add across.

---

## 0. Executive read (the four things that matter)

1. **Inventory is well-stocked but lumpy, and one platform is dead.** Unified platform stock on 2026-06-26 = **294,013 L** (64% PREMIUM). Amazon rebuilt from 58k→112k sellable units across H1; Zepto grew 17k→100k units. **JioMart is effectively wound down** (sellable inventory = **0 since 2026-04-16**).
2. **The live stock-out cost is real and rising.** Swiggy's **potential GMV loss = ₹16.96M** on 2026-06-26 (up from ~₹13.7M two days earlier), **43% of it concentrated in DOH<7 SKUs**; 198 SKU-rows sit at DOH<7 and 128 are already at DOH 0.
3. **Marketing is efficient and Amazon-deep.** ₹25.3M spend → ₹354.5M attributed sales → **blended ~14× ROAS**; Zepto best (18.7×), BigBasket worst (6.5×). But coverage windows are wildly uneven (Amazon 55 days vs Zepto 10 / BigBasket 5), so cross-platform ROAS is not apples-to-apples.
4. **JIVO's premium price is under sustained undercut.** Live pricematch (2026-06-27): of 174 actively-priced JIVO listings, **74 (43%) sit BELOW the agreed reference price**, ₹5,709 exposure; **Flipkart and Amazon are the worst** (Extra Virgin 2L −18.9% on Flipkart, Groundnut 5L −21.9% on Amazon). The Amazon `amazon_price_data` lens agrees: JIVO ASP sits **above the live shelf on 89 of 95 ASIN pairs** — resellers undercut it almost everywhere.

---

## 1. INVENTORY HEALTH 2026

### 1.1 Current snapshot — per platform (latest `inventory_date`)

| Platform | Snapshot | Stock on hand | Value / extra | Open-PO pull | Health flag |
|----------|----------|--------------:|---------------|-------------:|-------------|
| **Amazon** (vendor-central) | 2026-06-24 | **111,880 units** sellable | ₹54.93M sellable; unsellable ₹0.25M/575u; **aged-90-day ₹0.53M/1,065u** | **165,351** | DOH ≈ **21.4 d** (dashboard); unfilled cust-ordered 7,323 |
| **Swiggy** (richest schema) | 2026-06-26 | **79,640 units** avail (719 SKU-rows) | **potential GMV loss ₹16.96M**; 36 facilities / 20 cities | **93,103** | **198 rows DOH<7, 128 at DOH 0**, 138 zero-stock; median DOH 26 |
| **Zepto** | 2026-06-26 | **99,671 units** (428 rows) | 65 cities | — | Grew 6× over H1 (Jan 16.8k → Jun 99.7k) |
| **Blinkit** | 2026-06-26 | **53,068 units** (backend 32,913 + frontend 20,155) | 59 facilities | — | Sliding this week (61.3k 06-22 → 53.1k 06-26) |
| **BigBasket** | 2026-06-26 | **15,709 SOH** | **₹6.90M** value | — | Cyclical (oscillates 3k–17k month-to-month) |
| **JioMart** | 2026-06-22 | **0 sellable** (22 rows, 1 RFC) | 76 unsellable units only | — | **DORMANT — no sellable stock since 2026-04-16** |
| CityMall, Zomato | — | empty tables (`expected_empty`) | — | — | not instrumented |

**Unified view** (`all_platform_inventory`, litres, latest 2026-06-26, 1,742 rows): **294,013 L** =
SWIGGY 104,000 / BLINKIT 85,966 / ZEPTO 76,373 / BIG BASKET 27,674. Tier mix **188,651 L PREMIUM (64%) /
105,362 L COMMODITY (36%)**. **19% of SKU-location rows are at zero SOH** (339/1,742) — i.e. ~1 in 5
SKU×store cells is locally stocked-out. *Caveat: this unified table carries only those 5 formats — **Amazon and
Flipkart stock are NOT in it**; their inventory lives only in the per-platform tables, so anyone reading
`all_platform_inventory` as "all platforms" undercounts by Amazon's ~112k units.*

### 1.2 Trend across 2026 (last snapshot of each month)

| Metric | Jan | Feb | Mar | Apr | May | Jun |
|--------|----:|----:|----:|----:|----:|----:|
| Amazon sellable **units** | 58,003 | 57,069 | 36,063 | 50,481¹ | 58,582 | 111,880 |
| Amazon sellable **₹** | 33.6M | 30.2M | 19.5M | ~24M¹ | 32.8M | **54.9M** |
| Amazon open-PO qty | 56,590 | 53,202 | 169,604 | (corrupt)¹ | 147,012 | 165,351 |
| Amazon aged-90-day **₹** | 3.91M | 2.37M | 1.30M | — | 0.80M | **0.53M** |
| Swiggy potential GMV loss **₹** | 9.97M | 11.75M | 11.27M | 9.80M | 9.61M | **16.96M** |
| Swiggy open-PO qty | 51,169 | 40,708 | 28,698 | 148,342 | 84,514 | 93,103 |
| Zepto units | 16,769 | 19,190 | 56,573 | 45,900 | 71,119 | **99,671** |
| Blinkit total qty | 18,423 | 28,491 | 21,796 | 20,505 | 78,951 | 53,068 |
| BigBasket SOH | 14,390 | 3,774 | 14,454 | 3,340 | 9,957 | 15,709 |
| **JioMart sellable** | 7,198 | 6,837 | 4,623 | **1** | **0** | **0** |
| Unified total **litres** | 149,351 | 30,712 | 195,892 | 156,993 | 317,384 | 294,013 |

¹ **The 2026-04-15 Amazon snapshot is corrupt** — see §1.4. April Amazon figures use the clean 2026-04-14 snapshot (50,481 u); open-PO for April is unusable.

**What the trend says:**
- **Amazon was rebuilt in H1.** Sellable units bottomed at 36k in March, then doubled to **112k by June** (₹54.9M); **aged-90-day overstock fell from ₹3.91M → ₹0.53M** — a genuine clean-up of slow/old stock. Open-PO held high (~165k) → strong replenishment pull into JM.
- **Zepto is the growth story** — 6× more units on shelf in June than January.
- **Swiggy stock-out cost spiked late June** — potential GMV loss jumped from ₹9.6M (May) and ~₹13.7M (06-24) to **₹16.96M (06-25/26)**, a ~24% step-up in two days; this is unserved demand driven by low stock, not a static label.
- **JioMart died mid-April.** Sellable inventory hit 1 unit on 2026-04-16 and has been **0 ever since** (last 6 weeks: 22 rows, 1 RFC, 76 unsellable). Either the feed stalled or JioMart was wound down — flag to owner.
- Unified-litres month-to-month is **volatile** (Feb 30.7k L is an obvious partial-feed day, not a real 80% crash) — read the per-platform unit series, not the unified-litre swings, for true direction.

### 1.3 Expiry risk (June 2026, `platform-expiry-alerts` roll-up — POs flagged on days-to-expiry)

| Platform | Litres at risk | POs | (value field) |
|----------|---------------:|----:|--------------:|
| **City Mall** | **51,756 L** | 5 | ₹7.37M — *dominant exposure* |
| **Swiggy** | **12,326 L** | 31 | ₹2.38M — *most POs* |
| Zepto | 989 L | 3 | ₹0.22M |
| Zomato | 890 L | 2 | ₹0.17M |
| Blinkit | 888 L | 7 | ₹0.17M |
| BigBasket | 312 L | 1 | ₹0.08M |

City Mall is **>4× any other platform** for expiry-risk litres despite its own inventory table being empty —
the risk lives in the PO layer (`master_po.days_to_expiry`), not in stock snapshots. *Note: the current
roll-up has **no Amazon row** (the model's earlier "Amazon 15,794 L / 4 POs" is not in this snapshot —
Amazon expiry is tracked via its own `aged_90_days_*` columns instead, currently a modest ₹0.53M).*

### 1.4 Inventory data-quality flags (broken / stale)

- 🔴 **Corrupt Amazon snapshot 2026-04-15** — 50 rows where `asin == product_title` (literally the ASIN string, some rows just `"ASIN"`) **and** `sellable_on_hand_units == sellable_on_hand_inventory == open_purchase_order_quantity` (same number in all three — impossible: units can't equal a rupee value can't equal open-PO). A placeholder/test upload. It silently inflates any "last-April" aggregate to a spurious 139,550. Exclude this date.
- 🔴 **`inventory-match__*` returns `{"match": null}` for all 10 platforms** — the JM-stock ↔ platform-stock reconciliation screen is hollow; there is no working JM-vs-platform cover view in the live app.
- 🟠 **`soh-doh` top-level `totals` are 0 for Swiggy/Blinkit/Zepto/BigBasket** (only Amazon's totals populate, 258,041 L). Use `region-doh` or the raw tables for non-Amazon DOH.
- 🟠 **JioMart inventory dormant** (sellable 0 since mid-April).
- 🟠 **No `jm_inventory` table** — JM's own warehouse stock is only derivable from the PO lineage, never directly sourced.
- ⚪ CityMall & Zomato inventory tables empty by design; `all_platform_inventory` excludes Amazon/Flipkart.

---

## 2. MARKETING 2026

### 2.1 Ad spend → attributed sales → ROAS, per platform (full extract window)

| Platform | Rows | Days | Window | Spend ₹ | Attributed sales ₹ | ROAS (ratio-of-sums) |
|----------|-----:|-----:|--------|--------:|-------------------:|---------------------:|
| **Zepto** | 560 | 10 | 05-19 → 06-25 | 7,453,358 | 139,365,497 | **18.70** |
| Swiggy | 249 | 11 | 05-19 → 06-25 | 9,139,333 | 123,284,657 | 13.49 |
| Amazon | 50,503 | 55 | 05-01 → 06-25 | 4,704,549 | 51,769,215 | 11.00 |
| Blinkit | 1,073 | 56 | 05-01 → 06-25 | 2,806,456 | 29,450,800 | 10.49 |
| Flipkart | 7,965 | 32 | 05-01 → 06-21 | 1,069,187 | 9,739,593 | 9.11 |
| BigBasket | 40 | 5 | 04-30 → 06-10 | 137,940 | 554,520² | 6.50 / 4.02² |
| **TOTAL** | | | | **25,310,823** | **354,506,392** | **~14.0** |

² BigBasket: ₹554,520 is direct ad-revenue only (ROAS 4.02); including same/other-SKU halo revenue it's ₹896,630 (ROAS 6.50). Tiny 40-row, 5-day sample either way.

> **Caveat — uneven depth.** Amazon 55 days / Blinkit 56 / Flipkart 32 vs **Swiggy 11, Zepto 10, BigBasket 5**.
> The quick-commerce ROAS league above rests on ~1–2 weeks. Also the app's on-screen Amazon ROAS uses
> **avg-of-ratios** (≈15.8) not ratio-of-sums (11.0) — read the table as ratio-of-sums. Attributed-sales
> definitions differ by platform (Amazon `sales`, Swiggy `total_gmv`, Blinkit `direct+indirect_gmv`,
> Zepto `revenue`, Flipkart `total_revenue`), so the blended ~14× is indicative, not strictly comparable.

### 2.2 Amazon marketing (the only platform with deep, dashboard-live data)

- **986 campaigns**, 66.86M impressions, 289,822 clicks → **CTR 0.43%**, **ACOS 9.09%** (ACOS is dashboard-derived, not stored), 112,914 units sold.
- Sales mix: promoted ₹18.83M, **halo ₹3.44M**, **NTB (new-to-brand) only ₹1.36M = 3% of sales** → spend is mostly defending existing buyers, not acquiring new ones.
- **Month-over-month**: May ₹2.98M spend → ₹34.4M (11.5×); June ₹1.72M → ₹17.4M (10.1×) — efficiency softened slightly into June.
- **Top portfolios by spend** (spend → ROAS): Groundnut ₹1.01M (10.8×), Canola ₹0.62M (10.8×), Extra Light ₹0.51M (10.7×), Pomace ₹0.36M (11.9×), Mustard ₹0.36M (14.8×). **Best ROAS: Sunflower 18.1×**; weakest: Extra Virgin 7.2×.

### 2.3 Coupons & brand-fund

- **Amazon coupons** (`amazon_coupon`, 795 rows): total budget ₹3.88M, **spent ₹0.95M (only 24% utilised)**, **44,257 redemptions**, 109,053 clips, discount given ₹0.95M. Top by spend: POMACE 5 (₹112k, 2,908 red.), CANOLA 5 (₹95k, 63% used, 3,685 red.), POMACE 1 (4,823 red.). Big unused budget headroom.
- **Brand-fund (co-funded trade discount):** Blinkit **₹1.69M** (423 rows, 60% non-zero), Zepto **₹0.41M** (44 rows, 100% populated), Swiggy **₹1,178** (411 rows, only **9% non-zero — effectively unwired/empty**).

### 2.4 ROAS-type signals available per platform

Zepto carries `roas` + `robas` + same/other-SKU halo; Swiggy carries `total_roi` + 7/14-day direct-ROI;
Flipkart `roi`; Blinkit direct vs indirect (halo) GMV; Amazon the richest (`roas`, derived `acos`, `ctr`,
`cpc`, NTB%, promoted, halo, detail-page-view funnel). **So a return signal exists for every platform** —
but only **Amazon's dashboards render live**; the other platforms' ad data exists as tables only (their
per-platform marketing dashboards are server-gated).

### 2.5 Marketing data-quality flags

- 🟠 Non-Amazon ad/coupon/price dashboards are **server-gated** — tables exist, rendered pages don't.
- 🟠 Swiggy brand-fund **effectively empty** (9% of rows have spend); Blinkit brand-fund `offer_type` is `"None"` on all rows.
- 🟠 QC ad windows are 5–11 days → cross-platform ROAS not comparable without normalising.
- ⚪ Amazon coupon budget is 76% unspent → either conservative clip strategy or under-promotion headroom.

---

## 3. PRICE COMPETITIVENESS 2026

Two independent lenses, telling the same story: **JIVO's premium/agreed price is routinely undercut.**

### 3.1 Lens A — live competitor shelf vs agreed price (`/opt/ecom-intel/data/pricematch/`, **fresh through 2026-06-27**)

This is the maintained price-match engine: it watches JIVO's **own** listings across 8 platforms and scores
the live modal shelf price against the **agreed reference** (`ref_price`) for that day's price plan
(**BAU** = weekday list; **SVD** = Special Value Days, Fri–Sun + first 7 days of any month). `diff =
live_modal − ref_price`; **negative = selling below the agreed floor (a violation)**.

**Latest snapshot 2026-06-27 (SVD day)** — 113 SKUs × 8 platforms = 904 listings:

| Status | Count | Meaning |
|--------|------:|---------|
| **BELOW** | **74** | shelf below agreed floor (violation) |
| ABOVE | 41 | overpriced (sales risk) |
| MATCH | 59 | at agreed price |
| OOS | 117 | out of stock |
| NOT_LISTED | 613 | SKU not carried on that platform |

→ Of the **174 actively-priced listings (BELOW+ABOVE+MATCH), 43% are BELOW the agreed price.** Exposure
(total ₹ gap below agreed) = **₹5,709**; **store-level violations = 2,444**.

**By platform on 2026-06-27 (undercut exposure):** Amazon ₹1,553 (18 listings below) · Flipkart ₹1,347 (10) ·
Blinkit ₹671 (9) · Amazon-Fresh ₹647 (10) · Zepto ₹569 (10) · Amazon-Now ₹564 (10) · BigBasket ₹261 (5) ·
Flipkart-Minutes ₹98 (3). **Amazon + Flipkart carry the most undercut.**

**Worst current undercuts:** Extra Virgin 2L on Flipkart −₹300 (**−18.9%**) · Extra Light 3L Flipkart −₹274
(−15.3%) · Sano Pomace 5L Flipkart −₹263 · Groundnut 5L Amazon −₹256 (**−21.9%**) · Extra Virgin 5L Amazon
−₹240 · Jivo Pomace 5L on Amazon-Now/Blinkit −₹202.

**20-day trend (2026-06-06 → 06-27, `daily.csv`):** below-ref listings ranged **74–139 (mean 96)**; exposure
**₹5,709–₹11,426 (mean ₹8,633)**; store violations **1,977–3,949 (mean 2,819)**. **Violations run higher on
BAU days** (the weekday agreed price is higher, so a discounted shelf breaches it more often) and ease on SVD
days. The latest reading (₹5,709, 74 below) is the **lowest exposure in the window** — compliance improving
into late June.

*Coverage caveat:* only **113 SKUs are mapped** (291 listing mappings); **613 of 904 daily cells are
NOT_LISTED**. Scope is deliberately locked to the agreed ~113-SKU master (per project policy) — this is the
agreed-price universe, not the full catalogue.

### 3.2 Lens B — JIVO ASP vs resellers on Amazon (`amazon_price_data`, **STALE 2-date snapshot**)

192 rows / 96 ASINs, uploaded only **2026-05-12 and 2026-05-14** (one-shot, not a series). It holds JIVO's
intended `asp` and `margin_pct` alongside scraped competing-seller prices (`url_price` = live buy-box,
`rk_price` RK World, `jm_price` Jivo Mart, `svd_price`, `bau_price`, `art_price`).

- **Margin discipline holds:** `margin_pct` median **25%** (range 18–25%); MRP→ASP discount median **37%**.
- **Stock health in the snapshot is poor:** 95 In Stock vs **94 Out of Stock** (~half the catalogue OOS).
- **JIVO is undercut almost everywhere it can be measured:**
  - JIVO `asp` is **above the live shelf (`url_price`) on 89 of 95 pairs (94%)** — only 5 below.
  - Reseller columns below ASP: **art_price 186/192, svd_price 140/192, bau_price 94/192, rk_price 88/88, url_price 89/95**.
  - Biggest gaps (ASP − shelf): **Jivo Pomace 5L ASP ₹2,799 vs shelf ₹1,899 (+₹900)**, Extra Virgin 5L +₹875, Extra Light 5L +₹658.
- 🔴 **Quality is poor:** `jm_price` is **null on 72% of rows** (only 54 populated) and carries outliers (the model's flagged A2 Ghee 1L `jm_price` ₹129 vs ASP ₹1,579). Treat no seller column here as a clean time series — **use Lens A for anything current.**

### 3.3 Combined read

Both lenses converge: **JIVO's listed/agreed price sits above the price the product actually transacts at**,
because resellers and grey-market sellers (RK World, SVD, BAU, ART) undercut the same ASINs — heaviest on
**Amazon and Flipkart**. Margin is held at 18–25% on paper (Lens B), but the consumer-facing shelf is below
the agreed floor on ~40% of active listings (Lens A). Coupons (₹0.95M, 76% budget unused) and brand-fund
(₹2.1M across Blinkit+Zepto) are the levers to close that gap legitimately — currently under-deployed.

---

## 4. Sources & provenance

- **Inventory:** `all_platform_inventory` (174,155 rows), `amazon_inventory` (12,899), `swiggy_inventory`
  (73,667), `blinkit_inventory` (29,161), `zepto_inventory` (34,937), `bigbasket_inventory` (36,895),
  `jiomart_inventory` (2,267) — all `*.changelog.jsonl`, 2026-06-27 pull. Dashboards: `soh-doh__amazon`
  (DOH 21.4, DRR 8,137 L/day), `platform-expiry-alerts` (June roll-up).
- **Marketing:** `amazon_ads` (50,503), `swiggy_ads`, `zepto_ads`, `blinkit_ads`, `flipkart_ads`,
  `bigbasket_ads`; `amazon_coupon` (795); `blinkit/zepto/swiggy_brandfund`.
- **Price:** `amazon_price_data` (192 rows, 2-date) + live `/opt/ecom-intel/data/pricematch/history.csv`
  (18,080 rows, 2026-06-08→27) and `daily.csv` (2026-06-06→27). Regime semantics from
  `tools/pricematch/regime.json` + `DASHBOARD-STYLE.md`. Latest figures reconcile exactly with the shipped
  `Jivo-Price-Match-2026-06-27.xlsx.summary.json` (74 below / 41 above / 59 match / 117 OOS / ₹5,709 exposure).
- All numbers in this doc were recomputed directly from the rows on 2026-06-28; data-quality issues are
  flagged 🔴 (broken) / 🟠 (stale/partial) / ⚪ (empty-by-design) inline.
