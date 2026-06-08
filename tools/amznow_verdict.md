# amazon-now vs amazon-core — owner verdict: is "Now" copying core prices?

**Verdict: CLEAN — Amazon Now is independently sourced, NOT a copy of amazon-core.**
**Confidence: HIGH.** (synthesis of W1 data forensics + W2 code audit + W3 independent live probe — 2026-06-08)

---

## The one-line answer for the owner
Amazon Now scrapes its **own** quick-commerce storefront (`almBrandId=ctnow`, logged-in) and
records the prices that surface lives there. Some SKUs end up at the **same** price as the core
marketplace (Amazon genuinely prices them the same), but a real fraction **differ** — and a copy
could never differ. We proved this three independent ways, including a live hit I made on the Now
surface myself. The old "Now = marketplace SEARCH" bug (ROOTCAUSE-2026-06-01) is fixed and the dead
surface is frozen.

---

## The 3 evidence pillars

### 1. Data divergence (W1 — `tools/amznow_forensics.md`)
- **Snapshot:** of 22 ASINs Now carries, **14 differ / 8 identical** in (sale, mrp); deltas up to
  ₹169 — far above rounding.
- **Time-series (decisive):** ASIN-bridged 7-day history — **15/20 shared ASINs diverge**, ~42% of
  aligned day-points differ, and the gaps are **sustained for days, bidirectional, and criss-cross**
  (Now is higher than core on some days, lower on others). A copy can never criss-cross. *e.g.*
  Pomace 5L: now 1950 / core 2119 held for 5 days; Extra-Virgin 1L: now & core criss-cross in one week.
- **Quick-commerce signal:** **674/674** Now rows carry a real `"10 min"` ETA; **0/314** core rows
  do. Marketplace cannot fake a minute ETA.
- "0 Now-only ASINs" is benign: core is an exhaustive 314-ASIN superset by direct lookup; Now
  surfaces a subset via its **own** search — not seeded from core.

### 2. Code independence (W2 — `tools/amznow_codeaudit.md`)
- **Different surface:** Now = `/s?k=jivo&almBrandId=ctnow` (logged-in ctnow storefront,
  `scrape.ctnow.js:146`); Core = guest `/dp/<asin>` (`amazon/scrape.js:77`).
- **Price comes only from Now's own response:** sale/mrp parsed from the ctnow card's
  `.a-offscreen` (`scrape.ctnow.js:161 → toRow:182`). **No** read of `amazon/result.json` /
  core prices, **no** "Now missing → fall back to marketplace price" path. The shared
  `../amazon/products.json` is used by `build_excel.py:27` for **name/category labels only** — never
  price (every displayed price is a scraped Now row, `build_excel.py:282-285`).
- **Genuine-Now gate enforced:** a row is kept only when `amazon_now_page` AND the offer is an
  instant-minute tier (`isInstantNow` → `'10 min'`) AND the GLOW location matched
  (`serviceable = matched && nowPage && rows>0`, `scrape.ctnow.js:263,269,285`). Scheduled
  Fresh/marketplace chips are dropped; non-Now pincodes record 0 rows.
- The old `i=nowstore` `scrape.js` is **frozen** and unused (`run.sh:16-17` selects
  `scrape.ctnow.js` for amazon-now).
- **Verdict: it is structurally NOT POSSIBLE for amazon-now to copy core prices.**

### 3. Independent live probe (W3 — this report)
I hit the Now surface myself, lock-guarded (`.amazon-now.lock`, never co-scraping), **after** the
background trio finished. `w3_probe.js` @ Bengaluru **560034**, 15:35 IST:
- **Logged in as the dedicated Now account** (`"Hello, Kanhaiya"`), **`amazonNowPage=true`** →
  genuine Now storefront, not marketplace.
- **Real minute ETAs present:** even at 15:35 (evening, instant slots tapering) 2 cards still showed
  the `'10 min'` instant tier; the rest were scheduled tiers (`overnight`/`tomorrow`/`2 days`) which
  the scraper correctly drops. The minute promise is exclusive to genuine Now.
- **Live Now vs live Core (freshness-correct, ~25 min apart):** of 15 shared ASINs, **11 SAME / 4
  DIFFERENT** — `B09NXCPZW1` now 1135 / core 1010 (+125), `B0DC6JR4F3` 279 / 257 (+22),
  `B093BMGPQC` 765 / 789 (−24), `B0B4SJTNF2` 190 / 207 (−17). An independent live read of Now yields
  prices that differ from core on a real subset → **not a copy.**

---

## The honest nuance (so the owner isn't misled)
**Identical prices on many SKUs are EXPECTED and are NOT contamination.** Amazon frequently prices
Now = core for the same product. Sameness alone proves nothing either way. What proves independence
is the combination that a *copy* could not produce: (a) a real subset that **differs**, (b)
differences that **criss-cross over time**, (c) genuine **minute ETAs** absent from core, and (d) a
code path that physically reads only the Now surface.

---

## Freshness anomaly found this run (data-integrity, SEPARATE from contamination)
The owner flagged that the 15:27 manual amazon-now run finished in ~7 min (vs ~26) and
`result.json` `captured_at` = **07:17Z (12:47 IST)**, not ~15:35. Confirmed and root-caused:

- **`scrape.ctnow.js` CRASHED at pincode 66/332** on a transient
  `page.evaluate: TypeError: Failed to fetch` (`fastSetAndSearch`, `scrape.ctnow.js:138`) —
  see `logs/manual-amazon-now-2026-06-08-1527.log:73`. The uncaught rejection killed node
  **before** the single `fs.writeFileSync(result.json)` at `scrape.ctnow.js:307` (only runs after
  the full 332-pincode loop), so **no new result.json was written** (mtime stayed 12:47 IST).
- The **manual** harness (`/tmp/amazon_run.sh`, no `set -e`) continued past the crash and
  `build_excel`/predict/review **re-rendered the stale 07:17Z file**, emitting a misleadingly green
  `DONE verdict=OK rows=674`. The on-disk Now snapshot is the **12:00 cron sweep's** data.
- **The real cron is SAFE:** `run.sh` uses `set -euo pipefail`, so a crashed scrape aborts that
  platform **before** build_excel — no stale-as-fresh build in production.
- **Does this change the verdict? No.** My live probe @15:35 confirms the stale values are still
  **live-accurate** (e.g. B077ZN4G28 1249, B09MJ6QDX7 255, B0DBJ13FKL 909 all match live; the few
  that moved drifted by small real amounts over ~3 h). The data is **stale-by-timestamp, not
  fabricated or cached-wrong.** Contamination verdict = **CLEAN**, unaffected.

## Robustness finding (recommend fixing)
`scrape.ctnow.js` has **no per-pincode try/catch** — one transient `Failed to fetch` aborts the
entire Now sweep, so a cron run loses that slot's Now data instead of skipping a single pincode.
**Recommend:** wrap the per-pincode body in try/catch + continue (record the pincode as 0 rows /
error and move on), so a single network blip costs one pincode, not the whole sweep. (W1 and the
lead independently reached the same recommendation.)

## Residual risk / recommendations
1. **No contamination risk** — Now is independently sourced (HIGH confidence). The next genuine
   re-scrape (lead to run, lock now free) will refresh the timestamp; values are already correct.
2. **Freshness gate gap:** the pipeline accepted a same-day ~3 h-stale `result.json` as fresh
   (review.py freshness only trips on cross-day staleness). Consider rejecting a build whose
   `result.json` `captured_at` predates the run's start, so a crash-then-republish can't ship green.
3. **Add the per-pincode try/catch** so transient fetch errors degrade gracefully.
