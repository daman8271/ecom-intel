# Target Sheets — the `/monthly-targets` page (Secondary & Primary monthly targets)

> The single page where JIVO **sets the month's litre goals per platform** and tracks **actual-vs-target
> day by day**. It is the team's scoreboard: a refreshed snapshot is **posted to the group every day**, so
> these numbers drive the daily sales conversation. Everything is in **litres (L)**, split **PREMIUM vs
> COMMODITY**, **per platform (FORMAT)**, **per month**.
>
> Evidence: `store/versioned/dashboards/month-targets__<slug>.changelog.jsonl` (Secondary track) and
> `primary-month-targets__<slug>.changelog.jsonl` (Primary track). All numbers below are real values from
> the 2026-06-27 pull.

---

## 1. What the page is

Two tabs, each with a **PREMIUM / COMMODITY toggle** and a **month picker**:

| Tab | Backing dashboard | `type` field | What it measures |
|-----|-------------------|--------------|-------------------|
| **Secondary Targets** | `month-targets__<slug>` | (mixed — see anomaly) | **Sell-OUT** — litres that sell through to **consumers** on the platform |
| **Primary Targets** | `primary-month-targets__<slug>` | `prim` | **Sell-IN** — litres Jivo **ships to the platform** (POs delivered) |

The grid the owner sees (columns `FORMAT, DATE, TARGETS, DONE LTRS, ACHIEVED %, EST.LTR, EST.LTR%`) is one
row **per platform** for the selected month and toggle. `FORMAT` = the platform (SWIGGY, AMAZON, …); `DATE`
= the as-of date of the snapshot. The Primary tab additionally exposes the pacing columns (`DRR`,
`REQUIRE DRR`, `PENDING`, `DP LTRS`).

**This is the one authored (write) surface** in an otherwise read-only stack: targets are typed in here
(or via Uploaders), so every row carries `created_at` / `updated_at`. Actuals (`done_ltrs`) are pulled in
automatically from the sales masters and refreshed daily.

---

## 2. Secondary vs Primary — and the value chain

JIVO's funnel is a price-rising litre chain (Home KPI cards, Jun 2026):

```
Wellness Billing 811,616 L @ ₹180/L  →  JM Primary 672,739 L @ ₹192.6/L
   →  PRIMARY 484,975 L @ ₹210.3/L (sell-IN to platforms)
      →  SECONDARY 560,048 L @ ₹218.2/L (sell-OUT to consumers)
```

- **Primary target = the SELL-IN goal.** "How many litres should we *ship into* each platform's warehouse
  this month (POs delivered)?" Source = `master_po` (purchase-order master). This is the supply-side
  commitment — it must be paced so stock lands before it can sell.
- **Secondary target = the SELL-OUT goal.** "How many litres should *consumers buy* off each platform this
  month?" Source = `secmaster` (secondary-sales master) for most platforms. This is the demand-side result —
  the number that actually realises revenue (`done_value`).

The two are **deliberately different numbers for the same platform/month/head** — Secondary measures
through-the-till, Primary measures into-the-warehouse, and they pace differently (you can over-ship and
under-sell, or vice-versa). Example, **Swiggy June '26 PREMIUM**: Secondary done **78,642 L** (131% of a
60k target) but Primary done only **53,952 L** (49% of a 110k target) — consumers are pulling faster than
Jivo is restocking. The opposite case, **Swiggy May '26 COMMODITY**: Primary 103,478 L (sell-in) vs
Secondary 80,999 L (sell-out) — shipped in more than sold through (inventory built).

---

## 3. Metric dictionary (every column, with the exact formula)

All formulas were reverse-engineered and verified against the raw rows. `elapsed = day-of-month in the
DATE field`; `dim = days in that month` (30 for June, 31 for May).

### Shared by both tabs
| Metric | Meaning | Formula / verification |
|--------|---------|------------------------|
| **targets** | The month's litre goal for that platform × item_head. Set by the team. | authored |
| **done_ltrs** | Actual litres achieved so far this month (sell-out for Secondary; PO sell-in for Primary). | pulled from sales master |
| **achieved_pct** | Progress against the goal. | `done_ltrs / targets`. Swiggy Jun COMM = 68,026 / 80,000 = **0.8503 (85.0%)** ✓ |
| **est_ltr** | **Month-end PROJECTION** — where you'll land at today's pace (a straight-line extrapolation). | `done_ltrs × dim / elapsed`. Swiggy Jun COMM (DATE 06-25): 68,026 × 30/25 = **81,631 L** ✓ |
| **est_ltr_pct** | Projected achievement vs goal. | `est_ltr / targets` = 81,631 / 80,000 = **1.0204 (102%)** ✓ |

