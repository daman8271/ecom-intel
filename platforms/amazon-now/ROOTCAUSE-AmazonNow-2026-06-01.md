# Why the Amazon Now Pricing Data Is Wrong — Plain-Language Report

**Date:** 2026-06-01  •  **Prepared for:** business owner  •  **Status of findings:** verified against our own live data captured this morning (the 4 PM raw file and the 110021 probe), plus a cross-check against our regular Amazon scraper.

---

## 1. The three things you caught at pincode 110021 — all confirmed

You flagged three problems at 110021. We checked each one against the live data. **You were right on all three.**

| What you saw | What the data shows | Verdict |
|---|---|---|
| **Groundnut 1L missing** (should be in stock) | The product (B0CKFFW9B6) is **In stock and buyable at ₹193** on its own Amazon page — but it **does not appear in the Amazon Now search at all**, not even when we search the exact words "jivo groundnut oil" (that search returns 9 cards, none of them a groundnut). | **Real miss.** We never see it, so we never report it. |
| **Sunflower 1L shown / wrong status** | The Sunflower 1L (B0B4SJTNF2) page says **"Temporarily out of stock."** It is genuinely OOS right now. | **Genuinely out of stock** — but our pipeline cannot tell "out of stock" apart from "missing," so this looks the same as the Groundnut problem even though the cause is different. |
| **Olive-oil prices wrong** | We reported **Extra Light Olive ₹499**, real price is **₹599** (we were **17% too low**). We reported **Extra Virgin ₹759**, real price is **₹789**. The Extra Virgin card itself even flapped between ₹696 and ₹759 in the same probe. | **Real price errors**, worst on the premium SKUs. |

These are not one-off glitches. They are symptoms of four deeper problems, ranked below by how much damage they do.

---

## 2. Root causes, ranked by damage

### #1 (CRITICAL) — We are scraping the wrong thing entirely. This is not "Amazon Now."

The feed we call "Amazon Now" is **not** the 10-to-30-minute quick-commerce service. It is the **ordinary Amazon marketplace** seen through an old search filter (`i=nowstore`, which traces back to the defunct 2015 "Prime Now / 2-hour" service). Where real quick-commerce isn't available, that search silently shows normal listings with normal delivery dates.

**The proof is unarguable and it is in our own data:**

