# JIVO — 2026 Deep-Dive (H1, Jan–Jun) — consolidated

> Synthesis of the four domain reports in this folder (secondary / primary / inventory-marketing /
> targets-and-bigpicture), all mined from the 2026-06-27 SSOT + live data and cross-validated.
> Built 2026-06-28.

## TL;DR
2026 H1 is a **strong-growth, premium-recovering** year that's **healthy on sell-OUT but wobbling on
sell-IN**. Consumers are buying (Secondary ≈ **3.63M L**, premium-mix climbing 40%→~53%); the problem is
**restocking** — June Primary (sell-in) cratered, fill-rate is eroding, and the misses are mostly
**self-inflicted target-setting**, not lost demand. Swiggy & Zepto are breaking out; Flipkart-family &
CityMall/Zomato are declining; Amazon is the flat, mature anchor.

## 1. Growth & premium-mix
- **Secondary sell-out ≈ 3.63M L** H1 (≈3.78M w/ June projected); **Primary sell-in 3.88M L** (Prem 1.86M /
  Comm 2.03M). vs 2024 the business has ~3–4×'d.
- **Premium-mix recovering**: ~40% (Jan/Feb) → low-50s (June) on Secondary — reversing 2025's slide
  (FY ~45.5%, down from 2024's 53.7%). Premium is also the most reliable vs target → **protect it** (it
  defends the ₹/L ladder: premium ₹218 vs commodity).

## 2. Platform scorecard (2026)
- 🚀 **Swiggy — breakout winner**: now #1 quick-commerce (156k L June), Secondary Premium target 83→87→**138%**
  Apr→Jun. **Lean in.**
- 🚀 **Zepto**: +74% Q1→Q2, 76% premium, inventory grew 6×.
- ⚓ **Amazon — mature anchor**: ~36% of sell-out, flat (+0.15% June YoY); ~34% of sell-in but the **worst
  PO filler (42% vs ~68%)**. Rebuilt stock + cleared aged overstock (₹3.9M→₹0.5M).
- 📉 **Laggards (declining)**: Flipkart −37%, Flipkart-Grocery −53%, CityMall −50%, Zomato −23%. Flipkart has
  **no Primary targets set at all** → fix GTM or stop setting unmet targets.
- 💀 **JioMart — effectively dead**: 0 sellable inventory since 2026-04-16; secondary stale to Apr-15.

## 3. #1 RISK — June Primary sell-in collapse (mostly a target-setting problem)
- June Primary: Commodity **30%** vs an **inflated 899k-L target (+78% MoM)**, Premium 55%. But the target was
  set **2–4× above what platforms actually ordered** (FK-Grocery 9×, CityMall 3×, Swiggy 2×); `require_drr`
  ran 9–33× the run-rate = **mathematically unreachable**. So **~70% is target-setting, not fill failure.**
- **Genuine fill failure is narrow**: Blinkit (28%) and Swiggy-commodity (46%). Secondary sell-out held up →
  it's **restocking/PO-pacing**, not lost demand — and it bleeds the richest margin rung (JM→Primary, +₹17.7/L).

## 4. Operations — fill-rate erosion
- PO-cohort fill **83% (Jan) → 75% (May)**, miss 17%→24%; **lead-times lengthening** (Swiggy 8.9→10.9d,
  Zepto 6.8→9.2d). Open **pendency 189,792 L** (Swiggy+CityMall+Zepto = 94%). Zomato steadiest filler.

## 5. Inventory health (as of 2026-06-26)
- Platform stock **294,013 L** (64% premium). **Swiggy stock-out risk = ₹16.96M potential GMV loss** (43% in
  DOH<7, 198 SKUs DOH<7) — the urgent one. Amazon healthy/rebuilt; JioMart dead.

## 6. Marketing & ROAS
- Ad spend **₹25.3M → ₹354.5M attributed = ~14× blended ROAS** (Zepto 18.7× best, BigBasket 6.5× worst).
- Amazon-deep (986 campaigns, ACOS 9.1%, only 3% new-to-brand). Coupons **76% of budget unused**;
  brand-fund ₹2.1M (Blinkit+Zepto) — **Swiggy brand-fund effectively unwired** (despite Swiggy being the winner).

## 7. Price competitiveness
- **43% of active listings below the agreed price floor** (₹5,709 exposure; worst Flipkart & Amazon —
  Groundnut 5L −21.9%). Amazon ASP sits **above** the live shelf on **89/95 ASINs** (resellers undercutting).

## 8. Target achievement — corrected (like-for-like; only platforms with a target set)
Targets exist only **Apr-2026 onward**. April is a frozen/partial snapshot (unreliable — the earlier
`targets-over-years.html` table over-stated it by dividing all-platform done by partial target coverage; now
corrected). Trust **May→June**: May ≈ 83% blended; June pacing ~82% (Secondary premium ~94%, commodity ~72%).

## 9. Data-quality caveats (so numbers are trusted correctly)
- **April = truncated/frozen snapshot**; **June = MTD** (use projections). Trust May as the clean month.
- JioMart stale to 2026-04-15; CityMall/Zomato are sheet-only with default-looking splits.
- `inventory-match` null for all 10 platforms; non-Amazon `soh-doh` zeroed; `amazon_price_data` a stale
  2-date snapshot; corrupt 2026-04-15 Amazon snapshot; June `state-sales` Amazon figure corrupted (753k vs
  ~155k) → use May for geography.
- **Value-chain top rungs (Wellness Billing, JM Primary) are owner KPI cards, NOT in the SSOT**
  (`prim_master_po` empty; JIVO-Mart vendor delivers ~0 L) — sourced from the app's Home cards/screenshots,
  not our tables. Only the Primary rung (484,975 L @ ₹210/L) is reproducible from data.

## 10. Highest-ROI recommendations
1. **Fix target-setting** — anchor commodity targets to capacity/actual orders (the single most expensive
   miss is an unmet Primary target at the +₹17.7/L rung).
2. **Resolve Swiggy stock-outs** (₹17M GMV at risk) and **wire Swiggy brand-fund** — it's the winning platform.
3. **Decide Flipkart-family & JioMart** — fix GTM or stop spending targets/effort on declining/dead channels.
4. **Defend premium-mix** (the margin lever) and **enforce the price floor** (43% of listings under it).

— Sources: `secondary-2026.md`, `primary-2026.md`, `inventory-marketing-2026.md`, `targets-and-bigpicture-2026.md` (this folder).