> **How the projection is derived (important):** it is **pure pace / DRR-based linear extrapolation** —
> take what's done, divide by days elapsed, multiply by days in the month. In a **closed** month the DATE
> is the month-end, so `elapsed = dim` and **`est_ltr == done_ltrs`** (the projection collapses onto the
> actual — visible in every May/April row). In the **live** month (June) the DATE lags (e.g. 06-24/25/26),
> so `est_ltr > done_ltrs` and the projection is meaningful. No smoothing or seasonality — just today's
> run-rate held flat to month-end.

### Secondary-only columns
| Metric | Meaning | Formula / verification |
|--------|---------|------------------------|
| **done_value** | Rupee value of the sell-out so far (the realised revenue). | Swiggy Jun PREM done 78,642 L → **₹17,258,028** ≈ ₹219.4/L (matches the secondary ₹218.2/L ladder) |
| **est_value** | Projected month-end revenue. | `done_value × dim / elapsed` |
| **last_month** | Prior month's **done_ltrs** (the comparison base). | Swiggy Jun COMM last_month = **80,999** = May COMM done ✓ |
| **growth** | **Projected** month-end litres vs last month's actual. | `est_ltr − last_month`. Swiggy Jun COMM = 81,631 − 80,999 = **+632 L** ✓ |
| **growth_pct** | Same, as a percentage. | `growth / last_month` = 632 / 80,999 = **+0.78%** ✓ (Swiggy Jun PREM = +61.7%) |

### Primary-only columns (the operational pacing engine)
| Metric | Meaning | Formula / verification |
|--------|---------|------------------------|
| **drr** | **Daily Run Rate** — average litres/day shipped so far this month. | `done_ltrs / elapsed`. Swiggy Jun COMM = 62,446 / 24 = **2,601.9 L/day** ✓ |
| **pending_ltr** | Litres still to go to hit the target (0 once beaten). | `targets − done_ltrs`. Swiggy Jun COMM = 200,000 − 62,446 = **137,554** ✓ |
| **require_drr** | The DRR you'd need **for the rest of the month** to still hit target — the gap-closer. | `pending_ltr / (dim − elapsed)`. Swiggy Jun COMM = 137,554 / (30−24) = **22,925.7 L/day** ✓ |
| **dp_ltrs** | **Dispatch-plan litres** — the committed plan; equals the target, but is bumped up to actual once actual overshoots. | `max(targets, done_ltrs)`. Under-shoot rows show dp = target (Swiggy Jun COMM dp 200,000); over-shoot rows show dp = done (BigBasket Jun COMM tgt 7,000 / done 16,881 / **dp 16,881**) ✓ |

> **`require_drr` vs `drr` is the hinge of the whole page.** If `require_drr >> drr`, the target is
> mathematically slipping away. Swiggy Jun COMM needs **22,926 L/day** but is running **2,602 L/day** —
> ~9× behind, so the 31% achieved will not recover. This single comparison is what the daily group post is
> really about.

---

## 4. PREMIUM vs COMMODITY split, and the per-platform breakdown

Every row is tagged `item_head` = **PREMIUM** (value oils: canola, groundnut, pomace/olive, sesame, yellow
mustard, ghee…) or **COMMODITY** (staples: mustard kacchi-ghani, sunflower, soyabean, rice-bran, gold).
A third tag **OTHER** (non-oils) appears once (FK-Grocery May, target 9,000 L, done 0). Targets are set
separately for each head, and the PREMIUM/COMMODITY toggle simply switches which head's rows show. This is
the same premium-vs-commodity axis as Home's Category Split, so target attainment ties straight back to the
headline **premium-mix** KPI.

### Aggregate (summed across platforms), litres

