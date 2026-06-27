# JIVO — SECONDARY (consumer sell-out) Deep-Dive, 2026 (Jan–Jun)

> **What this is.** A month-by-month read of what shoppers actually *bought off* JIVO's e-commerce
> platforms in H1-2026 — by platform, by PREMIUM/COMMODITY, with the SKU, geography and
> target-attainment detail. **Secondary = sell-OUT** (last link of the chain), vs **Primary = sell-IN**
> (what JIVO ships onto the platforms).
>
> **Sources (all mined, nothing re-pulled):**
> - `/root/jivo-intel/docs/app-model/target-history.csv` (2026-06-28 pull) — the spine: secondary
>   `done_ltrs` + `targets` + `est_ltr` per **platform × item_head × month** for all of 2026. This is
>   the app's `secmaster` sell-out series and is cross-validated below.
> - `store/versioned/dashboards/secondary__<platform>` — June per-platform snapshots (premium/commodity
>   litres, realised value, ₹/L, top SKUs).
> - `secondary-yoy-growth` — June-over-June (2024/25/26) per-platform.
> - `secondary-monthly__{amazon,flipkart}` — within-year monthly series (used to validate).
> - `state-sales__2026-MM` — geographic sell-out (units, all platforms pooled).
> - `docs/app-model/secondary.md` — the domain model.
>
> **Premium vs commodity** (per the app's per-SKU `item_head`): **PREMIUM** = canola, groundnut,
> olive/pomace, sesame, coconut, ghee, yellow/premium mustard; **COMMODITY** = kacchi-ghani mustard,
> sunflower, soyabean, rice-bran, gold/blended. All volumes in **litres (L)** unless stated.
>
> **Five timing/quality rules — read everything through these:**
> 1. **June is live/MTD** (~24–26 days of 30). June actuals are understated ~15–25%; the `est_ltr`
>    straight-line projection is the fair full-month figure. Both are shown.
> 2. **April is a partial/frozen snapshot** — its actuals are truncated and unreliable. The April "dip"
>    below is a **data artifact, not a demand collapse**. **May is the first fully-trustworthy recent
>    full month.** Jan–Mar are clean full months.
> 3. **Targets exist only from Apr-2026.** Achievement is an Apr–Jun metric; Jan–Mar have actuals only.
> 4. **"Value" ≠ consumer GMV.** Dashboard "Done Value" = `SecMaster.sales_amt` ≈ realised price
>    (~0.40× gross sticker MRP). Use it for money and ₹/L; never sum raw GMV (overstates ~2.3×).
> 5. **CityMall & Zomato are sheet-only** (their scraper tables are empty). They appear in the target
>    sheet but their item_head splits look like mapping defaults (Zomato 100% premium, CityMall ~98%
>    commodity) — treat their internals with caution. **JioMart is stale** (to 2026-04-15) and absent
>    from the live secondary views.

---

## 1. Executive summary

- **H1-2026 sell-out ≈ 3.63 M L** across 10 reported platforms (Jan–Jun, June MTD); **≈3.78 M L** with
  June projected. **Premium mix 46.3%** for the half (1.68 M L premium vs 1.95 M L commodity).
- **The mix is shifting premium**: 40% (Jan/Feb) → low-50s by June, driven by Zepto, Flipkart, Swiggy
  trading up and by the commodity-heavy laggards (CityMall, FK-Grocery) shrinking.
- **Two engines, one anchor, four laggards.** **Zepto (+74% Q1→Q2)** and **Swiggy (+14%, now the #1
  quick-commerce platform at 156k L in June)** are the growth engines; **Amazon** is the flat mature
  anchor (~36% of all sell-out, +0.15% June YoY). **Flipkart (−37%), Flipkart-Grocery (−53%), CityMall
  (−50%), Zomato (−23%)** are all declining.
- **Targets:** **May 83%** attainment (premium 77% / commodity 90%), **June 70% MTD → 82% projected**.
  GROUNDNUT 1L is the volume hero; MUSTARD 1L the commodity workhorse. Sell-out concentrates in
  Maharashtra + Delhi (≈28% of national units).

---

## 2. Month-by-month, all platforms (litres)

| Month | Total L | MoM | PREMIUM L | COMMODITY L | Premium-mix | Note |
|---|---:|---:|---:|---:|---:|---|
| Jan | 658,326 | — | 263,075 | 395,251 | **40%** | clean |
| Feb | 565,044 | −14.2% | 227,908 | 337,136 | **40%** | clean |
| Mar | 584,267 | +3.4% | 259,224 | 325,043 | **44%** | clean |
| Apr | 438,536 | −24.9% | 237,681 | 200,855 | **54%** | ⚠ truncated/frozen — understated |
| May | **801,401** | +82.7% | 385,371 | 416,030 | **48%** | **peak full month** |
| Jun (MTD) | 583,695 | −27.2% | 309,185 | 274,510 | **53%** | live; **proj ≈ 729,234** |
| **H1** | **3,631,269** | | **1,682,444** | **1,948,825** | **46.3%** | June MTD |

**How to read it:** the Apr trough and the May "+82.7%" rebound are largely the **April-truncation
artifact** plus a **genuine May surge** (Amazon's May spike — see §4). Ignoring April, the clean
full-month signal is **Jan ~658k → Mar ~584k → May ~801k**, i.e. the platform base is *growing* into Q2,
led by quick-commerce. June projects to ~729k, just below the May peak.

**Premium-mix evolution:** **40% → 40% → 44% → 54%(Apr, denominator effect) → 48% → 53%.** Stripping the
truncated April, the real arc is a steady climb from **40% in Q1 to low-50s by June** — a structural
trade-up toward margin-rich oils.

---

## 3. Sell-out by platform (litres)

### 3a. Monthly matrix (done_ltrs)

| Platform | Jan | Feb | Mar | Apr* | May | Jun(MTD) | **H1** | H1 share |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Amazon** | 228,006 | 174,761 | 203,019 | 173,097 | **328,428** | 204,174 | **1,311,487** | **36.1%** |
| **Swiggy** | 118,278 | 103,018 | 111,765 | 84,920 | 139,364 | **156,022** | **713,366** | **19.6%** |
| **Blinkit** | 66,457 | 63,920 | 76,199 | 28,858 | 86,601 | 72,727 | **394,762** | 10.9% |
| **Zepto** | 27,537 | 33,236 | 58,268 | 62,059 | 76,426 | 68,404 | **325,930** | 9.0% |
| **Flipkart** | 61,119 | 36,455 | 38,969 | 21,100 | 42,890 | 21,642 | **222,174** | 6.1% |
| CityMall† | 59,534 | 66,503 | 14,132 | 3,707 | 49,089 | 17,715 | 210,680 | 5.8% |
| Flipkart Grocery | 49,833 | 36,587 | 36,466 | 16,004 | 25,100 | 16,129 | 180,119 | 5.0% |
| Zomato† | 35,632 | 33,643 | 30,894 | 32,379 | 33,718 | 11,472 | 177,738 | 4.9% |
| BigBasket | 11,931 | 16,921 | 14,434 | 12,466 | 14,792 | 9,870 | 80,414 | 2.2% |
| Amazon MP | 0 | 0 | 120 | 3,946 | 4,993 | 5,541 | 14,600 | 0.4% |
| **ALL** | 658,326 | 565,044 | 584,267 | 438,536 | 801,401 | 583,695 | **3,631,269** | |

`*` April truncated. `†` CityMall/Zomato sheet-only (empty scraper tables — internals unreliable).
*Validation: per-platform `done_ltrs` here matches `secondary-monthly__amazon` shipped_ltr exactly (e.g.
Amazon premium Jan 93,148 / May 147,569) and the per-platform June `secondary__` dashboards — the series
is trustworthy.*

### 3b. Growth vs decline (Q1 Jan–Mar → Q2 Apr–Jun; Q2 carries June MTD so is ~10% understated)

| Platform | Q1 L | Q2 L | Q1→Q2 | Verdict |
|---|---:|---:|---:|---|
| **Zepto** | 119,041 | 206,889 | **+74%** | 🟢 star grower |
| **Amazon** | 605,786 | 705,699 | **+16%** | 🟢 anchor, lifted by May |
| **Swiggy** | 333,061 | 380,306 | **+14%** | 🟢 now #1 quick-commerce |
| Blinkit | 206,576 | 188,186 | −9% | 🟡 soft (April dip) |
| BigBasket | 43,286 | 37,128 | −14% | 🟡 small & flat |
| Zomato† | 100,169 | 77,569 | −23% | 🔴 declining (sheet-only) |
| **Flipkart** | 136,543 | 85,632 | **−37%** | 🔴 declining |
| **CityMall†** | 140,169 | 70,511 | **−50%** | 🔴 collapsing (sheet-only) |
| **Flipkart Grocery** | 122,886 | 57,233 | **−53%** | 🔴 collapsing |

Single-month Jan→Jun (June projected) tells the same story even harder: **Zepto +187%, Swiggy +52%**,
Amazon ~flat (+/− around the May spike), vs **Flipkart −59%, FK-Grocery −67%, CityMall, Zomato all down**.

---

## 4. Per-platform deep-dive — June 2026 detail

From the `secondary__<platform>` dashboards (SecMaster / range master views, June MTD). Value = realised
`sales_amt`; ₹/L is the realised consumer price.

| Platform | June L | Units | Value (₹) | ₹/L | PREMIUM (L @ ₹/L) | COMMODITY (L @ ₹/L) | Prem-mix |
|---|---:|---:|---:|---:|---|---|---:|
| **Amazon** | 195,294 | 114,720 | ₹4.49 cr | 230 | 93,307 @ **288** | 101,987 @ 176 | 48% |
| **Swiggy** | 146,668 | 122,457 | ₹2.89 cr | 197 | 78,642 @ 230 | 68,026 @ 159 | 54% |
| **Blinkit** | 69,794 | 54,334 | ₹1.67 cr | **308** | 39,638 @ **399** | 30,156 @ 191 | 57% |
| **Zepto** | 64,852 | 91,653 | ₹1.48 cr | 228 | 48,882 @ 244 | 15,970 @ 179 | **76%** |
| **Flipkart** | 19,286 | 5,398 | ₹0.58 cr | **300** | 14,446 @ **333** | 4,840 @ 202 | **74%** |
| Flipkart Grocery | 16,129 | 15,322 | ₹0.26 cr | 158 | 999 | 15,130 | 6% |
| BigBasket | 9,294 | 6,977 | ₹0.17 cr | 178 | 2,067 @ 240 | 7,227 @ 153 | 22% |

**Reads:**
- **Amazon** — the mature anchor: 36% of all H1 sell-out, balanced 48% premium, mid ₹230/L. Carried a
  **genuine May spike (328k L vs ~175–203k other months)** — an Amazon summer-sale surge that drove the
  all-platform May peak; it is real (de-overlapped, cross-validated), not a range-view double-count.
- **Swiggy** — the **#1 quick-commerce platform** and rising (June 156k L, +14% Q1→Q2). Premium-mix
  climbed 34%→53% across H1. Volume hero GROUNDNUT 1L alone = 51,362 L (₹1.0 cr) in June.
- **Blinkit** — small-but-rich: highest realised **₹308/L** and a stand-out **premium ₹399/L**
  (POMACE/CANOLA skew). Flat overall (−9% Q1→Q2, the April dip); +7.93% June YoY.
- **Zepto** — the **growth star**: +74% Q1→Q2, **76% premium-mix** (highest of the real platforms),
  GROUNDNUT-led. From 27.5k L (Jan) to ~79k L (June projected).
- **Flipkart (core)** — **richest mix (74% premium, ₹300/L) but shrinking volume** (−37% Q1→Q2, −28.5%
  June YoY). A premium-but-fading channel.
- **Flipkart Grocery & BigBasket** — commodity-heavy (94% / 78% commodity), low ₹/L, both small and soft.

---

## 5. Top SKUs & movers (June 2026)

Aggregating the per-platform `top_items` (a floor, since each list is truncated):

| SKU | ≈June L (cross-platform) | Class | Where it sells |
|---|---:|---|---|
| **GROUNDNUT 1L** | **~79,100** | PREMIUM | Swiggy 51,362 · Zepto 27,777 — the #1 hero |
| **MUSTARD 1L** | **~66,400** | COMMODITY/premium-split | Swiggy 25,242 · Blinkit 18,380 · FK-Groc 13,777 · Zepto 8,426 — the volume workhorse |
| **SUNFLOWER 1L** | ~32,500 | COMMODITY | Swiggy 18,408 · Zepto 6,124 · BB 4,084 · Blinkit 3,891 |
| **JIVO POMACE 1L** (olive) | ~19,500 | PREMIUM | Blinkit 14,039 · Zepto 5,284 — premium star, ₹324–348/L |
| GROUNDNUT 5L | ~12,800 | PREMIUM | Swiggy |
| SUNFLOWER 5L | ~13,500 | COMMODITY | Swiggy 11,885 · BB 1,645 |
| CANOLA 1L | ~10,600 | PREMIUM | Blinkit 9,173 · FK-Groc · BB |
| GROUNDNUT 200ML | ~7,700 | PREMIUM | Zepto — high realised ₹/L small-pack |
| GOLD 1L / EXTRA LIGHT 1L | ~6–7k each | blended/premium | Swiggy / Zepto |

**Mover signal:** the premium heroes (GROUNDNUT, POMACE, CANOLA) are the ones *growing* via Zepto/Swiggy;
the commodity workhorses (MUSTARD, SUNFLOWER) hold the base volume. The premium-mix lift in §2 is exactly
this: groundnut/pomace gaining share on the quick-commerce platforms.

> Note: the `top-skus` dashboard is `source:"primary"` (sell-IN) — **not** used here. SKU figures above
> come from the genuine secondary `secondary__<platform>.top_items`.

---

## 6. Geography (state-sales, units — all platforms pooled)

`state-sales` is **units**, 35 states, 6 core platforms (Amazon, Swiggy, Zepto, Blinkit, BigBasket,
Flipkart; excludes CityMall/Zomato/JioMart). **June is corrupt** (Amazon over-counted to 753k units vs
~155k in May) — so **May 2026 is the clean reference**: **435,152 national units, 35 states.**

| State | May units | % national | Leading platform |
|---|---:|---:|---|
| **Maharashtra** | 64,368 | 14% | Swiggy (20,653) |
| **Delhi** | 62,441 | 14% | Zepto (23,508) |
| Karnataka | 45,487 | 10% | Swiggy (17,432) |
| Uttar Pradesh | 42,253 | 9% | Amazon (17,080) |
| Haryana | 40,224 | 9% | Zepto (10,666) |
| Punjab | 36,007 | 8% | Blinkit (22,459) |
| Telangana | 29,107 | 6% | Swiggy |
| West Bengal | 16,832 | 3% | Amazon |

**Top-5 states = ~56% of national units** — sell-out is metro/north-and-west concentrated.
Platform totals (May units): Amazon 155,159 · Swiggy 106,286 · Zepto 82,498 · Blinkit 66,317 ·
Flipkart 13,012 · BigBasket 11,870. Monthly national-unit trend (clean months): Jan 286k · Feb 258k ·
Mar 306k · Apr 246k(truncated) · **May 435k**. Quick-commerce (Swiggy/Zepto/Blinkit) wins the metros;
Amazon leads the broader/tier-2 geographies (UP, WB).

---

## 7. Targets vs Done vs Achieved (Apr–Jun, like-for-like)

Achievement summed **only over platform-cells that have a target set** (the honest, apples-to-apples
basis). Litres.

| Month | PREMIUM tgt→done (ach%) | COMMODITY tgt→done (ach%) | ALL tgt→done (ach%) |
|---|---|---|---|
| **Apr** ⚠ | 168,668 → 150,434 (**89%**) | 252,900 → 95,054 (**38%**) | 421,568 → 245,488 (**58%**) |
| **May** | 499,000 → 385,371 (**77%**) | 464,000 → 416,030 (**90%**) | 963,000 → 801,401 (**83%**) |
| **Jun** (MTD) | 372,000 → 297,601 (**80%**) | 419,000 → 256,907 (**61%**) | 791,000 → 554,508 (**70%**) |
| **Jun** (projected) | → 348,224 (**94%**) | → 302,839 (**72%**) | → 651,064 (**82%**) |

April's 38% commodity is the truncation artifact (don't trust it). **May is the clean attainment read:
83% overall — commodity (90%) actually beat premium (77%).** June is pacing to **~82% projected** (premium
strong at 94%, commodity lagging at 72%).

**Platform attainment standouts (May, closed month):** Amazon **100%** (328k vs 330k target), Swiggy
**95%**, CityMall 94%, BigBasket 87%, Blinkit 86%, Zepto 83%. **Misses:** Flipkart **50%**, Flipkart
Grocery **46%**, Amazon MP **20%**. (April outliers like Zepto 215% / Zomato 108% are truncation noise.)

---

## 8. June-over-June YoY context (`secondary-yoy-growth`, litres, June MTD anchor)

| Platform | Jun-2024 | Jun-2025 | Jun-2026 | YoY |
|---|---:|---:|---:|---:|
| Amazon | 115,716 | 194,997 | 195,294 | **+0.15%** (flat anchor) |
| Blinkit | 22,789 | 64,666 | 69,794 | **+7.93%** |
| BigBasket | — | 9,295 | 9,294 | −0.01% |
| Flipkart | — | 26,978 | 19,286 | **−28.5%** |
| Swiggy | — | — | 146,668 | new in 2026 |
| Zepto | — | — | 64,852 | new in 2026 |
| Flipkart Grocery | — | — | 16,129 | new in 2026 |
| Amazon MP | — | — | 4,820 | new in 2026 |

All-platform June total (8 scraper platforms) = **526,138 L MTD → 642,901 L projected** (Home card reads
560,048 L). The 2026 story vs prior years: Amazon matured to a flat ceiling after its 2024→25 doubling;
the **new quick-commerce platforms (Swiggy 147k, Zepto 65k) are the entire growth story**; Flipkart is the
one shrinking incumbent.

---

## 9. Standouts and weak spots

**🟢 Standouts**
- **Zepto** — fastest grower (+74% Q1→Q2, +187% Jan→Jun proj) *and* the richest real mix (76% premium).
  Doing the right thing: growing volume while trading up.
- **Swiggy** — became the **#1 quick-commerce sell-out platform** (156k L June), +14% with premium-mix up
  34%→53%. GROUNDNUT 1L is a ₹1-cr/month SKU here.
- **Premium trade-up** — overall mix 40%→low-50s; premium realises ₹230–399/L vs commodity ₹150–200/L, so
  this is margin accretive.
- **Amazon May surge** — a real 328k-L spike, the engine of the all-platform May peak (801k L); Amazon
  also hit 100% of its May target.

**🔴 Weak spots**
- **Flipkart (core)** — premium-rich (74%, ₹300/L) but **volume down −37% Q1→Q2 and −28.5% June YoY**, and
  only ~50% of target. A high-quality channel quietly bleeding volume.
- **Flipkart Grocery** — **−53% Q1→Q2**, 94% commodity, 46% of May target. Weakest trajectory of the real
  platforms.
- **Commodity attainment** — June commodity pacing only 61% MTD / 72% projected vs target; the commodity
  book (mustard/sunflower) is consistently underselling its plan while premium hits ~94%.
- **BigBasket** — stuck small and flat (~80k L H1, −14%, −0.01% YoY).
- **Data-quality flags:** CityMall (−50%) and Zomato (−23%) are **sheet-only with mapping-default splits**
  — their numbers shouldn't drive decisions without source data; JioMart is stale (Apr-15); the June
  `state-sales` Amazon figure is corrupted (use May for geography).

---

## 10. Data lineage & caveats (one place)

1. **Spine = `target-history.csv` (secondary rows, 2026)** — `done_ltrs` per platform×item_head×month;
   cross-validated against `secondary-monthly__amazon` (exact match) and the June `secondary__` dashboards.
2. **June MTD ≈ 24–26/30 days** → understated; `est_ltr` is the straight-line month-end projection.
3. **April is a truncated/frozen snapshot** — its actuals (and the Apr dip + commodity-38%) are artifacts.
4. **Targets only from Apr-2026**; achievement is Apr–Jun, computed like-for-like (cells with target>0).
5. **Value = realised `SecMaster.sales_amt` ≈ 0.40× gross MRP** — used for ₹ and ₹/L; never sum raw GMV.
6. **CityMall & Zomato = sheet-only** (empty scraper tables; suspicious 100%/98% single-class splits);
   **JioMart stale** to 2026-04-15; both excluded from the live secondary roll-ups.
7. **`state-sales` = units** (not litres), 6 platforms; **June Amazon over-counted** → use May.
8. **Amazon range master views are non-additive**; the monthly Amazon series here uses the app's
   de-overlapped excel-month-end filter (validated), so Amazon monthly litres are trustworthy.

*Built 2026-06-28 from the SSOT extract under `/root/jivo-intel/store/versioned/` and
`/root/jivo-intel/docs/app-model/`. Read-only mine; no data re-pulled.*
