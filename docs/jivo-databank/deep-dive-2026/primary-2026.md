# JIVO — PRIMARY (Sell-In / PO) Deep-Dive, 2026 (Jan–Jun)

> **Scope.** The operational, PO-level deep-dive of JIVO's **Primary** domain — sell-IN to platforms
> (purchase orders delivered). Where the sibling file
> [`targets-and-bigpicture-2026.md`](./targets-and-bigpicture-2026.md) reads the *target sheet*, this file
> mines the **raw PO book** to show *how* the sell-in actually happened: fill-rate / miss-rate, the open
> order book (pendency), lead-time, vendor accountability, the ₹/L value ladder, and a forensic root-cause
> of the known weak spot — **Primary Commodity**.
>
> **Sources (all extracted, no re-pull):**
> - `store/versioned/tables/master_po.changelog.jsonl` — **44,081 PO lines**, the enriched SSOT (the union
>   of `total_po` 8,239 + `total_po_zbs` 35,842). Carries order/delivered/missed litres, status, vendor,
>   rates, dates, city/state, lead-time, item_head. **Covers 8 platforms — NOT Amazon** (Amazon runs a
>   parallel `reporting."Amazon PO"` feed and is absent from every PO table).
> - `docs/app-model/target-history.csv` (2026-06-28 pull, freshest) — canonical monthly primary `done_ltrs`
>   per platform×head, **including Amazon / Amazon-MP / Flipkart-MP**, plus targets (May/Jun) & achieved%.
> - `store/versioned/dashboards/{fulfilment-health, primary-month-targets__*, pendency__*}` — windowed
>   fill-rate and the live DRR pacing engine.
>
> **Reconciliation that anchors the whole file:** target-history `done_ltrs` == master_po delivery-month
> `filled_ltrs` (e.g. FK-Grocery Jun COMMODITY = **18,178 L** in both). So the two sources are one number
> seen two ways; master_po just exposes the order/miss/pending mechanics behind each `done`.
>
> **Three timing rules (read everything through these):**
> 1. **Litres are the unit.** OTHER item_head (juices/seeds/spices) = units only, **0 L** — it never shows on a litre chart.
> 2. **June is the live month** (data as-of ~2026-06-27). A June *PO cohort* is mid-flight: much of it is
>    still **pending**, not missed. June fill-rate is NOT comparable to closed months.
> 3. **Two date lenses.** *Delivery-month* = when litres landed (the "sell-in happened" view, used for §1/§5).
>    *PO-month cohort* = POs raised in month M, scored on what that cohort filled/missed/pending (used for
>    §2/§3 fill mechanics). State each explicitly; they are not interchangeable.

---

## 0. Headline — H1 2026 Primary at a glance

| Metric | H1 2026 (Jan–Jun) | Source |
|---|---|---|
| **Total primary sell-in (incl Amazon)** | **3,883,009 L** (PREMIUM 1,855,826 + COMMODITY 2,027,183) | target-history `done` |
| of which **Amazon (+MP)** | 1,326,087 L (≈ **34%** of all sell-in) | target-history |
| **master_po sell-in (8 platforms, excl Amazon)** | **2,322,151 L delivered** | master_po, delivery-month |
| **master_po delivered value (excl Amazon)** | ₹52.5 Cr incl-GST · ₹50.0 Cr exclusive · ₹47.5 Cr without-margin | master_po |
| **₹/L ladder (master_po, H1)** | without-margin **₹205/L** → exclusive **₹215/L** → inclusive **₹226/L** | master_po |
| **Premium / Commodity mix (H1 litres)** | 47.8% / 52.2% — commodity slightly larger by litres (bigger packs) | target-history |
| **Current open order book (pendency)** | **189,792 L** across 259 POs / 1,259 lines | master_po PENDING rows |
| **Fill-rate, 30-day lagged window (all 8+Amazon)** | **56.2%** (filled 542,343 / ordered 964,560 L) — Amazon-dragged | fulfilment-health |
| ↳ same window **excl Amazon** | **~68%** (361,803 / 535,318 L) | derived |

**One-line story.** The premium sell-in book is the reliable engine (high-70s/80s attainment); the
**commodity book is the problem child** — and June's 30% commodity attainment is **~70% a target-setting
problem** (targets set 2–4× above the order the platforms actually placed) and only ~30% an execution
problem (soft fill + lengthening lead-times). Amazon is the single biggest sell-in channel (34%) **and** the
worst filler (42%), so it both carries and caps the domain.