**Secondary (sell-out):**
| Month | Head | Target | Done | Achieved |
|-------|------|--------|------|----------|
| 2026-04 | PREMIUM | 168,668 | 150,434 | 89.2% |
| 2026-04 | COMMODITY | 292,900 | 95,054 | 32.5% |
| 2026-05 | PREMIUM | 479,000 | 380,648 | 79.5% |
| 2026-05 | COMMODITY | 459,000 | 415,760 | 90.6% |
| 2026-06 | PREMIUM | 367,000 | 277,982 | 75.7% |
| 2026-06 | COMMODITY | 412,000 | 243,336 | 59.1% |

**Primary (sell-in):**
| Month | Head | Target | Done | Achieved |
|-------|------|--------|------|----------|
| 2026-05 | PREMIUM | 415,000 | 318,081 | 76.6% |
| 2026-05 | COMMODITY | 294,000 | 247,106 | 84.0% |
| 2026-06 | PREMIUM | 536,000 | 261,592 | 48.8% |
| 2026-06 | COMMODITY | 857,000 | 250,947 | 29.3% |

(Note Primary's June commodity goal jumped to **857k L** — a big sell-in push that is running far behind.)

### Per-platform — **June 2026 (live month)**

**Secondary tab (sell-out), June:**
| Platform | PREMIUM tgt → done (ach / est%) | COMMODITY tgt → done (ach / est%) |
|----------|-------------------------------|----------------------------------|
| amazon | 160,000 → 93,307 (58% / 73%) | 180,000 → 101,987 (57% / 71%) |
| swiggy | 60,000 → **78,642 (131% / 157%)** | 80,000 → 68,026 (85% / 102%) |
| zepto | 55,000 → 48,882 (89% / 107%) | 30,000 → 15,970 (53% / 64%) |
| blinkit | 60,000 → 39,638 (66% / 79%) | 35,000 → 30,156 (86% / 103%) |
| flipkart | 25,000 → 14,446 (58% / 72%) | 35,000 → 4,840 (**14% / 17%**) |
| flipkart_grocery | 2,000 → 999 (50% / 62%) | 40,000 → 15,130 (38% / 47%) |
| bigbasket | 5,000 → 2,067 (41% / 50%) | 12,000 → 7,227 (60% / 72%) |
| citymall | — *(no June secondary row)* | — *(no June secondary row)* |
| zomato | — *(no June secondary row)* | — *(no June secondary row)* |

**Primary tab (sell-in), June — pacing view:**
| Platform | COMMODITY tgt → done (ach) · drr → require_drr | PREMIUM tgt → done (ach) |
|----------|----------------------------------------------|--------------------------|
| swiggy | 200,000 → 62,446 (31%) · 2,602 → **22,926** | 110,000 → 53,952 (49%) · req 9,341 |
| flipkart_grocery | 200,000 → 18,178 (**9%**) · 790 → 25,975 | 2,000 → 1,988 (99%) |
| citymall | 150,000 → 17,603 (12%) · 1,956 → 6,305 | 2,000 → 112 (6%) |
| amazon | 180,000 → 101,987 (57%) · 3,923 → 19,503 | 160,000 → 93,307 (58%) · req 16,673 |
| blinkit | 70,000 → 13,704 (20%) · 571 → 9,383 | 120,000 → 16,494 (14%) · req 17,251 |
| zepto | 50,000 → 20,148 (40%) · 806 → 5,970 | 100,000 → 68,451 (69%) · req 7,887 |
| bigbasket | 7,000 → **16,881 (241% — beat)** | 2,000 → 2,241 (112% — beat) |
| zomato | — *(no commodity)* | 40,000 → 25,047 (63%) · req 2,492 |
| flipkart | — *(no Primary rows at all — empty)* | — |

For comparison, **May 2026 (closed)** shows several wins: Primary Swiggy COMM 103,478/100,000 (**103%**),
Blinkit COMM 62,704/50,000 (**125%**) and PREM 118,846/100,000 (**119%**); Secondary BigBasket COMM
11,832/12,000 (99%), Zepto COMM 25,898/25,000 (104%).

---

## 5. How it connects to the rest of the app

- **Primary tab ↔ Primary page.** `primary-month-targets` (`type=prim`, `source=master_po`) is the *true
  Primary* target: its `done_ltrs` are the PO sell-in actuals shown on the Primary page, and its `drr`
  is the same daily-run-rate that the per-platform **`drr` Insights** dashboard exposes. The Primary page
  documents this leaf explicitly (`primary.md` §7).
- **Secondary tab ↔ Secondary page.** `month-targets` (`source=secmaster`) carries the sell-out
  `done_ltrs` / `done_value` that the Secondary page reports; the `month-on-month-sale` dashboards
  (BigBasket, FK-Grocery) carry the **same target + day-pace projection** logic, feeding the Home
  Secondary KPI card (`secondary.md` §Targets/Home).
- **Home KPI cards.** Home shows **actuals** for Primary (484,975 L) and Secondary (560,048 L); the Target
  sheet is the goal/pacing layer underneath them. There is **no aggregate target roll-up on Home** — the
  Target sheet is consumed per platform.
- **Item_head axis.** PREMIUM/COMMODITY here is the same split as Home's Category Split and the premium-mix
  KPI, so missing a premium target directly dents the premium-mix story.
- **The daily-posting workflow (why this page exists).** Each day the actuals refresh (DATE advances,
  `done_ltrs` grow, `drr`/`est_ltr`/`require_drr` recompute — note `updated_at` stamps like
  2026-06-26 on June rows), then a snapshot of the sheet is **posted to the team group**. The page is the
  daily accountability artefact: "at today's run-rate, where do we land, and what daily rate still closes
  the gap?" `require_drr` is the actionable number that conversation hinges on.
- **Authoring path.** Targets are set on this page / via **Uploaders**; actuals flow up from the
  `master_po` (Primary) and `secmaster` (Secondary) sales masters. It is the only place numbers are
  written into this read-only surface.

---

## 6. Anomalies & caveats

1. **Targets started part-way through 2026 — early months are blank.**
   - **Primary has NO April data at all** — Primary targets begin in **May 2026** (only May & June rows
     exist on every platform). Secondary goes back to April for most platforms.
   - **Secondary April is missing for amazon and flipkart_grocery** (they begin in May). So "over the
     years" history does not exist in this extract — the targets endpoint returns only a recent snapshot
     (April–June 2026).
2. **`jiomart` has NO targets at all.** Despite being a tracked platform (full sales/inventory/state-sales
   dashboards exist), there is **no `month-targets__jiomart` and no `primary-month-targets__jiomart`** file.
   jiomart is unmanaged on the target sheet.
3. **`flipkart` Primary is empty.** `primary-month-targets__flipkart` exists but has **0 data rows** — no
   sell-in targets were ever set for Flipkart (it has Secondary targets, but no Primary).
4. **The `type` field on the Secondary track is inconsistent — do not trust it to identify the track.**
   The task framing labelled Secondary as `type=B2C`; in reality the field is mixed per platform:
   `amazon` & `flipkart` = **B2C**, but `bigbasket/blinkit/swiggy/zepto/citymall/zomato/flipkart_grocery`
   = **B2B**. The reliable discriminators are the **dashboard key** (`month-targets` vs
   `primary-month-targets`) and the **`source`** field. (Primary is consistently `type=prim`,
   `source=master_po` — the task's "type=sec" label does not appear in the data.)
5. **Secondary `source` also varies per platform:** mostly `secmaster`, but `amazon`→`amazon`,
   `flipkart_grocery`→`flipkart_grocery`, and `citymall`/`zomato`→`master_po`. The citymall/zomato
   secondary rows being sourced from `master_po` means their "sell-out" figures may actually be
   PO-derived — treat those two platforms' Secondary numbers with caution.
6. **Projection is naïve linear pace** — `done × days_in_month / days_elapsed`, no seasonality, no
   day-of-week weighting, no weekend effect. Early in the month a few strong days can inflate `est_ltr`
   wildly. Extreme case: **Zepto April PREMIUM** target 8,798 L, done 43,655 L → **496% achieved** (the
   target was set far too low, not a real 5× beat). Similar over-runs: Blinkit April PREMIUM 176%,
   BigBasket June COMMODITY 241%.
7. **Coverage is uneven across the live month.** citymall and zomato have **no June Secondary rows**
   (last secondary month is May), and zomato has **no COMMODITY** anywhere (premium-only). So the June
   aggregate is summed over a *different platform set* than May — month-over-month aggregate comparisons
   are not strictly like-for-like.
8. **No aggregate target view** — the page is per-platform; there is no captured all-platform target total
   inside the app (the §4 aggregates above were summed by us, and reconcile exactly with the
   `target-timeseries.json` roll-up, e.g. June Secondary PREMIUM 367,000 / 277,982 = 75.7%).
