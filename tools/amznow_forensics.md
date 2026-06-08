# W1 — DATA FORENSICS: Is amazon-now copying amazon-core prices?

**Question (owner):** Does `amazon-now` scrape genuinely different prices from `amazon`
(core marketplace), or is it silently re-using the same marketplace prices labelled "Now"?
This was a real past bug (ROOTCAUSE-AmazonNow-2026-06-01.md — Now once published marketplace
SEARCH prices off the legacy `i=nowstore` surface).

**Method:** adversarial — I tried to *prove contamination* (copy), and only conclude CLEAN
because every test failed to show it. Read-only; no scraping, no edits outside this file.

---

## VERDICT: **CLEAN** ✅

amazon-now sources its prices **independently** from the genuine Amazon Now storefront
(`almBrandId=ctnow`). It is **not** copying amazon-core. Four independent tests all point the
same way, and the strongest one (time-series) is decisive:

1. **Code provenance** — the now scraper never reads any amazon-core file. ASINs, titles and
   prices all come from the live ctnow search DOM. (No copy *path* exists.)
2. **Price divergence (snapshot)** — only 8/22 ASINs share an identical (sale, mrp); 14/22
   differ, by up to ₹169, far beyond rounding.
3. **Time-series independence (decisive)** — over 7 days, 15/20 shared ASINs diverge from
   core at ≥1 point; 42% of aligned points differ; divergences are **sustained for days and
   run in both directions** (now sometimes higher, sometimes lower than core, and they
   criss-cross). A copy could never do this.
4. **Now-surface signal** — every one of the 674 now rows carries a genuine "10 min" instant
   ETA; 0/314 core rows carry any ETA. Marketplace data cannot fabricate a minute-level ETA.

The owner's flagged "suspicious" fact — *now has 0 ASINs that core lacks* — is fully
explained and is **not** evidence of seeding: see §3.

---

## 1. Catalog provenance (code) — Now discovers its own ASINs; never reads core

Live scraper: `platforms/amazon-now/scrape.ctnow.js` (wired in `run.sh:17`,
`SCRAPER="scrape.ctnow.js"`).

- **ASIN discovery is an independent search on the Now storefront.** `fastSetAndSearch()`
  fetches `/s?k=jivo&almBrandId=ctnow` and reads ASINs straight off the result cards
  (`[data-component-type="s-search-result"][data-asin]`, scrape.ctnow.js:146-152). The ASIN
  set is whatever the *Now* surface returns for that pincode — not a list handed in from core.
- **Prices come from the ctnow card DOM**, not core: `price`/`mrp` are read from
  `.a-price .a-offscreen` / `[data-a-strike] .a-offscreen` on the Now card (lines 161-162),
  carried verbatim into `toRow()` (`sale = numPrice(card.price)`, line 184).
- **No code path reads amazon-core.** `grep` for `amazon/`, `../amazon`, `result.json`,
  `products` in scrape.ctnow.js returns only its **own** `OUT_FILE` and an attempt to load a
  **local** `products.json` *in the amazon-now dir* — and **that file does not exist**
  (`ls platforms/amazon-now/products.json` → absent), so `PRODUCTS = {}` and even the
  metadata-enrichment fallback is inert. The scraper is 100% dependent on the live ctnow
  search for ASIN, title **and** price.

