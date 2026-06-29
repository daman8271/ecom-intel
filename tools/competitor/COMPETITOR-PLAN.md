# Competitor Price Intelligence — V1 (Quick-Commerce)

Phased build plan for a quick-commerce competitor price-tracker that rides on the
existing `/opt/ecom-intel` scraper fleet without touching the live JIVO pipeline.

Status: **planning / Phase 0 scaffold in progress.** Nothing here is cron-wired and
nothing here can land in the daily mailer (see Guardrails). Owner sign-off required
before Phase 4 (verify + push).

---

## Why / the insight

Every quick-commerce platform answers a **search query**, not a brand lookup. When our
scraper asks Blinkit / Zepto / Flipkart-Minutes for "olive oil" against a pincode, the
response payload already contains *every* brand the store ranks for that term — Fortune,
Saffola, Figaro, Borges, Oleev, bb Royal, store private-labels — sitting in the **same
JSON response as the JIVO listing we keep.** Today the live pipeline filters that response
down to JIVO SKUs and **throws the competitors away.**

That discarded data is a free, pincode-accurate, daily competitive price book: what each
rival charges, their MRP, their live discount, their stock state, and their **search rank
versus JIVO** in the exact store a JIVO buyer would see. We are already paying the scrape
cost. V1 is about *keeping* the rows we already fetch, not adding new traffic.

---

## Scope

- **V1 = Blinkit first.** Cleanest in-page listing API, already scraped on-VPS daily,
  store_id captured, no login/proxy. Prove the whole loop on one platform.
- **Then Zepto + Flipkart-Minutes.** Same on-VPS scrape surface, same per-pincode model;
  add once the Blinkit lane is verified.