---

## 1. Month-by-month sell-in — PLATFORM × PREMIUM/COMMODITY (delivered litres)

Delivery-month view (litres that *landed* that month), incl Amazon, from target-history `done_ltrs`.

### 1.1 PREMIUM sell-in (L)
| Platform | Jan | Feb | Mar | Apr | May | Jun* | H1 |
|---|--:|--:|--:|--:|--:|--:|--:|
| **Amazon** | 93,148 | 77,191 | 85,728 | 82,716 | 147,570 | 97,378 | **583,732** |
| Amazon MP | 0 | 0 | 55 | 3,584 | 4,723 | 5,379 | 13,741 |
| **Swiggy** | 48,711 | 39,990 | 33,270 | 36,903 | 109,022 | 61,871 | **329,766** |
| **Blinkit** | 38,362 | 41,554 | 45,932 | 36,605 | 118,846 | 16,494 | **297,793** |
| **Zepto** | 14,790 | 22,681 | 64,886 | 33,833 | 50,723 | 73,159 | **260,072** |
| **Zomato** | 35,632 | 33,643 | 30,894 | 32,379 | 33,718 | 33,311 | 199,577 |
| Flipkart MP | 34,508 | 22,876 | 21,158 | 14,861 | 31,491 | 16,111 | 141,004 |
| BigBasket | 3,855 | 2,496 | 3,866 | 3,113 | 1,458 | 2,445 | 17,233 |
| FK Grocery | 1,835 | 1,123 | 1,332 | 2,548 | 1,004 | 1,988 | 9,830 |
| CityMall | 1,048 | 731 | 204 | 204 | 780 | 112 | 3,079 |
| **TOTAL** | **271,888** | **242,285** | **287,325** | **246,746** | **499,335** | **308,248** | **1,855,826** |

### 1.2 COMMODITY sell-in (L)
| Platform | Jan | Feb | Mar | Apr | May | Jun* | H1 |
|---|--:|--:|--:|--:|--:|--:|--:|
| **Amazon** | 134,858 | 97,570 | 117,291 | 90,381 | 180,859 | 106,796 | **727,755** |
| **Swiggy** | 80,267 | 69,079 | 61,156 | 62,875 | 103,478 | 68,197 | **445,052** |
| **CityMall** | 58,486 | 65,772 | 13,928 | 3,503 | 48,309 | 17,603 | 207,601 |
| **FK Grocery** | 43,170 | 69,404 | 43,568 | 16,132 | 3,263 | 18,178 | 193,715 |
| **Blinkit** | 17,250 | 31,660 | 31,650 | 11,320 | 62,704 | 13,704 | 168,288 |
| **Zepto** | 18,280 | 23,618 | 25,740 | 23,599 | 23,005 | 20,560 | 134,802 |
| Flipkart MP | 26,611 | 13,579 | 17,811 | 6,239 | 11,399 | 5,531 | 81,170 |
| BigBasket | 8,980 | 8,112 | 14,099 | 10,982 | 6,967 | 18,801 | 67,941 |
| Amazon MP | 0 | 0 | 65 | 362 | 270 | 162 | 859 |
| **TOTAL** | **387,902** | **378,794** | **325,308** | **225,393** | **440,254** | **269,532** | **2,027,183** |

\*June is live/partial (as-of ~06-27); it will close higher than shown.

**What the shape says:**
- **Total sell-in by month:** Jan 660k → Feb 621k → Mar 613k → **Apr 472k (trough)** → **May 940k (peak)** →
  Jun 578k (live). The **April dip + May spike is real in master_po too** (master_po-only delivered Apr
  273,996 L vs May 563,277 L) — a genuine pre-monsoon re-stock surge in May, not just a sheet artifact.
- **Amazon is ~⅓–½ of every month's litres** and the swing factor: its May commodity (180,859 L) and May
  premium (147,570 L) drive the May peak.
- **Quick-commerce trio (Swiggy/Blinkit/Zepto) is the volatile core.** Blinkit premium swings 118,846 (May)
  → 16,494 (Jun); Zepto premium spikes 64,886 in Mar then 73,159 in Jun. These swings are mostly **PO
  timing**, not demand collapse.
