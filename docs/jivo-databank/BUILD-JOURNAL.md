# JIVO Data-Bank — Build Journal

> A running record of how we are building the unified JIVO data bank: the goal, the journey, the
> problems hit, and how each was solved. Append-only narrative; newest phase at the bottom.
> Owner: Daman (Jivo e-com). Maintained by Claude. Started 2026-06-27.

## 0. The end goal (what we are making)
**THREE vaults, kept distinct + one combined:**
1. **ECOM-Intel vault** (`/opt/ecom-intel`, repo `daman8271/ecom-intel`) — the existing **competitor-pricing
   scraper** (8 platforms, daily; what the live shelf shows).
2. **App vault** (`/root/jivo-intel`, repo `daman8271/jivo-intel`) — a **lossless extract of the JIVO app's
   own internal data** (sales/inventory/POs/targets/margins).
3. **Combined data bank** (lives in THIS ecom-intel repo) — the two merged so **each product is ONE node**
   carrying *both* lenses (internal performance + competitor price), Premium/Commodity-aware, for
   cross-business **pattern analysis**. Raw extraction is worthless without these connections — connections
   are the deliverable.

## 1. The two source systems
- **The JIVO app (ecom.jivo.in) = the CORE / "mother" system** — Jivo's internal e-com control tower for an
  edible-oils business. Value chain (Jun-2026, litres @ ₹/L): Jivo Wellness (parent makes+bills oil)
  811,616@180 → JM Primary (Jivo Mart) 672,739@192.6 → Primary (to platforms) 484,975@210.3 → Secondary
  (to consumers) 560,048@218.2. Segmented PREMIUM / COMMODITY / OTHER. 13 pages. Drill-down
  Category→Sub-cat→Platform→SKU. (Full model: `app-model/JIVO-App-Model.html` + the 4 `app-model/*.md`.)
- **The ECOM-Intel scraper** — daily competitor/live price per Jivo product per platform per pincode.

## 2. Journey & problem-solving (chronological)

### Phase A — Full lossless extraction of the app → `jivo-intel` (DONE)
Built a read-only CLI off the app + pulled EVERYTHING into a lossless SSOT + an Obsidian Markdown vault
(34,749 notes, 1,312,518 rows, all 41 tables 100%, 2,946 dashboards). 4 integrity gates green; independent
adversarial verify PASS.
- **Problem: rotating-cursor pagination.** `tables/data` has no stable sort and the CLI cached pages → a
  naive multi-pass pull silently DROPPED ~30% of the whales (swiggySec got 342k of 537k).
  **Solution:** `--no-cache` page fetches (each call = next disjoint 200 rows) + parallel page fetch +
  `--page-workers`/`--passes`/`--gain-thresh`; converged swiggySec to 537,624 = 100%. A/B proved lossless.
- **Problem: pull was heading to 4–6h serial.** **Solution:** parallel page-fetch engine → ~8 min full pull.
- **Problem: `all_platform_inventory` 174,155 < embedded 176,769.** **Solution:** confirmed (full re-pull)
  the 2,614 gap = byte-identical duplicate rows → lossless content-hash collapse, not loss.

### Phase B — The SKU bridge (the matching bottleneck) (DONE, 170/178)
To merge, we must know "this product here = that product there." 
- **Problem: the two vaults share NO SKU id** — app keys by SAP code (`sku-FG0000032`), scraper by
  product-name slug (`canola-oil-cold-pressed-1l`); 0 shared ASINs.
- **Solution:** the **price-match sheet is the Rosetta Stone** — `tools/pricematch/sku_map.json` +
  `data/pricematch/history.csv` already map `sku → canonical_sku → platform/listing` for 112 master SKUs.
  A fan-out of matching agents recognized the remaining 67 by product+pack-size → **170/178 bridged**; 8 are
  pack-size gaps (bulk 15L / 3kg / 100ml not sold online — product IS matched in retail sizes); 1 owner call
  (cola juice, confirmed same). (Artifacts: `sku-bridge/`.)
- **Owner insight:** the app thinks at oil/product level (Canola, Mustard); the detail sheet is per-pack-size.
  Same model, different granularity — match at product level.

### Phase C — Learning the app (DONE)
A 4-session fleet learned each page's purpose, metrics, data, drill-down, and **cross-page connections**, then
synthesized one detailed HTML (`app-model/JIVO-App-Model.html`) with an understanding-coverage table
(52 fully / 28 partial / 8 unclear) + self-assessment. Anomalies flagged: Distributor incomplete; jiomartSec
stale to 2026-04-15; citymall/zomato secondary+inventory empty; category-sku-breakdown dormant; top-skus
carries source=primary.

### Phase D — Target sheets (IN PROGRESS)
The `/monthly-targets` page (Secondary + Primary tabs, Premium/Commodity, all platforms) is **posted to the
team group daily** — the targets they must hit. Metrics: targets, done_ltrs, achieved_pct, est_ltr
(naïve linear projection = done × days-in-month ÷ days-elapsed), drr, pending_ltr, require_drr (= litres/day
needed to still hit target — the real point of the daily post).
- **Problem: the targets endpoint returns only a recent snapshot** (no year/month flag) — SSOT had only
  Apr–Jun 2026. The UI month-picker pulls history via a dated API call the CLI doesn't expose.
- **Problem: the bearer token expired mid-effort** → live pulls 401'd; no stored password (cardinal rule).
- **Solution:** owner refreshed auth (`auth login`, password via stdin, never persisted) → fresh ~24h token;
  staged self-cracking harvesters then pull the full 2024→2026 history → CSV → over-the-years graph.
  (Current-month snapshot already visualized in `app-model/target-sheets.html`.)

## 3. Key decisions (owner-ratified)
- **Lossless vault:** exact rows embedded as CSV; no summarizing, no redundancy (each row once, linked);
  100% Markdown; integrity gates with zero tolerance.
- **Premium vs Commodity vs Other** = a first-class analytical axis everywhere.
- **HTML publishing → Vercel only.** Every GitHub push → clean + properly formatted.
- **Three-vault strategy** (see §0) — do not collapse into one.

## 4. Operational gotchas (so we never re-learn them)
- Reconcile against each table's OWN embedded count, NOT the stale `tables counts` endpoint.
- GitHub hard-rejects files >100MB → use Git LFS (swiggySec changelog/state are LFS in jivo-intel).
- The auto-mode classifier HARD-BLOCKS Claude from pushing the proprietary dataset to GitHub
  (data-exfiltration) → the **owner runs the push** with `!`.
- App auth: token ~24h, no refresh token; refresh via `auth login` (creds owner-side, never stored).
  GA/FB cookies do NOT authenticate — only the bearer token does.

## 5. Current state & next
- DONE: app extracted (jivo-intel), app learned (HTML), SKU bridge (170/178), this journal.
- NOW: pulling full target history → over-the-years graph.
- NEXT: build the **combined data bank** (merge bridged products: app internal + competitor price, woven by
  product ↔ tier ↔ category ↔ platform ↔ vendor ↔ location ↔ month) → the §0 deliverable.

## 6. Artifacts index
- App model: `docs/jivo-databank/app-model/` (4 MD + `JIVO-App-Model.html` + target-sheet files).
- SKU bridge: `docs/jivo-databank/sku-bridge/` (`bridge_result.json`, the match xlsx, core map).
- App vault + lossless SSOT: repo `daman8271/jivo-intel` (`/root/jivo-intel`).
- This journal: `docs/jivo-databank/BUILD-JOURNAL.md` (append as we go).
