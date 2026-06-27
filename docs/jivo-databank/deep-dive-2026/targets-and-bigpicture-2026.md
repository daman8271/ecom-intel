# JIVO — Target Performance & the Big Picture, 2026 (Jan–Jun)

> **Scope.** Deep-dive into JIVO's monthly litre targets vs actuals for 2026, and the full value chain
> behind them. **Primary source:** `/root/jivo-intel/docs/app-model/target-history.csv` (2026-06-28 pull —
> the freshest extract, fresher than the json/HTML roll-ups below). Supporting:
> `target-sheets.md`, `targets-over-years.html`, `target-timeseries.json`, `home-overview.md` (value-chain
> KPI cards). All volumes in **litres (L)**; split **PREMIUM** (canola, groundnut, olive/pomace, sesame,
> yellow-mustard, ghee) vs **COMMODITY** (mustard kacchi-ghani, sunflower, soyabean, rice-bran, gold).
>
> **Two tracks:** **Secondary** = sell-OUT to consumers (`month-targets`, source `secmaster`);
> **Primary** = sell-IN to platforms / POs delivered (`primary-month-targets`, source `master_po`).
>
> **Three timing rules to read everything correctly:**
> 1. **Targets exist only from Apr-2026.** Jan–Mar ran with no formal target, so for those months we only
>    have actuals. Achievement is an Apr–Jun metric.
> 2. **April is a partial/frozen snapshot** (see Anomaly #1) — its actuals are truncated and its achievement
>    % is unreliable. Treat **May as the first fully-trustworthy month** and **June as live/in-progress**.
> 3. **June is the live month.** `done` is as-of the latest daily refresh (~06-27); `est%` is the
>    straight-line month-end projection (`done × days_in_month / days_elapsed`). For closed months
>    `est == done`.

---

## 1. Target achievement, Apr → Jun 2026

### 1.1 Aggregate — the honest "like-for-like" view

These numbers sum `done` and `target` **only over platform-cells that actually have a target set** (so the
ratio is apples-to-apples). This is the correct way to read attainment; the published
`targets-over-years.html` table does NOT do this and is broken — see Anomaly #2.

**SECONDARY (sell-out):**
| Month | PREMIUM tgt → done (ach% / est%) | COMMODITY tgt → done (ach% / est%) |
|-------|----------------------------------|------------------------------------|
| Apr (partial) | 168,668 → 150,434 (**89%** / 102%) · 7 plats | 252,900 → 95,054 (**38%** / 41%) · 6 plats |
| May (closed) | 499,000 → 385,371 (**77%**) · 10 plats | 464,000 → 416,030 (**90%**) · 9 plats |
| Jun (live) | 372,000 → 297,601 (**80%** / 94% est) · 8 plats | 419,000 → 256,907 (**61%** / 72% est) · 8 plats |

**PRIMARY (sell-in):**
| Month | PREMIUM tgt → done (ach% / est%) | COMMODITY tgt → done (ach% / est%) |
|-------|----------------------------------|------------------------------------|
| Apr | *only Flipkart-MP had a target* → 34,000 → 14,861 (44%) | *only Flipkart-MP* → 56,000 → 6,239 (11%) |
| May (closed) | 645,000 → 499,335 (**77%** / 80% est) · 10 plats | 504,000 → 440,254 (**87%** / 95% est) · 9 plats |
| Jun (live) | 566,000 → 308,248 (**55%** / 63% est) · 10 plats | 899,000 → 269,532 (**30%** / 39% est) · 9 plats |

> The official Home roll-up (`target-timeseries.json`, an earlier pull) reports slightly different headline
> numbers — Sec May PREM 79.5% / COMM 90.6%, Jun PREM 75.7% / COMM 59.1%; Pri May PREM 76.6% / COMM 84.0%,
> Jun PREM 48.8% / COMM 29.3%. The gap is purely a **scoping choice**: that roll-up excludes Amazon-MP from
> Secondary and excludes Amazon + Flipkart-MP from Primary (those marketplaces are treated as duplicate of
> their secondary). Direction and conclusions are identical. The CSV-derived figures above are the most
> complete and most recent.

**The 3-month story (aggregate):**
- **Premium sell-out holds in the high-70s/80%** all quarter (89→77→80%) — the premium book is the
  reliable engine.
- **Commodity sell-out is volatile** (38→90→61%): a weak partial April, a near-perfect May, then a June
  fade.
- **Primary (sell-in) decelerates hard into June.** May was strong (77% / 87%); June craters, especially
  **commodity sell-in at 30%** against a target that was inflated to 899k L (+78% MoM). This is the single
  biggest miss in the dataset.

### 1.2 Per-platform — who's hitting, who's missing

Format: `target → done  ach% / est%`. "(no tgt)" = no target set that month (actuals still shown).

**SECONDARY · PREMIUM**
| Platform | Apr | May | Jun (live) |
|----------|-----|-----|-----|
| **Swiggy** ⭐ | 45k → 37.2k (83%) | 67k → 58.4k (87%) | 60k → **82.6k (138% / 159%)** |
| Amazon | (no tgt; 82.7k) | 150k → 147.6k (**98%**) | 160k → 97.4k (61% / 73%) |
| Zepto | 8.8k → 43.7k (496%※) | 67k → 50.5k (75%) | 55k → 51.8k (94% / 109%) |
| Blinkit | 11k → 19.4k (176%※) | 66k → 53.1k (80%) | 60k → 41.2k (69% / 79%) |
| Zomato | 30k → 32.4k (108%) | 60k → 33.7k (56%) | (no tgt; 11.5k) |
| **Flipkart** ✗ | 34k → 14.9k (44%) | 60k → 31.5k (52%) | 25k → 16.1k (64% / 74%) |
| Flipkart Grocery | (no tgt; 0.9k) | 2k → 2.1k (107%) | 2k → 1.0k (50% / 62%) |
| BigBasket | 5k → 2.8k (56%) | 5k → 3.0k (59%) | 5k → 2.1k (43% / 49%) |
| CityMall | 34.9k → 0.2k (**1%**) | 2k → 0.8k (39%) | (no tgt; 0.1k) |
| Amazon MP | (no tgt; 3.6k) | 20k → 4.7k (24%) | 5k → 5.4k (108%) |

**SECONDARY · COMMODITY**
| Platform | Apr | May | Jun (live) |
|----------|-----|-----|-----|
| Amazon | (no tgt; 90.4k) | 180k → 180.9k (**100%**) | 180k → 106.8k (59% / 71%) |
| Swiggy | 65k → 47.7k (73%) | 80k → 81.0k (**101%**) | 80k → 73.4k (92% / 106%) |
| Blinkit | 55k → 9.5k (17%) | 35k → 33.5k (96%) | 35k → 31.5k (90% / 104%) |
| Zepto | 20k → 18.4k (92%) | 25k → 25.9k (104%) | 30k → 16.6k (55% / 64%) |
| BigBasket | 33k → 9.7k (29%) | 12k → 11.8k (99%) | 12k → 7.7k (64% / 74%) |
| Flipkart Grocery | (no tgt; 15.1k) | 52k → 23.0k (44%) | 40k → 15.1k (38% / 47%) |
| **Flipkart** ✗ | 56k → 6.2k (11%) | 25k → 11.4k (46%) | 35k → 5.5k (**16% / 18%**) |
| CityMall | 23.9k → 3.5k (15%) | 50k → 48.3k (97%) | (no tgt; 17.6k) |
| Amazon MP | (no tgt; 0.4k) | 5k → 0.3k (5%) | 7k → 0.2k (**2%**) |

**PRIMARY · PREMIUM** (sell-in)
| Platform | Apr | May | Jun (live) |
|----------|-----|-----|-----|
| Blinkit | (no tgt; 36.6k) | 100k → 118.8k (**119%**) | 120k → 16.5k (**14% / 17%**) |
| Swiggy | (no tgt; 36.9k) | 100k → 109.0k (**109%**) | 110k → 61.9k (56% / 65%) |
| Amazon | (no tgt; 82.7k) | 150k → 147.6k (98%) | 160k → 97.4k (61% / 70%) |
| Zepto | (no tgt; 33.8k) | 100k → 50.7k (51%) | 100k → 73.2k (73% / 84%) |
| Zomato | (no tgt; 32.4k) | 60k → 33.7k (56%) | 40k → 33.3k (83% / 93%) |
| Flipkart MP | 34k → 14.9k (44%) | 60k → 31.5k (52%) | 25k → 16.1k (64% / 74%) |
| BigBasket | (no tgt; 3.1k) | 5k → 1.5k (29%) | 2k → 2.4k (122%) |
| Flipkart Grocery | (no tgt; 2.5k) | 30k → 1.0k (**3%**) | 2k → 2.0k (99%) |
| CityMall | (no tgt; 0.2k) | 20k → 0.8k (4%) | 2k → 0.1k (6%) |
| Amazon MP | (no tgt; 3.6k) | 20k → 4.7k (24%) | 5k → 5.4k (108%) |

**PRIMARY · COMMODITY** (sell-in)
| Platform | Apr | May | Jun (live) |
|----------|-----|-----|-----|
| Blinkit | (no tgt; 11.3k) | 50k → 62.7k (**125%**) | 70k → 13.7k (**20% / 24%**) |
| Swiggy | (no tgt; 62.9k) | 100k → 103.5k (**103%**) | 200k → 68.2k (**34% / 39%**) |
| Amazon | (no tgt; 90.4k) | 180k → 180.9k (100%) | 180k → 106.8k (59% / 68%) |
| Zepto | (no tgt; 23.6k) | 30k → 23.0k (77%) | 50k → 20.6k (41% / 47%) |
| CityMall | (no tgt; 3.5k) | 50k → 48.3k (97%) | 150k → 17.6k (**12% / 39%**) |
| BigBasket | (no tgt; 11.0k) | 12k → 7.0k (58%) | 7k → 18.8k (269%※) |
| Flipkart MP | 56k → 6.2k (11%) | 25k → 11.4k (46%) | 35k → 5.5k (16% / 18%) |
| Flipkart Grocery | (no tgt; 16.1k) | 52k → 3.3k (**6%**) | 200k → 18.2k (**9% / 12%**) |
| Amazon MP | (no tgt; 0.4k) | 5k → 0.3k (5%) | 7k → 0.2k (2%) |

(※ = target mis-set, not a real beat — see Anomaly #4. *Flipkart has NO Primary targets at all*; its
"Primary" cells above are the Flipkart-MP marketplace entity.)

**Per-platform verdict:**
- **Hitting:** **Swiggy** (the standout — beats Secondary Premium every harder, 138% in June; top Primary
  performer in May). **Amazon** (near-perfect May on both heads, large absolute volumes; softening but live
  in June). **Zepto** & **Blinkit** Secondary respectable. **Zomato** Primary Premium recovering (83% June).
- **Missing:** **Flipkart** — chronic on every cut (Secondary Commodity 11→46→16%; no Primary targets);
  the structural laggard. **Flipkart-Grocery Commodity** sell-in (6%, 9% — against a wildly oversized 200k
  June target). **CityMall** (1% April premium, 12% June commodity sell-in vs a 150k target). **Amazon-MP**
  Commodity is effectively dead (2–5%). **BigBasket** Premium is tiny and consistently short (43–59%).
- **The June Primary collapse is broad,** not platform-specific: Blinkit (14%/20%), Swiggy commodity (34%),
  FK-Grocery (9%), CityMall (12%) all crater on sell-in despite a strong May — pointing to a restocking /
  PO-pacing problem this month, not lost demand (Secondary sell-out held far better than Primary sell-in).

---

## 2. The value chain, 2026

JIVO's funnel is a **price-rising litre chain**: oil is made by Jivo Wellness, taken into Jivo-Mart's
warehouse, shipped to platforms (Primary sell-in), then sold to consumers (Secondary sell-out). Each step
adds ₹/L.

### 2.1 Jun-2026 — the full 4-stage chain with the margin ladder

| Stage | What it is | Litres | ₹/L | Gross value | Step vs prior stage |
|-------|------------|--------|-----|-------------|---------------------|
| 1. **Wellness Billing** | Parent makes & bills the oil (supply top) | 811,616 | ₹180.0 | ₹14.61 Cr | — |
| 2. **JM Primary** | Jivo-Mart warehouse intake | 672,739 | ₹192.6 | ₹12.96 Cr | **+₹12.6/L (+7.0%)**, −138,877 L |
| 3. **Primary** | Sell-IN: shipped to platforms (POs) | 484,975 | ₹210.3 | ₹10.20 Cr | **+₹17.7/L (+9.2%)**, −187,764 L |
| 4. **Secondary** | Sell-OUT: bought by consumers | 560,048 | ₹218.2 | ₹12.22 Cr | **+₹7.9/L (+3.8%)**, +75,073 L |

- **Total price markup Wellness → Secondary: +₹38.2/L = +21.2%.** The richest single step is **JM → Primary
  (+₹17.7/L, +9.2%)** — i.e. the margin is concentrated in *getting oil onto the platform shelf*, which is
  exactly the step (Primary sell-in) that is missing target hardest in June. Under-shipping Primary bleeds
  the most valuable jump in the ladder.
- **Litre conversion is lossy at the top:** only **82.9%** of Wellness litres reach JM, and **59.8%** reach
  Primary. ~40% of produced litres do not convert to platform sell-in within the month (timing/inventory,
  not necessarily waste — these are point-in-time card snapshots, not a cohort).
- **The chain is NOT monotonic at the bottom:** Secondary (560,048 L) **exceeds** Primary (484,975 L) in
  June — consumers are pulling **+75,073 L more than Jivo shipped in**, i.e. platform inventory is being
  drawn down. This is the mirror of the Primary-sell-in miss: demand is healthier than restock.

### 2.2 Monthly litres through 2026 (Primary sell-in & Secondary sell-out)

The Wellness and JM-Primary stages are **only captured as the live June KPI cards** — there is no monthly
history for them in this extract (Anomaly #6). What we *do* have monthly is Primary (sell-in) and Secondary
(sell-out), summed across all platforms:

| Month | PRIMARY done (L) | prem-mix | SECONDARY done (L) | prem-mix | Note |
|-------|------------------|----------|--------------------|----------|------|
| Jan | 659,790 | 41% | 658,326 | 40% | no targets |
| Feb | 621,079 | 39% | 565,044 | 40% | no targets |
| Mar | 612,633 | 47% | 584,267 | 44% | no targets |
| Apr | 472,139 | 52% | 438,536 | 54% | **partial snapshot — undercounts** |
| May | 939,589 | 53% | 801,401 | 48% | closed — best month |
| Jun | 577,780 | 53% | 583,695 | 53% | **live / in-progress** |

- **May is the volume peak** (Primary 939.6k, Secondary 801.4k). The Jan–Mar plateau (~620–660k) and the
  April dip are below it — April's dip is largely a data artefact (partial snapshot), so the real shape is
  a steady Jan–Mar base stepping up into a strong May, with June still accumulating.
- Primary and Secondary monthly litres track closely (within ~5–10% most months), consistent with a
  short, fast-turning q-commerce pipeline.

---

## 3. Premium-mix evolution through 2026

Premium-mix = premium litres ÷ total litres. It's the same axis as Home's Category Split and is what
protects the ₹/L ladder (premium realises ₹218 vs commodity's lower deck).

**Secondary (sell-out), monthly:**
| | Jan | Feb | Mar | Apr | May | Jun |
|--|-----|-----|-----|-----|-----|-----|
| 2026 premium-mix | 40% | 40% | 44% | 54%* | 48% | 53% |

**Primary (sell-in), monthly:** 41% · 39% · 47% · 52% · 53% · 53%.

(*April's 54% is partly inflated by the partial snapshot truncating commodity actuals more than premium.)

**Multi-year context (Secondary, full-year average):**
- **2024: 53.7%** premium (premium-led book; commodity ramping).
- **2025: 45.5%** premium — the mix **slid** as commodity volume scaled faster (low of 40% in Jun-2025).
- **2026 H1: 46.3%** and **rising within the half** — from 40% in Jan to 53% in June.

**Read:** the premium pivot lost ground through 2025, and **2026 H1 is clawing it back** — premium-mix has
climbed ~13 points Jan→Jun on the Secondary side and is now back above 50%. This is a quietly positive
structural trend: the same litres are migrating toward the richer end of the ₹/L ladder.

---

## 4. The 5 biggest insights — and data anomalies

### Insights for the owner

1. **May proved the system works; June shows a broad sell-in deceleration that is the #1 risk.** On
   well-calibrated May targets most platforms landed 77–125%. In June the **Primary (sell-in) book
   collapses — commodity at 30% against a 899k-L target (+78% MoM), premium at 55%** — with Blinkit
   (14%/20%), Swiggy commodity (34%), FK-Grocery (9%) and CityMall (12%) all cratering after a strong May.
   The `require_drr` math makes most of these mathematically unrecoverable this month. Because Secondary
   sell-out held far better than Primary sell-in, **this is a restocking/PO-pacing problem, not lost
   demand** — and it directly bleeds the richest margin step (JM→Primary, +₹17.7/L).

2. **Swiggy is the breakout winner — lean in.** It's the only platform that *beats* its Secondary Premium
   target and is widening the beat (83% → 87% → **138%** Apr→Jun), and it was a top Primary performer in May
   (Premium 109%, Commodity 103%). It is carrying the premium story.

3. **Flipkart is the chronic structural laggard on every cut.** Secondary Commodity 11% → 46% → 16%,
   Secondary Premium stuck in the 40–60s, and it has **no Primary targets set at all**. Either fix the
   Flipkart go-to-market or stop setting aspirational targets that it never meets — it is dragging the
   commodity aggregate down.

4. **Premium-mix is structurally recovering in 2026 — protect it.** Secondary premium-mix has risen ~40% →
   53% Jan→Jun, reversing the 2025 slide (FY 45.5%, down from 2024's 53.7%). This is the lever that defends
   the ₹/L ladder (premium ₹218 vs commodity). The premium book is also the *most reliable* against target
   (Secondary Premium held high-70s/80% all quarter while commodity swung 38→90→61%).

5. **Target-setting itself is the weak link — calibration and capacity are mismatched to reality.** Month-1
   (April) targets were guesses: Zepto Premium target 8,798 L → "496%", CityMall Premium 34,870 L → "1%".
   June's commodity sell-in targets were inflated +78% with no matching restock capacity → 30% achieved.
   Given that the value chain only converts **60% of Wellness litres into Primary**, and the **biggest
   margin jump is JM→Primary (+₹17.7/L)**, every mis-set or unmet Primary target is the most expensive kind
   of miss. Tighter, capacity-anchored target-setting (especially on Primary commodity) is the highest-ROI
   fix.

### Data anomalies & caveats

- **#1 — April is a partial/frozen snapshot.** April `est_ltr` ≠ `done_ltr` at *different per-platform
  dates* (e.g. Blinkit `est = 2× done` → captured ~day 15; most others ~day 28–29), and April totals
  (Secondary 438.5k) sit far below every adjacent month. April achievement % is unreliable; **start trust
  at May.**
- **#2 — `targets-over-years.html`'s achievement table is methodologically broken.** It divides
  total-done-across-ALL-platforms by the sum-of-targets-only-where-set, producing nonsense when target
  coverage is partial (it reports **Pri·Prem April 726%, Pri·Comm 402%** purely because only Flipkart-MP
  had an April Primary target of 34k/56k while every platform's done was summed into the numerator). Use the
  like-for-like table in §1.1 instead.
- **#3 — Primary April targets exist ONLY for Flipkart-MP** (34k/56k). All other Primary targets begin in
  May (a slight contradiction with `target-sheets.md`'s "Primary has no April data" — Flipkart-MP is the
  lone exception).
- **#4 — Month-1 calibration whiplash:** Zepto Apr Premium "496%" and Blinkit "176%" are targets set far
  too low; CityMall Apr Premium "1%" is a target set far too high. Not real performance.
- **#5 — The CSV is fresher than the json/HTML/md roll-ups** (later June pull → higher June `done`).
  Headline % differ by **scoping**: the Home roll-up excludes Amazon-MP from Secondary and Amazon +
  Flipkart-MP from Primary. Direction unchanged; §1.1 uses the complete CSV.
- **#6 — No monthly Wellness / JM-Primary history.** The top two value-chain stages exist only as the live
  June KPI cards; monthly history is available for Primary & Secondary only.
- **#7 — Coverage is uneven across the live month.** CityMall and Zomato have **no June Secondary rows**
  (last secondary month May); Zomato has **no Commodity** anywhere; **jiomart has no targets at all**;
  Flipkart has **no Primary targets**. So June aggregates are summed over a *different platform set* than
  May — MoM aggregate comparisons are not strictly like-for-like.
- **#8 — CityMall/Zomato Secondary is sourced from `master_po`** (not `secmaster`), so their "sell-out"
  figures may actually be PO-derived — treat those two platforms' Secondary numbers with caution.
- **#9 — Litres are non-monotonic down the chain** (Secondary 560k > Primary 484k in June). This is
  expected — sell-out can exceed sell-in in a month as platform inventory is drawn down — but means the
  chain reads as "growing" at the bottom while the top is flat.

---

*Built 2026-06-28 from `target-history.csv` (2026-06-28 pull). All figures litres unless ₹/L or ₹ Cr.
Achievement % = done ÷ target over cells with a target; est% = pace projection ÷ target (live month only).*