- Across **all 1,970 listings** we captured, **not one** says "in 10 minutes," "in 2 hours," or any minute/hour ETA. **Every** delivery line is either a calendar date ("FREE delivery Thu, 4 Jun") or a scheduled window ("Tomorrow 6 am - 8 am"), and **every one** ends with the marketplace tail "on orders over ₹149."
- The page **never once** identifies itself as "Amazon Now" (the probe's `mentions_amazon_now` flag is `false` on every search).
- Of the 762 rows we *kept* and published as "Now," **392 (51%) are literally next-day ("Tomorrow") deliveries.**

The genuine Amazon Now (launched in India June 2025, 30-min-or-less) lives on a **different, logged-in storefront** — the "Amazon Local Market" / `alm` surface with `almBrandId=ctnow`, the **same backend Amazon Fresh uses**, which we already scrape successfully in this project. We are pointed at the wrong door.

**Damage:** the entire sheet is mislabelled. The honest number of pincodes with true sub-2-hour Now service in this capture is **0, not the 123 we reported.**

### #2 (HIGH) — Amazon Now search only ever shows ~8% of the catalog

Even setting aside the labelling problem, the search surface only ever returns about **24 distinct Jivo products nationwide** (23 of which are in our catalog) out of roughly **294** — **under 8% coverage.** The other **271 products (92%) never appear in Now search at any pincode.**

- The scraper makes this worse by firing a single `jivo` keyword search, **page 1 only** (scrape.js line 40 and line 134, no pagination). But **more searching would not help**: page 2 returns **zero** Jivo products, and even a targeted "jivo groundnut oil" search returns no groundnut.
- We **proved the products exist**: our regular Amazon scraper, which looks products up by their exact ID, captured **313 of 314** catalog items. They are all live and buyable on Amazon — they are simply **not in the Now search index.**
- Entire categories are absent by Amazon's design: **all Drinks, all Gift packs, all Seeds, all Spices, all Ghee**, and nearly every multi-litre pack and bundle.

**Damage:** your missing Groundnut 1L is a direct symptom. And any "catalog coverage %" we report on this feed is meaningless.

### #3 (HIGH) — The prices come from the search tile, not the real product page

The scraper reads the price off the **search-results card** (scrape.js line 143), not the verified **buy-box** on the product page. The card frequently shows a **wrong variant/pack price** or a **stale deal price**.

- The 110021 olive-oil errors above (₹499 vs ₹599; ₹759 vs ₹789) come straight from this.
- **17 of the 24 products show more than one price** across pincodes for the *same* item. Examples: one olive oil ranged **₹759 → ₹1,799**, the Pomace **₹379 → ₹1,049**, the Groundnut **₹193 → ₹560**. A single product cannot have all those prices — the card is grabbing the wrong number.

**Damage:** prices are off by up to ~17% on the high-value items leadership cares about most, and are too volatile to trust as a single figure.

### #4 (HIGH) — The "is this a Now slot?" filter is too loose

The filter that decides whether a listing counts as "Now" (scrape.js `isNowSlot`, lines 94-99) accepts **any** "Today" or "Tomorrow" plus an am/pm time. So "Tomorrow 6 am - 8 am" passes as genuine Now. A real Now offer would say a **duration** ("in 10 minutes"), never a calendar window. This filter is the mechanism that lets the mislabelled marketplace data through (and is what waved through those 392 next-day rows).

### #5 (MEDIUM) — Wrong-location data is leaking in

The code intends to discard a pincode if Amazon resolved it to the wrong place, but **on the saved rows that check is not enforced.** Result: **16 pincodes recorded data for the wrong location.** Every Bengaluru 560xxx pincode actually resolved to **"Olpad 394540" in Gujarat**, yet we still saved 8-10 "Bengaluru" rows each. Any city-level analysis on those is silently corrupted.

### #6 (MEDIUM) — We can't tell "out of stock" from "missing"

A genuinely out-of-stock item (Sunflower 1L) and a genuinely-missing-from-search item (Groundnut 1L) both just show up as **absent**. We have no way to distinguish a stockout from an index gap, which is exactly why the two 110021 problems looked the same to us.

---

## 3. Prevention plan — what to change and how to prove it works

Ordered roughly fastest-to-slowest. The first three are quick and stop the bleeding today.

**A. Stop the misinformation now (≈1 hr).** Relabel the feed "Amazon scheduled/same-day (marketplace)" and the price column "list/card price (indicative)" in `build_excel.py` and the report. Pure labelling — no scraping change.

**B. Tighten the Now-slot filter (≈1-2 hrs).** Rewrite `isNowSlot` to **require** a minute/hour ETA (e.g. "in 10 minutes," "in 2 hours") and **reject** any calendar date, any "on orders over ₹149" tail, and any bare am/pm window — including "Tomorrow." On today's data this correctly produces **zero** true-Now rows, which is the honest answer.

**C. Fix the location bug (≈1 hr).** Enforce `serviceable = matched && nowOffered` on the saved rows, and drop any pincode whose resolved location label doesn't contain the requested pincode. Removes the 16 Bengaluru→Olpad records.

**D. Drive a known-ASIN list, not a keyword search (≈½ day).** We already have all 314 catalog IDs from the core Amazon scraper. Probe each one on the Now surface directly instead of hoping search surfaces it. Recovers items like Groundnut 1L that exist but never appear in search, and stabilizes coverage per pincode.

**E. Verify price + availability from the product page, not the card (≈½ day).** For the priority SKUs (the four olive oils, Groundnut, Sunflower), re-read the PDP **buy-box** and the availability line, and prefer those over the card. This would have caught ₹499-vs-₹599 and correctly marked Sunflower 1L as **OOS** instead of silently dropping it.

**F. Make the output honest about gaps (≈½ day).** Three columns: **PRESENT / OUT OF STOCK / NOT AVAILABLE ON NOW.** Add a "catalog SKUs not on Amazon Now" list (the ~271, by category). Flag any item showing more than one price across pincodes and collapse to the most common value. Show the funnel (24 products seen → 19 published).

**G. Add an automatic guard so this can't silently regress (≈½ day).** A small per-run probe (like the existing `probe_110021.js`) that checks anchor ASINs at 2-3 pincodes and **fails the run loudly** if: a card price differs from the PDP buy-box by >5%, any slot is a calendar date, or a resolved location doesn't match the requested pincode.

**H. Wire up the real Amazon Now surface (1-2 days, needs an attended session).** Re-point at the logged-in `alm/ctnow` storefront (`amazon.in/fmc/storefront?almBrandId=ctnow`) and capture its in-page JSON responses — the same technique used for BigBasket and Amazon Fresh. Run it under the existing shared `.amazon-account.lock` so Now and Fresh never run at the same time (they share one account-global location).

---

## 4. What is still uncertain — needs one more live check

- **We have not confirmed the real Amazon Now endpoint.** The `alm/ctnow` storefront is confirmed to exist and to require a logged-in, location-resolved session, but the specialists **could not authenticate into it** (correctly — they did not touch your account). We do **not** yet have first-hand proof of its exact search/category API or that it returns genuine minute-level ETAs and Now-specific prices. **This requires one attended live session** before step H can be built.
- **Now is metro-only.** Real Amazon Now covers roughly 2,600 quick-commerce pincodes nationally (metros first). Most of our 332 pincodes will legitimately have **no** Now service — so expect the honest serviceable count to be small, not in the hundreds.
- **Whether Now prices differ from the marketplace.** Quick-commerce is a different fulfilment channel and may price differently per pincode. We won't know the true Now prices until the `alm` surface is live.

---

### Key files referenced
- Scraper: `/opt/ecom-intel/platforms/amazon-now/scrape.js` (single query line 40; page-1-only search line 134; card price line 143; loose slot filter lines 94-99; un-enforced location gate around lines 242-254)
- This morning's raw capture: `/opt/ecom-intel/platforms/amazon-now/result.raw-pre-nowfilter-2026-06-01-1600.json`
- Published feed: `/opt/ecom-intel/platforms/amazon-now/result.json`
- Live 110021 ground-truth probe: `/opt/ecom-intel/platforms/amazon-now/secrets/probe_110021.json`
- Proof the products exist on Amazon: `/opt/ecom-intel/platforms/amazon/result.json` (313/314 captured) and `/opt/ecom-intel/platforms/amazon/products.json` (314 ASINs)
- Prior recon notes: `/opt/ecom-intel/platforms/amazon-now/BLOCKED.md`