**Why Now's ASINs are a subset of core's (the owner's "suspicious" point):** core captures
the *entire* Jivo catalogue (314 ASINs by **direct ASIN lookup** — it is given the full ID
list). Now only surfaces what its quick-commerce search index returns at serviceable
pincodes (~22 distinct Jivo ASINs nationally). Any ASIN Now can possibly surface is therefore
necessarily already inside core's exhaustive 314 — *0 now-only ASINs is the expected outcome
of core being a superset, not of Now reading core's list.* Same-products is fine; the test
that matters is whether the **prices** are independently sourced — §2/§3 show they are.

---

## 2. Price divergence — snapshot table (by ASIN)

Modal (sale, mrp) per ASIN across all pincodes. **NOTE on snapshot:** at the time of writing,
a live re-scrape is mid-flight; this table compares **now @ 2026-06-08 07:17Z** (this
morning's sweep) vs **core @ 2026-06-08 09:40Z** (re-scraped ~2h later). Because the two
captures are ~2h apart, some differences include genuine intraday drift — the §3 time-series,
which aligns same-day/same-slot, is the clean test. *(Will refresh this table with the
fresh same-run now snapshot once the live run reaches "amazon-now: DONE".)*

| ASIN | now sale | now mrp | core sale | core mrp | Δsale | verdict | name |
|---|--:|--:|--:|--:|--:|---|---|
| B077ZN4G28 | 1193 | 1650 | 1249 | 1650 | −56 | **DIFFER** | Canola 5L |
| B07X53ZL6J | 1950 | 4999 | 2119 | 4999 | −169 | **DIFFER** | Pomace Olive 5L |
| B0821DNF2W | 379 | 1049 | 379 | 649 | 0 | **DIFFER (mrp)** | Pomace Olive 1L |
| B091XPD9J3 | 960 | 1250 | 960 | 1250 | 0 | identical | Kachi Ghani Mustard |
| B093BMGPQC | 789 | 1799 | 789 | 1799 | 0 | identical | Extra Virgin Olive 1L |
| B0991VMDB1 | 1049 | 1350 | 987 | 1350 | +62 | **DIFFER** | Sunflower (unrefined) |
| B09HZY97FR | 499 | 1499 | 499 | 1499 | 0 | identical | Extra Light Olive 1L |
| B09MJ6QDX7 | 259 | 375 | 255 | 375 | +4 | **DIFFER** | Canola 1L |
| B09NXCPZW1 | 1135 | 2799 | 1010 | 2799 | +125 | **DIFFER** | Extra Light Olive 2L |
| B09NYCSQLF | 181 | 255 | — | 450 | n/a | **DIFFER** | Kachi Ghani (chem-free) |
| B0B4SJTNF2 | 192 | 275 | 207 | 275 | −15 | **DIFFER** | Sunflower 1L |
| B0B6HNNL5B | 199 | 225 | 199 | 225 | 0 | identical | Soyabean 1L |
| B0BZ8K3DQP | 539 | 700 | 539 | 700 | 0 | identical | Coconut 1L |
| B0C9Q1S6QG | 909 | 1050 | 930 | 1050 | −21 | **DIFFER** | Gold Refined |
| B0CKFFGC31 | 1074 | 2800 | 1079 | 2800 | −5 | **DIFFER** | Groundnut 5L |
| B0CKFFW9B6 | 193 | 560 | 193 | 560 | 0 | identical | Groundnut 1L |
| B0CT5MYSDS | 173 | 225 | 173 | 225 | 0 | identical | Gold Premium Refined |
| B0DBHQ2QWW | 189 | 285 | 178 | 285 | +11 | **DIFFER** | Rice Bran 1L |
| B0DBJ13FKL | 909 | 1425 | 909 | 1425 | 0 | identical | Rice Bran 5L |
| B0DC6JR4F3 | 279 | 325 | 257 | 325 | +22 | **DIFFER** | So-Olive 1L |
| B0DM2G4YCC | 35 | 100 | — | 750 | n/a | **DIFFER** | Wheatgrass Juice |
| B0FF9P7XVX | 259 | 355 | 259 | 395 | 0 | **DIFFER (mrp)** | Yellow Mustard 1L |

**Snapshot result:** 22 now ASINs, all 22 also in core (0 now-only). **14 differ, 8 identical.**
Differences are real (|Δsale| up to ₹169, median ₹18); the only ~0 cases are genuine
mrp-only differences, not rounding. The 8 identical-price ASINs are simply SKUs where the
marketplace list price and the Now price currently coincide — expected, and consistent with
independent sourcing.

---

## 3. Time-series independence — **the decisive test**

A pure copy would equal core at **every** aligned timepoint. To test this I bridged the two
platforms' `history.csv` by ASIN (their `canonical_sku` strings differ — core canonicalises
from full catalogue titles, now from search-card titles — so canonical can't be joined
directly; I mapped each platform's canonical→ASIN from its current `result.json`, then aligned
by ASIN at each (date, slot)). 21 shared ASINs, 20 with ≥2 aligned points over 2026-06-01→08.

**Result: 15/20 ASINs diverge from core at ≥1 point; 50/117 aligned points differ (42%).**
The divergences are **sustained over days** and run **in both directions** — the signature of
independent sourcing, the opposite of a copy:

- **Pomace Olive 5L (B07X53ZL6J): now ₹1950 vs core ₹2119 — held for 5 consecutive days**
  (06-05→06-08). A copy cannot maintain a ₹169 gap for five days.
- **Sunflower unrefined (B0991VMDB1): now ₹1049 > core ₹976 for 5 days** — Now priced
  *higher* than core, sustained. A copy is always ≤/= core, never persistently above.
- **Sunflower 1L (B0B4SJTNF2): now ~₹177 vs core ₹207 for 4 days** (Δ ≈ −30, sustained).
- **Extra Virgin Olive 1L (B093BMGPQC): now and core criss-cross** — 06-04 now 759 / core 789;
  06-05 now 789 / core 759; 06-08 now 789 / core 765. They move in **opposite directions in
  the same week**. Impossible under any copy hypothesis.
- **Canola 5L (B077ZN4G28):** tracked equal 06-05/06, then split to now 1193 / core 1234 and
  **stayed split** 06-07/08 — independent step-changes.
- **Rice Bran 1L (B0DBHQ2QWW): now ₹189 vs core ₹178 for 4 days** (sustained +11).
- **Convergent-then-divergent** SKUs (B0821DNF2W, B091XPD9J3): differ on 06-01, then converge —
  again, independent movement, not lock-step.

Four ASINs tracked **identically 7/7** (B09HZY97FR Extra Light 1L, B0B6HNNL5B Soyabean,
B0BZ8K3DQP Coconut, B0DBJ13FKL Rice Bran 5L). This is exactly what independent sourcing of a
shared underlying list price looks like — some SKUs genuinely price the same on both channels.
It is *not* a copy signature, because the *other* 15 SKUs demonstrably do not track.

> A copy hypothesis predicts `different = 0` at every point. Observed: 42% of points differ,
> with multi-day, bidirectional, criss-crossing gaps. **Copy hypothesis: refuted.**

---

## 4. Now-surface signals — Now carries a quick-commerce signal core cannot

- **Every one of the 674 now rows carries a genuine instant ETA** — `now_eta`/`now_slot` =
  "10 min" for 674/674 rows (`summary.now_tier_breakdown = {"10 min": 674}`).
- **0/314 core rows carry any ETA** (`now_eta`/`now_slot`/`eta_min` all empty on core).
- The scraper only keeps a row when the page is genuinely Amazon-Now-branded
  (`amazonNowPage`) **and** the card shows an instant-minute tier (`isInstantNow`,
  scrape.ctnow.js:109-111, 263-285). Scheduled tiers (tomorrow/today/overnight = Amazon
  **Fresh**) are dropped. This is the fix for the original `i=nowstore` mislabel bug; the
  current surface emits a minute-level ETA that the marketplace `/dp` path provably never
  produces. Marketplace data cannot fabricate a "10 min" ETA — its presence on 100% of now
  rows is positive proof the data is sourced from the live Now storefront, not from core.

---

## Caveats / scope

- §2 snapshot is a ~2h-skewed pair (live re-scrape in flight); the §3 time-series is the clean,
  same-slot test and is decisive on its own. Table §2 will be refreshed to the same-run pair
  once the live run reports "amazon-now: DONE".
- A handful of single-day spikes in §3 (e.g. core 06-01/06-04 jumps of −189/−259) are
  *core-side* combo/cross-sell artifacts, not now contamination; they don't affect the
  conclusion (they show core moving while now didn't — still independent).
- History join is ASIN-bridged via today's canonical→ASIN map; ASINs whose card title drifted
  out of today's map are simply absent from the time-series (conservative — it can only
  *under*-count divergence, never invent it).

**Bottom line:** code shows no copy path, snapshot shows 14/22 prices differ, the 7-day
time-series shows sustained bidirectional divergence (refuting copy), and 100% of now rows
carry a 10-min ETA core never has. **amazon-now is CLEAN.**