- **Marketplace-grocery (CityMall, FK-Grocery) is commodity-skewed and fading** — both were big commodity
  shippers in Jan–Feb (CityMall 58k/66k; FK-Grocery 43k/69k) then fell off a cliff by April. This fade is
  the seed of the June commodity miss (see §4).

---

## 2. Fill-rate & miss-rate trend (PO-cohort, master_po, 8 platforms)

PO-month cohort = POs *raised* in month M. Denominator is **net of cancellations** (cancelled POs never had
a chance to deliver — 508,763 L cancelled across H1, ~13% of gross orders, correctly excluded). For each
cohort: `fill = delivered / net_ordered`, `miss = missed / net_ordered`, remainder = still pending.

| PO month | gross ord | cancelled | net ord | delivered | missed | pending | **fill%** | **miss%** |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Jan | 522,885 | 61,969 | 460,916 | 381,433 | 79,481 | 0 | **82.8%** | 17.2% |
| Feb | 542,147 | 55,338 | 486,809 | 389,508 | 97,302 | 0 | **80.0%** | 20.0% |
| Mar | 579,642 | 75,767 | 503,875 | 375,424 | 128,442 | 9 | **74.5%** | 25.5% |
| Apr | 503,939 | 18,183 | 485,757 | 373,380 | 112,245 | 0 | **76.9%** | 23.1% |
| May | 779,724 | 57,494 | 722,230 | 542,816 | 174,580 | 4,834 | **75.2%** | 24.2% |
| Jun* | 451,657 | 29,177 | 422,480 | 190,899 | 45,808 | 184,949 | 45.2%† | 10.8%† |

\*June cohort is mid-flight — **184,949 L (44% of net) is still pending**, not missed; †these % are not
comparable to closed months.

**Trend:** fill-rate **declined ~8 pts across the closed half** (Jan 82.8% → May 75.2%) while miss-rate
**rose from 17% to 24%**. March was the worst closed month (25.5% miss). This is a slow structural erosion
of fulfilment quality, not a cliff.

### 2.1 Fill% by platform × PO-month (net of cancel)
| Platform | Jan | Feb | Mar | Apr | May | Jun* |
|---|--:|--:|--:|--:|--:|--:|
| Swiggy | 72% | 68% | 66% | 72% | 54% | 40%* |
| Blinkit | 93% | 89% | 84% | 80% | 86% | 42%* |
| Zepto | 89% | 83% | 74% | 85% | 89% | 58%* |
| Big Basket | 86% | 69% | 69% | 64% | 57% | 84% |
| FK Grocery | 99% | 91% | 94% | 90% | 53% | 73% |
| City Mall | 85% | 78% | 56% | 85% | 89% | 0%* |
| Zomato | 86% | 87% | 84% | 90% | 88% | 81% |

**Swiggy is the chronic under-filler** (60s-70s all year, sliding to 54% in May) — it is also the largest
master_po orderer, so its weakness dominates the blended number. **Zomato is the steadiest** (84–90%).
FK-Grocery and CityMall hold high fill *when ordered* but their order volume collapsed (§1.2).

### 2.2 The current 30-day window (fulfilment-health, incl Amazon)
The cleanest live read — a 30-day window (2026-05-21 → 06-20) with a 7-day lag so only deliverable POs count:

| Platform | ordered | filled | **fill%** | miss% | POs |
|---|--:|--:|--:|--:|--:|
| **Amazon** | 429,242 | 180,540 | **42.1%** | 11.6% | 108 |
| **Swiggy** | 222,359 | 114,430 | **51.5%** | **27.5%** | 504 |
| Zepto | 94,787 | 67,847 | 71.6% | 10.2% | 134 |
| FK Grocery | 22,008 | 17,806 | 80.9% | 6.2% | 30 |
| Blinkit | 110,520 | 90,061 | 81.5% | 17.6% | 165 |
| Big Basket | 26,869 | 22,097 | 82.2% | 12.9% | 39 |
| City Mall | 21,028 | 17,715 | 84.2% | 15.8% | 6 |
| Zomato | 37,747 | 31,848 | 84.4% | 10.1% | 45 |
| **TOTAL** | **964,560** | **542,343** | **56.2%** | 15.7% | 1,031 |

