# Primary domain — the supply / sell‑in chain (W2)

**Owner:** W2. **Pages covered:** **Primary**, **JM Primary**, and the **Wellness Billing** Home card —
i.e. the whole *sell‑in* (supply) side of JIVO: how oil moves from the factory down to the platforms,
and how much of every platform PO Jivo actually fulfils.

> All quantities on these pages are in **LITRES** (the universal unit), with a parallel ₹ (value) view.
> Non‑oils ("OTHER" item_head — juices, seeds, spices) carry **units only, 0 litres**.

---

## 0. The value / margin ladder (the spine of this domain)

JIVO is a *manufacturer‑distributor stack*. Oil is made once and re‑sold down a chain; at each hop a
margin is added, so the **same litre gets more expensive as it descends**. The four Home KPI cards
(Jun 2026, from the owner's screenshots) are the four rungs:

| Rung | Card | Litres (Jun 2026) | ₹/L | What it is | Stage owner |
|---|---|---|---|---|---|
| 1 | **Wellness Billing** | 811,616 L | ₹180.0 | Jivo **Wellness** (the parent factory) *makes* the oil and **bills/invoices Jivo** for it (transfer / ex‑factory price). | Jivo Wellness (parent) |
| 2 | **JM Primary** | 672,739 L | ₹192.6 | **Jivo Mart ("JM")** — Jivo's own distribution entity & warehouse — takes that stock as its **primary** and dispatches it onward (+~7% margin). | Jivo Mart |
| 3 | **Primary** | 484,975 L | ₹210.3 | Jivo ships to the **platforms / distributors** against their POs. This is "sell‑in" (+~9% margin). | Jivo → platform |
| 4 | **Secondary** | 560,048 L | ₹218.2 | Platforms **sell to consumers** (+~4%). *(Secondary is W3's domain — shown only to close the chain.)* |

**Read the rungs as a flow, not four silos:**
`Wellness Billing (811k @ ₹180)` → `JM Primary (672k @ ₹192.6)` → `Primary (485k @ ₹210.3)` → `Secondary (560k @ ₹218.2)`.

Two structural facts fall straight out of the numbers:
- **Volume *shrinks* going down (811k → 672k → 485k):** each stage holds back stock as inventory, so the
  top of the funnel is always bigger than what reaches the platforms. The gap between rungs **is the
  inventory being built** at Wellness (811−672 = 139k L) and at JM (672−485 = 188k L).
- **…but Secondary (560k) > Primary (485k):** consumers pulled **more** than Jivo shipped in this month →
  platforms were **destocking** (drawing down their own on‑hand). A persistent Secondary>Primary gap is the
  early‑warning for **platform stock‑outs next month** — this is the single most important cross‑page signal
  (see §8, Primary↔Secondary gap).
- **Price *rises* going down (₹180 → ₹192.6 → ₹210.3 → ₹218.2):** the spread between any two rungs is the
  margin captured at that hop. Total factory‑to‑consumer markup ≈ **+21%** (₹180 → ₹218.2).

The ladder is reproducible inside the data: in `master_po`, the per‑litre columns step up the same way —
**without‑margin ₹202/L → exclusive (with distributor margin, pre‑GST) ₹213/L → inclusive (with GST) ₹225/L**
(June ordered, 8 platforms; `total_order_amt_without_margin / exclusive / inclusive ÷ total_order_liters`).

---

## 1. PRIMARY (per‑platform page) — the core of this domain

### Purpose
Primary answers: **"For each platform, how much did we get ordered, how much did we deliver, what's still
pending, and are we on pace to hit the month's litre target?"** It is the operational dashboard for the
sell‑in team — the daily scoreboard of platform POs vs Jivo's fulfilment.

### Data behind it
- **Source: `master_po`** (the SSOT for primary). The app says so literally:
  `primary__<platform>.source = "master_po"`, `dashboard_title = "<PLATFORM> Primary Dashboard"`,
  `mode = "DEL MONTH"` (aggregated by **delivery month**).
- **Exception — Amazon:** `primary__amazon.source = reporting."Amazon PO"` (a *separate* reporting view, NOT
  `master_po`). Amazon is the "vendor‑central" archetype and runs its own PO pipeline → it is **absent from
  `master_po`** and from `total_po` / `total_po_zbs`. Treat Amazon primary as a parallel feed (see Anomalies).
- Endpoint: `platform <slug> primary` (live for all 10 slugs).

### Key metrics / KPIs (the master_po vocabulary — memorise this, it recurs on every primary page)
For each `item_head` (PREMIUM / COMMODITY / OTHER) and at SKU grain, every row carries this status ladder:

| Field | Meaning |
|---|---|
| `order_ltrs` / `order_qty` / `order_value` | **Total ordered** by the platform (all statuses). |
| `done_ltrs` (a.k.a. `filled_ltrs`) | **Delivered / fulfilled** litres. |
| `missed_ltrs` | Ordered but **not delivered** on a closed/expired PO (a *fulfilment failure*). |
| `pending_ltrs` | Still **open** — not yet delivered, not yet failed. |
| `dp_ltrs` | **D**one **+ P**ending (`done + pending`; the still‑live order book). |
| `expired_ltrs` / `cancelled_ltrs` | POs that lapsed past expiry / were cancelled. |
| `projection_ltrs` | **Run‑rate extrapolation** to month‑end (elapsed‑day pace × days‑in‑month). |
| `lead_time_days` | Avg PO‑date → delivery‑date gap (Swiggy ≈ **10.5 days**). |

**Real example — Swiggy Primary, June 2026** (`summary_total`, delivery‑month view):
ordered **175,227 L**, delivered (done) **125,838 L**, pending **49,389 L**, dp **175,227 L**,
projected month‑end **151,006 L**; value done ₹24.7 Cr of ₹33.8 Cr ordered.
Split: PREMIUM done 59,157 L / COMMODITY done 66,681 L / OTHER 0 L (1,073 units of non‑oil).

### Drill‑down / structure (grain)
`Platform → item_head (PREMIUM/COMMODITY/OTHER) → Category → Sub‑category → per‑litre pack (1 L / 5 L)`.
The page exposes several lenses off the same master_po slice:
- **`summary` / `summary_total`** — the headline tiles by item_head (delivery‑month).
- **`fill_rate_summary` / `fill_rate_total`** — same metrics over a **trailing fill‑rate window**
  (`fill_rate_date_from`→`fill_rate_date_to`, e.g. 2026‑05‑01 → 06‑18) used to score fulfilment fairly
  (POs only count once they've had time to be delivered). Swiggy fill‑rate window: done 294,817 L / dp 388,360 L ≈ **76%**.
- **`details`** — SKU‑pack grain rows (`category / sub_category / per_ltr` + `value_per_ltr`), e.g.
  `BLENDED → GOLD → 1 LTR @ ₹152.6/L`.
- **`top_items`** — biggest items: Swiggy's #1 is `GROUNDNUT 1L` (done 31,854 L, missed 10,562 L),
  then `MUSTARD 1L`, `SUNFLOWER 1L`.
- **`open_vendor_pending_*`** — open order book **by fulfilling vendor/distributor** (order vs delivered
  vs pending ltrs + `lead_time_avg`). This is the bridge to the **Distributor** page (see §8).
- **`trends.day`** — daily delivered/ordered curve for the month (sparkline).

---

## 2. JM PRIMARY — Jivo Mart's own primary dispatch

### Purpose
"JM Primary" is **rung 2** of the ladder: the volume Jivo **Mart** (JM — Jivo's in‑house distribution
company/warehouse) takes from Wellness and dispatches as *its* primary, **before** third‑party distributors
mark it up to the platforms. Card value: **672,739 L @ ₹192.6/L** (Jun 2026). It sits *above* Primary in
both volume (672k > 485k) and is *cheaper* per litre (₹192.6 < ₹210.3) — JM has not yet added the
distributor margin.

### Where it lives in the data (important — there is **no** separate `jm_primary` table/leaf, and the obvious proxy FAILS)
JM Primary is **not** a distinct API leaf or table in the extracted SSOT. My first hypothesis was that it
surfaces as the vendor `JIVO MART PRIVATE LIMITED` inside `master_po` — **I tested that against the data and
it does *not* reconcile**, so I'm downgrading it:

- `JIVO MART PRIVATE LIMITED` *is* one of the 11 fulfilling vendors (520,498 L delivered all‑time), **but its
  deliveries are historical and now dormant:** ~80–99k L/mo in Oct 2025–Jan 2026, then **11k L in Mar 2026 and
  ZERO delivered litres in Apr / May / Jun 2026.** The current fulfillers are KNOWTABLE (277k), SUSTAINQUEST
  (270k), ANTIZE (229k), CHIRAG (193k), EVARA (173k) — **JM is absent.** So the "JM‑as‑master_po‑vendor" slice
  **cannot** be the 672,739 L/mo JM‑Primary card. *(Beyond‑context correction — see UNDERSTANDING COVERAGE.)*

**What JM Primary actually is:** the **upstream rung‑1→rung‑2 stock‑transfer** — Wellness bills JM, JM holds it
as primary and dispatches onward (₹192.6/L). That stage sits *above* the platform‑PO layer that `master_po`
captures, so the SSOT we hold **does not contain it** as a measurable object. The 672,739 L figure is a Home
KPI card (owner screenshot), not recomputable from these tables.

> Corrected reading: **Primary = "what platforms ordered & we shipped" (master_po, all vendors, ₹210.3 rung).
> JM Primary = the Jivo‑Mart entity's upstream primary stage (₹192.6 rung) that is NOT in the extracted data.**
> They are adjacent rungs of one ladder; only Primary is reproducible from the SSOT.

### Caveat
The dedicated `prim_master_po` table — the natural home for a clean "JM primary master" — is **empty
(0 rows)**; likewise `test_master_po` (0 rows). JM‑Primary is therefore **UNCLEAR in the data**: known as a
business concept + Home card, but with no populated object and a failed vendor‑proxy. Flag to the lead.

---

## 3. WELLNESS BILLING card — rung 1 (the factory invoice)

### Purpose
The **top** of the chain: **Jivo Wellness** (the parent company; it owns the manufacturing + its own
warehouse) **makes** the oil and **bills Jivo** for it. Card: **811,616 L @ ₹180/L** (Jun 2026) — the
cheapest rung (ex‑factory / transfer price, no distribution margin yet). Everything downstream is this oil
re‑sold. It is the **supply ceiling**: Jivo can never sell more (JM Primary + Primary) than Wellness bills,
net of inventory.

### Data behind it
A Home KPI card (sourced from the owner's screenshots per CONTEXT). **Verified independently:** the four Home
card litre values (`811616 / 672739 / 484975 / 560048`) appear in **none** of the extracted dashboard JSONs —
so the cards are **owner‑screenshot‑only**, not reproducible from the pulled SSOT. `master_po` begins at the
JM/distributor→platform layer, not at the Wellness→Jivo invoice, so Wellness Billing has no table behind it
here. Treat 811,616 L / ₹180 as authoritative‑from‑owner; the SSOT does not recompute it. Premium/commodity
split applies (same item_head axis as every card).

---

## 4. The PO tables — what actually feeds master_po

`master_po` is **not raw**; it is the enriched **union of two raw PO feeds**, split by platform archetype.
The row counts prove the union exactly: **8,239 + 35,842 = 44,081**.

| Table | Rows | Formats it carries | PO‑number style | Role |
|---|---|---|---|---|
| **`total_po`** | 8,239 | BIG BASKET, FLIPKART GROCERY, CITY MALL, ZOMATO, DEAL SHARE | `IRA…` | Raw POs for the **non‑quick‑commerce** (marketplace‑grocery) formats. |
| **`total_po_zbs`** | 35,842 | **SWIGGY, BLINKIT, ZEPTO** | `P…` | Raw POs for the **ZBS** feed = the 3 **quick‑commerce** platforms (`taxonomy.zbs = [blinkit, swiggy, zepto]`). |
| **`master_po`** | 44,081 | **all 8 above (union)** | both | **Enriched SSOT:** adds category/sub_category/item_head, litres, margins, fill/miss, lead_time, city/state, projection. |
| **`prim_master_po`** | **0 (empty)** | — | — | Placeholder (intended "primary master"; unused). |
| **`test_master_po`** | **0 (empty)** | — | — | Test scratch table. |

**Raw columns** (`total_po` / `total_po_zbs`, 16 cols): `po_number, po_date, po_expiry_date, grn_date,
vendor_name, status, sku_code, sku_name, order_qty, delivered_qty, basic_rate, landing_rate, location,
format, remark`.

**`master_po` adds ~40 derived columns** (55 total), the ones that make every dashboard above possible:
`category, sub_category, item, sap_sku_name, item_head, category_head, brand, case_pack, per_liter,
total_order_liters, total_delivered_liters, total_order_amt_inclusive/exclusive/without_margin,
distributor_margin, realise, distributor_commission_per_unit, lead_time, days_to_expiry, po_window,
po_status, item_status, missed_qty/ltrs, filled_qty/ltrs, city, state, po_month, delivery_month, po_year…`.

**Status reality (44,081 rows):** `item_status` = FULL SUPPLIED 26,103 · SHORT SUPPLIED 7,347 · EXPIRED 6,294 ·
CANCELLED 3,061 · PENDING 1,259. `item_head` rows = PREMIUM 26,405 · COMMODITY 13,320 · OTHER 4,355.
So **PREMIUM dominates the order book by line‑count (~60%)** — but by *delivered litres* premium‑mix is only
**~46% all‑time** (rising to ~53% in June), because commodity SKUs ship in bigger pack sizes. **Brand split
(verified):** `JIVO` 43,347 rows, `SANO` **528** (a tiny premium pomace/olive sub‑brand), null 206 — matches
`taxonomy.brands = [JIVO, SANO]`.

**The rate columns — how the ₹ ladder is encoded per row (verified, beyond context):**
| Column | Grain | Example (Sunflower) | Meaning |
|---|---|---|---|
| `basic_rate` | **per physical unit** (scales with pack) | 1 L → ₹161.38, 5 L → ₹806.86 (=5×) | Pre‑tax base price of the unit. |
| `landing_rate` | per unit | ₹169.44 / ₹847.20 | **basic × ~1.05** — the **landed price the platform pays** (+~5% GST/freight). |
| `realise` | **per LITRE** (pack‑normalised) | ₹152/L | What Jivo **nets per litre** after distributor commission. |
| `distributor_margin` | ratio | **0.055** (≈5.4% blended) | Commission to the fulfilling distributor. |
| `per_liter` | litres/unit | 1.0 or 5.0 | `total_order_liters = order_qty × per_liter`. |

So a single master_po row contains three of the four ladder rungs at once: net realisation (`realise`) <
base (`basic_rate`/per_liter) < landed (`landing_rate`/per_liter).

---

## 5. FULFILMENT‑HEALTH — the cross‑platform fill/miss scoreboard

### Purpose & metrics
One global view: **are we fulfilling platform POs, and where are we bleeding?** Over a **30‑day window with a
7‑day lag** (`start 2026‑05‑21 → end 2026‑06‑20`, so only POs old enough to have been deliverable count).

- `ordered_ltrs`, `filled_ltrs`, `missed_ltrs`, `po_count`
- **`fill_rate` = filled / ordered**; **`miss_rate` = missed / ordered** (the rest is still open → fill+miss < 100%).

**Real totals (Jun 2026 window):** ordered **964,560 L**, filled **542,343 L (56.2%)**, missed
**151,757 L (15.7%)**, 1,031 POs. **By platform fill‑rate, worst→best:**
Amazon **42.1%** (largest orderer, 429k L) · Swiggy **51.5%** (worst miss‑rate **27.5%**, 504 POs) ·
Zepto 71.6% · Flipkart‑Grocery 80.9% · Blinkit 81.5% · Big Basket 82.2% · City Mall 84.2% · Zomato **84.4%**.

> Reading: the **big quick‑commerce orderers (Amazon, Swiggy) have the *worst* fill rates** — they order huge
> and we miss a quarter of it. The small marketplace‑grocery platforms are nearly fully served. This is the
> headline supply‑chain problem the Primary domain exists to surface.

**Independent raw cross‑check (beyond context):** at the raw‑PO line level, **Swiggy has `delivered_qty = 0`
on 8,709 of 21,274 lines (41%)**, Zepto 30%, Blinkit 17% — Swiggy's raw miss matches its worst windowed
miss‑rate. **But beware:** BigBasket shows 2,235/3,483 (**64%**) zero‑delivered yet a *fill‑rate of 82%* — the
raw zeros are dominated by the **EXPIRED + CANCELLED tail (6,294 + 3,061 lines)**, not genuine current misses.
**Do not equate `delivered_qty = 0` with "missed"** — the lagged fill‑rate window exists precisely to strip
that noise.

### Connection
Same `master_po` numerator as Primary, just windowed + aggregated across platforms. Its `miss_rate` is the
flip side of Primary's `missed_ltrs`, and it feeds the **Distributor** page's vendor accountability.

---

## 6. PENDENCY — the open order book (what's owed *right now*)

### Purpose
The **"who do we still owe?"** page: all **open** POs (delivered‑short, not yet expired) for a platform,
sliced four ways. Pure `master_po` open rows.

### Structure (slices) & real numbers — Swiggy, June 2026
Totals: **pending 91,033 L across 162 open POs (837 lines)**. Sliced by:
- **`by_city`** (delivery destination): Hyderabad 23,448 L · Bengaluru 10,906 L · Pune 7,800 L …
- **`by_distributor`** (who must deliver): KNOWTABLE 48,672 L (95 POs) · Chirag 20,670 L · Sustainquest 15,808 L.
- **`by_sku`**: `GROUNDNUT 1L` 28,496 L (80 POs) · `MUSTARD 1L` 15,300 L.
- **`by_warehouse`**: Hyderabad 23,448 L · Bangalore 10,906 L.

### Connection
Pendency = Primary's `pending_ltrs` exploded to actionable grain. Its `by_distributor` ties to Primary's
`open_vendor_pending_*` and to the **Distributor** page; its `by_city/warehouse` ties to **JM/Inventory**
(is the warehouse out of stock?). High pendency on a SKU + low DOH on Inventory = imminent stock‑out.
*(Pendency is served for the marketplace‑grocery + qcomm platforms; `citymall`/`zomato` flagged empty‑prone.)*

---

## 7. POS · PRIMARY‑PO‑LITRES · TARGETS · DRR (the supporting leaves)

### POS — raw PO line viewer
`platform <slug> pos` returns the **full `master_po` rows** (all ~55 columns) for that platform — the
export/audit grain behind everything else. **Only populated where the raw listing is wired:**
`citymall (1,433)`, `flipkart_grocery (1,834)`, `zomato (1,423)` — counts that **match `total_po` exactly**.
The qcomm platforms, Amazon, Flipkart, Jiomart and **Big Basket return `count: 0`** here (data lives in the
aggregated primary view instead, or is gated). Think of POS as "show me the actual POs," Primary as "summarise them."

### Primary‑PO‑Litres — the Primary card's per‑platform breakdown
`primary-po-litres` = **delivered litres per format for the month** (the rung‑3 card, exploded). June 2026:
Amazon 128,447 · Swiggy 125,838 · Zepto 88,599 · Blinkit 30,198 · Zomato 26,495 · Big Basket 21,246 ·
Flipkart‑Grocery 20,166 · City Mall 17,715 → **Σ ≈ 458,704 L** (partial month to 06‑25; the 484,975 L Home
card is the full/projected figure). Cross‑checks cleanly: master_po non‑Amazon June delivered = **330,257 L**,
**+ Amazon 128,447 = 458,704 L**. ✔

### Targets — two DISTINCT target tracks (different sources — do not conflate)
1. **`primary-month-targets`** (`type = "prim"`) — the **Primary litre target & pacing** sheet, by
   format × item_head × month. Carries `targets, done_ltrs, achieved_pct, est_ltr(_pct), drr, require_drr,
   pending_ltr, dp_ltrs`. **Swiggy June:** COMMODITY target 200,000 L → done 62,446 L (**31.2%**), needs
   `require_drr` 22,926 L/day vs current `drr` 2,602 → badly behind; PREMIUM target 110,000 L → done 53,952 L
   (49%). (May closed *above* target: COMMODITY 103,478/100,000 = 103%.)
2. **`month-targets`** (`type = "B2B"`) — **CORRECTION (verified, against shared model): its `source =
   "secmaster"`, i.e. it is measured against SECONDARY (sell‑out) sales, NOT `master_po`.** So despite living
   among the "primary" leaves, this is the **Secondary monthly target** track (value + growth‑vs‑last‑month):
   `targets, done_ltrs, done_value, achieved_pct, est_ltr, est_value, last_month, growth(_pct)`. **Swiggy June:**
   PREMIUM target 60,000 L → done 78,642 L (**131%**, +61.7% MoM, done_value/L ≈ **₹219** = the *secondary*
   ₹218.2 rung, confirming it's sell‑out); COMMODITY 80,000 L → done 68,026 L (85%, ₹151/L). The proof it is a
   *different* track from `primary-month-targets`: same platform/month/head but **different `done_ltrs`**
   (prim COMMODITY 62,446 L from master_po vs B2B 68,026 L from secmaster). This is really W3's (Secondary)
   number, surfaced here; W4's **Target sheet** is the editable master of both tracks.

> `require_drr` (litres/day still needed to hit target) is the hinge that connects **targets → DRR/velocity →
> Primary pacing**: if today's run‑rate `drr` < `require_drr`, the month will miss.

### DRR — daily run‑rate / velocity (the bridge into Secondary & Inventory)
`drr__<platform>` measures **sell‑through speed**, not sell‑in. Its `source = {sales: SecMaster,
inventory: all_platform_inventory}` — so DRR is really a **Secondary/Inventory** metric that lives here
because it **paces the Primary targets**. Per item/SKU it gives `drr_qty/ltr/value` (avg daily sales),
`cur_day_soh` (stock on hand) and **`doh` = SOH ÷ DRR** (days of cover). **Swiggy June:** total DRR
**5,867 L/day** (122,457 L sold over 25 elapsed days), SOH 104,098 L → cover varies by SKU
(e.g. CANOLA 1L DOH ≈ 15.7 days). Low DOH + high Pendency = restock now.

---

## 8. CONNECTIONS (the most important part)

- **Wellness Billing → JM Primary → Primary → Secondary (ONE flow, four rungs).** Same oil, re‑sold down a
  chain; litres shrink (811k→672k→485k, the difference = inventory built at each stage) while ₹/L rises
  (₹180→₹192.6→₹210.3→₹218.2, each gap = a margin). This domain owns rungs 1–3; W3 owns rung 4.
- **Primary ↔ JM Primary** are the *same litres at adjacent rungs.* JM Primary is realised in `master_po`
  as `vendor_new = JIVO MART PRIVATE LIMITED` (JM fulfilling its own slice) and as the upstream ₹192.6 stage;
  Primary is the full platform‑facing ₹210.3 stage across **all 11 vendors**.
- **Primary → Distributor (vendor fill‑rate).** Every platform PO is handed to a fulfilling vendor; the 11
  vendors (KNOWTABLE 696k L, SUSTAINQUEST 673k, EVARA 549k, **JIVO MART 520k**, CHIRAG 482k, ANTIZE 422k…
  delivered all‑time) are scored on **delivered vs ordered** = vendor fill‑rate. `open_vendor_pending_*`
  (Primary) + `by_distributor` (Pendency) + `fulfilment-health` are the same accountability viewed three ways;
  they feed the **Distributor** page.
- **Primary → Target sheet (targets vs actual).** Only **`primary-month-targets` (`prim`, source master_po)**
  is a true *Primary* target — `done_ltrs` vs `targets`, with `require_drr` vs `drr` saying whether the
  run‑rate closes the gap. **`month-targets` (`B2B`) is sourced from `secmaster` → it is a *Secondary* target**
  that merely lives among the primary leaves (cross‑domain bridge to W3). W4's **Target sheet** owns both.
- **Primary vs Secondary gap (the key signal).** Jun 2026 **Secondary 560k > Primary 485k** ⇒ platforms sold
  more than we shipped ⇒ **destocking** ⇒ stock‑out risk. **DRR/DOH** (sell‑through speed + days of cover) is
  the instrument that quantifies it; it stitches Primary (sell‑in) to Secondary (sell‑out) and Inventory (SOH).
- **Primary → Inventory / JM Inventory.** Pendency `by_warehouse/by_city` + DRR `cur_day_soh`/`doh` ask "is
  the warehouse able to fulfil?" — the missed_ltrs on Primary are often an *inventory* failure, not a demand one.
- **`master_po` is the join hub.** `taxonomy.join_model`: `format_sku_code → sku_sap_code (FG hub) → item`,
  with item_head/brand/category sourced from master_po + notifications. Primary, Pendency, POS, both Target
  tracks and Fulfilment‑Health all read this one enriched table (Amazon excepted).

---

## 9. ANOMALIES / CAVEATS

- **Amazon is off‑model.** `primary__amazon.source = reporting."Amazon PO"`, **not** `master_po`; Amazon is
  absent from `total_po`/`total_po_zbs`/`master_po`. Its fill rate is the **worst (42.1%)** and its pending is
  huge (242,699 L pending vs 128,447 done) — but it can't be reconciled against the same table as the others.
- **`prim_master_po` and `test_master_po` are EMPTY (0 rows).** The natural "JM primary master" object is
  unbuilt; JM Primary is therefore inferred (vendor lens + Home card), not directly served.
- **POS is sparse.** Only citymall / flipkart_grocery / zomato return rows; Big Basket, all qcomm, Amazon,
  Flipkart, Jiomart return `count: 0` (gated or routed through the aggregate view). Don't read "0 POs" as "no orders."
- **Fill‑rate ≠ one number.** Three coexisting definitions: Fulfilment‑Health `fill_rate = filled/ordered`
  (Swiggy 51.5%, 30‑day lagged window) vs Primary `fill_rate_total done/dp` (Swiggy ~76%, different trailing
  window) vs delivery‑month `done/order`. Always state the window; they are **not** comparable.
- **Wellness Billing (811,616 L) & the Home card ₹/L are owner‑screenshot values**, not recomputed by the
  SSOT (master_po starts below Wellness). Use as authoritative‑from‑owner; flag the non‑reconciliation.
- **`DEAL SHARE` (66 rows)** is a minor extra format in `total_po` beyond the 8 named platforms — small but real.
- **Built fast / live:** large EXPIRED+CANCELLED tail (6,294 + 3,061 lines) inflates "ordered"; the lagged
  fill‑rate window exists precisely to stop counting POs that never had a chance to deliver.
- **OTHER item_head = 0 litres** by design (non‑oils tracked in units) — it will always look "empty" on any
  litre chart; that's not a bug.

---

## 10. UNDERSTANDING COVERAGE (self‑audit: what I verified vs. what's still open)

Marks reflect *independent verification against the data*, not just restating CONTEXT. Evidence cited inline.

### Tables
| Object | Status | Evidence / why |
|---|---|---|
| `master_po` (44,081) | **FULLY** | Confirmed = `total_po` ∪ `total_po_zbs` (8,239+35,842=44,081 exact); 55 cols decoded; status/item_head/brand/rate columns all sampled & reconciled. |
| `total_po` (8,239) | **FULLY** | Format dist verified: BIGBASKET 3,483 / FK‑GROC 1,834 / CITYMALL 1,433 / ZOMATO 1,423 / DEALSHARE 66; `IRA…` PO ids. |
| `total_po_zbs` (35,842) | **FULLY** | Verified = qcomm only (SWIGGY 21,274 / BLINKIT 10,451 / ZEPTO 4,117) = `taxonomy.zbs`; `P…` PO ids. "ZBS" expansion itself inferred (qcomm feed) not documented anywhere — *naming UNCLEAR, membership FULLY clear*. |
| `prim_master_po` | **FULLY (as empty)** | 0 rows, columns `[]`. Confirmed unused placeholder. |
| `test_master_po` | **FULLY (as empty)** | 0 rows. Test scratch. |
| rate columns (`basic/landing/realise/per_liter/distributor_margin`) | **FULLY** | Pack‑scaling + landing=basic×1.05 + per‑litre `realise` verified on sampled rows. |

### Pages / dashboards
| Page | Status | Evidence / gap |
|---|---|---|
| **Primary** (`primary__<p>`) | **FULLY** | Source=master_po confirmed; full metric vocab (done/missed/pending/dp/projection), summary vs fill_rate windows, details/top_items/trends/open_vendor all decoded with Swiggy numbers. |
| **Wellness Billing** card | **PARTIAL** | Meaning clear (rung‑1 factory invoice, 811,616 L @ ₹180); **but not in any pulled object** (verified absent) → can't recompute or drill. |
| **JM Primary** | **UNCLEAR** | Rung‑2 concept clear (672,739 L @ ₹192.6); **no leaf/table**, `prim_master_po` empty, and the JIVO‑MART‑vendor proxy **fails** (0 L delivered Apr–Jun 2026). Needs owner confirmation of its true source. |
| **fulfilment‑health** | **FULLY** | Window (30d/7d‑lag), fill=filled/ordered, miss=missed/ordered all verified; per‑platform numbers cross‑checked vs raw zero‑delivered rates. |
| **pendency** | **FULLY** | 4 slices (city/distributor/sku/warehouse) + totals decoded; Swiggy 91,033 L / 162 POs. |
| **pos** | **FULLY** | = raw master_po line viewer; populated only citymall/fk_grocery/zomato (counts match total_po); others `count:0`. |
| **primary‑po‑litres** | **FULLY** | Per‑format delivered ltrs; Σ≈458,704 reconciled to master_po‑non‑amazon (330,257)+amazon (128,447). |
| **primary‑month‑targets** (`prim`) | **FULLY** | Source master_po; litres + DRR pacing (`drr` vs `require_drr`) decoded. |
| **month‑targets** (`B2B`) | **FULLY (re‑classified)** | **source=secmaster ⇒ a SECONDARY target, not primary** — verified by source field + ₹219/L + differing done_ltrs. Cross‑domain (W3). |
| **drr** | **PARTIAL** | Mechanics clear (DRR=sales/elapsed, DOH=SOH/DRR; source secmaster+all_platform_inventory); it's primarily a Secondary/Inventory metric — full ownership is W3/W1. Included here only as the target‑pacing link. |

### Metrics
| Metric | Status | Note |
|---|---|---|
| Order/Done/Missed/Pending/DP/Projection LTRS | **FULLY** | `dp=done+pending` verified; projection=run‑rate extrapolation. |
| Fill Rate / Miss Rate | **FULLY (with caveat)** | **Three different definitions/windows coexist** — never compare across pages without stating the window. |
| Lead Time | **FULLY** | po_date→delivery_date; Swiggy avg ≈10.5d; per‑vendor `lead_time_avg`. |
| Premium‑mix | **FULLY** | ~46% of delivered litres all‑time, ~53% June; differs from ~60% by line‑count. |
| The value/margin ladder ₹/L | **PARTIAL** | Rungs 2–4 (₹192.6/210.3/218.2) and the master_po per‑L steps (202→213→225) verified; **rung‑1 (Wellness ₹180) is owner‑asserted, not in data.** |

### Things the DATA revealed BEYOND the shared context
1. **`month-targets` is Secondary‑sourced (`secmaster`)**, despite sitting in the primary leaf group — the
   shared model implied it was primary. *Re‑classified.*
2. **The JM‑Primary‑as‑master_po‑vendor proxy is false for the live period** (JIVO MART delivers 0 L
   Apr–Jun 2026). The rung is genuinely upstream of the SSOT.
3. **Amazon runs a parallel PO pipeline** (`reporting."Amazon PO"`) outside master_po — it's ~⅓ of all
   ordered litres (429k of 964k) yet can't be reconciled against the same table.
4. **Raw `delivered_qty=0` ≠ missed** — it's mostly the expired/cancelled tail (BigBasket 64% zero but 82%
   fill). The lagged window is the only honest miss metric.
5. **Two PO id namespaces** (`IRA…` marketplace vs `P…` qcomm/zbs) physically partition the feed.