- **Instamart deferred.** Swiggy search/v2 is AWS-WAF-blocked from this VPS datacenter IP
  (re-confirmed first-hand — even Swiggy's own page 403s from the box). Competitor capture
  for Instamart needs the off-box Mac / residential-IP collector, so it is **LATER**, not V1.
- **Out of scope for V1:** national / marketplace platforms (Amazon, BigBasket-national,
  JioMart, flat e-com). Those are national-priced, different identity model, different
  cadence. National + Amazon is a deliberate LATER phase, not part of V1.

---

## Geography

- **~60 pincodes: 2–3 per city × 25 cities.** Wide enough to read regional price spread,
  small enough to stay inside the existing serial scrape budget and the cron deadline.
- **Seeded from the price-match key pins** so competitor numbers line up with the locked
  JIVO price-match surface day one — includes **Delhi 110092** and **Bengaluru 560006**.
- Remaining pins drawn from the Wave-1 anchor configs already used by blinkit/zepto/
  flipkart-minutes (`platforms/<p>/pincodes.full25.json`), one or two representative
  metro/tier-1 pincodes per city.
- **File:** `tools/competitor/top_pincodes.json` (same record shape the scrapers already
  consume via `PINCODES_FILE`, so no scraper plumbing changes are needed).

---

## Method

- **Category-sweep queries, not brand-by-brand.** Query the broad category term
  (`olive oil`, `mustard oil`, `sunflower oil`, `canola oil`, `rice bran oil`,
  `groundnut oil`, `soyabean oil`, `blended oil` — see `category_queries.json`) and read the
  *whole* ranked result. One sweep per category surfaces all rivals at once; brand-by-brand
  would multiply traffic and still miss listings we did not name.
- **Brand whitelist + tag.** Each returned listing is matched against the alias table in
  `competitor_brands.json` (`ours` = Jivo/Sano; `brands[]` with per-brand `aliases` and
  `categories`; plus a `by_category` index). Matches are tagged with their brand + category;
  unmatched noise (bulk/reseller, unrelated SKUs) is dropped.
- **Capture per listing:** `price` (selling), `mrp`, `discount`, `stock`/in-stock flag,
  `store_id`, and **search `rank`** within the category response. Rank-vs-JIVO is a primary
  output, not a nice-to-have.
- **Keep `store_id` + canonical** on every row. `store_id` is the real dark-store the
  pincode resolves to (Blinkit/Zepto capture it natively); the canonical product key lets us
  **dedup** the same listing seen across pincodes/days and build a clean **trend** series.

---

## The identity problem

A flat brand+name match is wrong for edible oil. The compare logic (`maps_to_jivo.json`)
normalises every competitor row onto a JIVO **bucket** keyed `category + sub_grade + pack`,
then compares on a **unit price**, never sticker price:

- **Split olive grades.** Olive is not one product. Extra-light / pure / pomace / extra-virgin
  are different price tiers and must map to the matching JIVO olive bucket — never collapsed
  into a single "olive oil" line.
- **Blends own a category.** "Blended" / multi-source oils are their own category bucket, not
  folded into the dominant constituent oil.
- **PACK DEFLATION — the headline trap.** Rivals routinely ship **910 g / 930 ml priced and
  shelved as "1L".** Comparing sticker-to-sticker overstates JIVO's price. So **always compare
  real per-litre:**
  - convert grams → ml by **density** (`oil = 0.916 g/ml`, `ghee = 0.91 g/ml`),
  - snap to the nearest true pack volume (`round_vol_ml`: 200/250/500/1000/2000/4000/5000/15000 ml),
  - derive `per_litre` from the *actual* contents, not the label.
- **Ghee compares per-kg** (mass basis), not per-litre.

JIVO anchor prices in the buckets come from the price-match regimes
(`tools/pricematch/sku_map.json`, BAU street regime + MRP), carried as `jivo_*_per_litre`
so the gap is computed against the agreed JIVO reference, not a scraped JIVO row.

---

## Guardrails

This lane must be invisible to the live JIVO pipeline.

- **Env-gated: `COMPETITOR_MODE=1`.** With the flag unset, the scrapers behave exactly as
  today (JIVO-only). The live JIVO path is byte-for-byte unchanged; competitor capture is a
  branch that only fires when the env var is on.
- **Non-`Jivo-` filenames.** The daily mailer + WhatsApp poster glob `Jivo-*.xlsx`. Every
  competitor artifact is named with a different prefix (`Competitor-*`), so the mailer
  **can never pick one up** and leak it to the team list.
- **Separate output dir.** Competitor outputs land in their own directory
  (`output/competitor/`), not in `output/` next to the shipped JIVO reports.
- **Never touch the locked price-match master.** Read-only consumption of
  `tools/pricematch/sku_map.json` for JIVO anchors; we do not write to, extend, or re-map the
  scope-locked ~96/114-SKU master. No new platform listings are added to it.
- **Not cron-wired.** V1 ships as a manual, operator-run lane. No crontab entry, no
  run_all.sh hook, until the owner approves a cron lane (LATER).

---

## Phases

- **Phase 0 — Scaffold.** Config files in `tools/competitor/` (`category_queries.json`,
  `competitor_brands.json`, `maps_to_jivo.json` — done) + author `top_pincodes.json` and the
  `run_competitor.sh` wrapper + this plan. No scraper changes yet.
- **Phase 1 — Blinkit mode + live test.** Add the `COMPETITOR_MODE` branch to the Blinkit
  scraper (keep + tag competitor rows instead of dropping them), write the raw competitor
  capture, and **live-test on 110092 + 560006**. Validate brand tagging, per-litre math, and
  store_id capture against the app by hand.
- **Phase 2 — Zepto + Flipkart-Minutes.** Port the same env-gated branch to both. Confirm
  Zepto store_id and FKM listing fields land the same shape.
- **Phase 3 — Lean gap report.** Build `build_competitor_report.py`: per category/pincode,
  JIVO per-litre vs each rival per-litre, the gap, rank-vs-JIVO, stock, and a flagged
  pack-deflation column. Lean — a gap book, not a dashboard.
- **Phase 4 — Verify + push.** Adversarial check of a sample against the live apps, confirm
  guardrails (no `Jivo-` collisions, mailer untouched, master untouched), then owner runs the
  push with `!` (classifier blocks Claude pushing ecom data).
- **LATER:** weekly competitor cron lane (separate from the deadline-aligned JIVO crons);
  competitor-aware verdict gate (let a rival undercut flag a JIVO price hold);
  data-bank competitor lens (fuse into the combined vault); Instamart competitor capture
  off-box (Mac / residential IP); Amazon + national platforms.

---

## Files

Under `tools/competitor/`:

- `COMPETITOR-PLAN.md` — this plan.
- `category_queries.json` — broad category sweep terms + `keep_jivo_query` flag.
- `competitor_brands.json` — `ours` list + brand whitelist with `aliases`/`categories` +
  `by_category` index. The tag/keep source of truth.
- `maps_to_jivo.json` — compare model: density table, `round_vol_ml`, and the
  `category+sub_grade+pack` buckets carrying JIVO per-litre anchors from the price-match regimes.
- `top_pincodes.json` — *Phase 0* — ~60 pins (2–3 × 25 cities), seeded from price-match key
  pins incl. 110092 + 560006; `PINCODES_FILE`-compatible record shape.
- `run_competitor.sh` — *Phase 0* — env-gated wrapper: sets `COMPETITOR_MODE=1` + the pincode
  file, dispatches to the per-platform scraper, lands output in `output/competitor/`.
- `build_competitor_report.py` — *Phase 3* — the lean gap report (`Competitor-*.xlsx`).

Env-gated scraper changes (in `platforms/<p>/`, branch only fires when `COMPETITOR_MODE=1`):

- `platforms/blinkit/` scraper — *Phase 1* — keep + tag competitor rows.
- `platforms/zepto/` scraper — *Phase 2*.
- `platforms/flipkart-minutes/` scraper — *Phase 2*.

Output (separate dir, non-`Jivo-` prefix): `output/competitor/Competitor-*.xlsx` / raw JSON.

---

## How to run

```bash
COMPETITOR_MODE=1 PINCODES_FILE=tools/competitor/top_pincodes.json \
  bash tools/competitor/run_competitor.sh blinkit
```

`COMPETITOR_MODE=1` flips the scraper into keep-competitors mode; `PINCODES_FILE` points it
at the ~60-pin competitor geography (relative path is normalised to absolute, same as the
live run). Swap `blinkit` for `zepto` / `flipkart-minutes` once Phase 2 lands. Output goes
to `output/competitor/` under a `Competitor-` prefix — never the mailer-globbed `Jivo-*`.