**The headline 56.2% is Amazon-dragged.** Amazon alone is 44% of the ordered book and fills only 42%;
strip it out and the 8 master_po platforms run **~68%**. The two big quick-commerce orderers (Amazon,
Swiggy) order the most and fill the worst — the central supply-chain tension of this domain.

---

## 3. Pendency — the open order book *right now*

Current live PENDING rows in master_po (open, not yet expired/missed):

**Total: 189,792 L open · 259 POs · 1,259 lines.** Split COMMODITY 106,307 L / PREMIUM 83,485 L / OTHER 0 L.

| Platform | open pending (L) | lines |
|---|--:|--:|
| **Swiggy** | 94,314 | 889 |
| **City Mall** | 51,756 | 63 |
| **Zepto** | 32,623 | 190 |
| FK Grocery | 5,784 | 15 |
| Big Basket | 2,469 | 83 |
| Zomato | 2,090 | 5 |
| Blinkit | 756 | 14 |

**By fulfilling vendor (who owes delivery):** Sustainquest 73,319 L · Knowtable 65,930 L · Chirag 33,492 L ·
Antize 8,424 L · Evara 4,299 L · Baba Lokenath 4,060 L · **JIVO Mart only 268 L** (confirming JIVO-Mart-the-
vendor is dormant — it delivers ~0 in the live period; "JM Primary" is the upstream rung, not this vendor).

**By destination city (top):** Hyderabad 23,924 L · Lucknow 13,411 · Gurugram 12,996 · Bengaluru 11,914 ·
Dadri 11,484 · Sonipat 10,970 · Bahadurgarh 9,848 · Pune 7,800 · Delhi 7,659 · Mumbai 6,990.

> Swiggy + CityMall + Zepto = **94% of all open pendency.** CityMall's 51,756 L is almost entirely its
> *June commodity* book sitting undelivered (see §4) — a single platform's open commodity orders.

---

## 4. Why Primary COMMODITY is the weak spot (forensic)

The known problem. Aggregate attainment (incl Amazon, target-history): **May commodity 87%** (closed,
healthy) → **June commodity 30%** (live) against a target inflated to **899,000 L (+78% MoM over May's 504k)**.
This is the single biggest miss in the 2026 dataset. Decompose June commodity into its three drivers:

### Driver 1 — Targets set 2–4× above the order book (DOMINANT, ~70% of the gap)
The target was never order-backed. Total commodity **net-ordered in June by the 8 master_po platforms = only
206,730 L** (PO cohort) — yet the target across those same platforms + Amazon was 899k. Per platform:

| Platform | Jun COMM target | actually ordered (PO cohort net) | done | ach% | target ÷ ordered |
|---|--:|--:|--:|--:|--:|
| **FK Grocery** | 200,000 | ~21,756 | 18,178 | **9%** | **9.2×** |
| **City Mall** | 150,000 | ~51,044 | 17,603 | **12%** | **2.9×** |
| **Swiggy** | 200,000 | ~94,737 | 68,197 | **34%** | 2.1× |
| Blinkit | 70,000 | ~2,800 | 13,704 | 20% | (dec. orders) |
| Zepto | 50,000 | ~17,936 | 20,560 | 41% | 2.8× |
| Amazon | 180,000 | n/a (off-model) | 106,796 | 59% | — |
| Big Basket | 7,000 | ~18,457 | 18,801 | **269%** | 0.4× (target too low) |

The **DRR pacing engine confirms mathematical impossibility:** the litres/day still required vs the actual
run-rate — FK-Grocery commodity needs **25,975 L/day**, running **790** (33×); Swiggy needs **22,926**,
running **2,602** (9×); Blinkit needs **9,383**, running **571** (16×). No execution could close gaps this
size; the targets are aspirational, not order-derived. Where targets *were* realistic, commodity hits or
beats (BigBasket 269%, May commodity 87% overall).

### Driver 2 — Mid-month pending, not missed (~timing, will partly recover)
Of June commodity net-ordered (206,730 L), **104,176 L (50%) is still PENDING** as of 06-27 — open, not yet
failed. **CityMall's entire ~51k commodity book is undelivered (0% filled, 100% pending).** This converts as
the month closes, so the 30% `done` understates the eventual landing — but `est%` (run-rate projection) still
only reaches ~35–39%, because even the pending can't lift it to a 2–4× target.

### Driver 3 — Genuine fill weakness (SMALLEST, ~30% of the execution piece)
Where commodity *does* ship, June-cohort fill is soft but miss is low (most non-delivery is pending):
Swiggy commodity fill **46%** (miss 12%), Blinkit **28%** (miss 48% — the one real fill failure), Zepto 66%.
Overall June commodity cohort: fill 43% / **miss only 7%** / pending 50%. So this is **not a miss-rate
collapse** — it's under-ordering + open book against an over-set target.

### Verdict
> **Primary Commodity June ≈ 70% a target-setting/demand problem, ~30% execution.** The commodity target
> (899k) was raised 78% MoM and set 2–4× above what platforms actually order (esp. FK-Grocery 9×, CityMall
> 3×, Swiggy 2×). Half the modest order book is still pending mid-month. Genuine fill failure is confined to
> Blinkit commodity (28%) and Swiggy (46%). **Fix = re-base commodity targets to the order book, and recover
> the FK-Grocery/CityMall commodity order volume that faded after February** (§1.2). Premium is comparatively
> fine (Jun 54% live; engine intact) — the worst premium cell is Blinkit (14%, also an inflated 120k target,
> +20k MoM).

---

## 5. Value chain — the four-rung ladder, 2026 magnitudes

The litre flows down a margin ladder; the same litre gets dearer at each hop (Jun 2026 Home KPI cards):

```
Wellness Billing 811,616 L @ ₹180.0/L   (rung 1: parent factory invoices Jivo, ex-factory)
   →  JM Primary  672,739 L @ ₹192.6/L   (rung 2: Jivo Mart holds & dispatches, +~7%)
      →  PRIMARY   484,975 L @ ₹210.3/L  (rung 3: sell-IN to platforms, +~9%)  ← THIS DOMAIN
         →  Secondary 560,048 L @ ₹218.2/L (rung 4: platforms sell to consumers, +~4%; W3)
```

- **Volume shrinks down (811k→672k→485k):** the gaps are inventory built — 139k L held at Wellness, 188k L
  at JM. **But Secondary (560k) > Primary (485k)** in June ⇒ platforms sold more than Jivo shipped ⇒
  **destocking ⇒ stock-out risk next month** (the single most important cross-page signal).
- **Rungs 1 & 2 (Wellness Billing, JM Primary) are owner-screenshot KPI cards — NOT reproducible from the
  extracted SSOT.** `master_po` begins at the platform-PO layer (rung 3). `prim_master_po` (the natural "JM
  primary master" table) is **empty (0 rows)**, and the JIVO-Mart-vendor proxy fails (≈0 L delivered Apr–Jun;
  see §3). So JM Primary's 672,739 L is authoritative-from-owner only.

**Rung 3 (Primary) IS measurable, and the ₹/L ladder is reproducible inside master_po (2026 H1, excl Amazon):**

| Delivery month | delivered L | incl-GST ₹/L | exclusive ₹/L | without-margin ₹/L | delivered value (incl) |
|---|--:|--:|--:|--:|--:|
| Jan | 372,134 | 219.3 | 208.9 | 198.6 | ₹8.16 Cr |
| Feb | 411,950 | 210.8 | 200.7 | 191.0 | ₹8.68 Cr |
| Mar | 370,537 | 226.5 | 215.7 | 205.0 | ₹8.39 Cr |
| Apr | 273,996 | 251.1 | 239.1 | 227.0 | ₹6.88 Cr |
| May | 563,277 | 228.5 | 217.6 | 206.8 | ₹12.87 Cr |
| Jun* | 330,257 | 228.8 | 216.6 | 205.5 | ₹7.55 Cr |
| **H1** | **2,322,151** | **~226** | **~215** | **~205** | **₹52.5 Cr** |

The per-row ladder steps **without-margin ₹205/L → exclusive ₹215/L → inclusive ₹226/L** — the +₹10/L
exclusive→without is the distributor commission (~5.4% `distributor_margin`), the +₹11/L incl→excl is GST.
Including Amazon (+34% litres) the H1 primary book is **≈ ₹85–90 Cr** at the rung-3 inclusive price.

---

## 6. Lead time & DRR (velocity)

### 6.1 Avg PO lead-time (po_date → delivery), days, by delivery month
| Platform | Jan | Feb | Mar | Apr | May | Jun |
|---|--:|--:|--:|--:|--:|--:|
| Swiggy | 8.9 | 8.7 | 8.6 | 9.7 | 10.2 | **10.9** |
| Blinkit | 4.2 | 4.3 | 4.0 | 4.1 | 4.5 | 6.0 |
| Zepto | 6.8 | 8.0 | 7.7 | 8.2 | 8.9 | 9.2 |
| Big Basket | 6.7 | 5.4 | 7.5 | 8.4 | 6.8 | 8.0 |
| FK Grocery | 8.1 | 11.1 | 8.8 | 9.2 | 7.4 | 12.2 |
| City Mall | 5.9 | 8.0 | 7.7 | 4.0 | 9.2 | 18.0 |
| Zomato | 5.2 | 4.9 | 3.8 | 6.6 | 6.0 | 7.3 |

**Lead-times are lengthening across H1** for the big platforms — Swiggy 8.9 → 10.9 d, Zepto 6.8 → 9.2 d,
Blinkit 4.2 → 6.0 d. Longer lead-times + a fixed PO expiry window = more litres expiring before delivery =
the rising miss-rate in §2. Blinkit is structurally fastest (it also has the **tightest PO window, 6.6 d
order→expiry** — vs Zepto's generous 23.1 d, Big Basket 15.2 d, Swiggy 13.0 d), so its lead-time creep is
the most dangerous.

### 6.2 DRR pacing — June targets vs run-rate (the daily scoreboard)
`require_drr` = litres/day needed for the rest of June to still hit target; `drr` = actual run-rate. When
`require_drr >> drr`, the month is mathematically gone:

| Platform | Head | target | done | drr (L/d) | require_drr (L/d) | gap |
|---|---|--:|--:|--:|--:|--:|
| Swiggy | COMMODITY | 200,000 | 62,446 | 2,602 | **22,926** | **9×** |
| FK Grocery | COMMODITY | 200,000 | 18,178 | 790 | **25,975** | **33×** |
| Blinkit | COMMODITY | 70,000 | 13,704 | 571 | 9,383 | 16× |
| CityMall | COMMODITY | 150,000 | 17,603 | 1,956 | 6,305 | 3× |
| Amazon | COMMODITY | 180,000 | 101,987 | 3,923 | 19,503 | 5× |
| Zepto | PREMIUM | 100,000 | 68,451 | 2,633 | 7,887 | 3× |
| Swiggy | PREMIUM | 110,000 | 53,952 | 2,248 | 9,341 | 4× |

(DRR snapshots are per-platform as-of dates 06-09…06-26; done is slightly behind the 06-28 target-history.)

---

## 7. Method notes & caveats

- **Amazon is off-model.** It is absent from `master_po`/`total_po`/`total_po_zbs` (parallel `Amazon PO`
  feed). All §2.1/§3/§5/§6.1 master_po tables therefore exclude Amazon; §1, §2.2, §4 and the DRR table
  include it via target-history / fulfilment-health. Amazon is ~34% of sell-in and the worst filler (42%) —
  always note whether a figure includes it.
- **"Missed" ≠ `delivered_qty = 0`.** Missed = expired POs (fully) + short-supply shortfall. Cancelled
  (508,763 L H1) and still-pending (189,792 L now) are excluded from miss — they are not fulfilment failures.
  Raw zero-delivered rows are dominated by the expired/cancelled tail, not genuine current misses.
- **Three coexisting fill-rate definitions** — never compare across them without stating the window:
  fulfilment-health (filled/ordered, 30-day lagged window, §2.2), PO-cohort (delivered/net-ordered, §2.1),
  and primary `fill_rate_total` (done/dp, a different trailing window). They are not interchangeable.
- **June is live.** Every June figure is a partial/projected snapshot; its low PO-cohort fill is a timing
  artifact (pending not yet converted), not a true collapse.
- **Targets begin May 2026** (April had a formal target only for Flipkart-MP). Jan–Apr have actuals only, so
  achievement % is a May/June metric. The June commodity target (899k) is the most inflated cell — see §4.
- **JM Primary & Wellness Billing (rungs 1–2) are owner KPI cards, not in the SSOT;** `prim_master_po` /
  `test_master_po` are empty; the JIVO-Mart vendor delivers ≈0 L in the live period. Only rung 3 (Primary)
  is reproducible from the extracted data.
