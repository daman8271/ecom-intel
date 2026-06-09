# Flipkart-Minutes RE-EXAMINE (post-zepto skepticism) — 2026-06-09 (W3, pmcover)

## VERDICT: **REAL thin — re-confirmed LIVE. NOT a capture bug.**
The owner's zepto catch (a live ₹469 CANOLA 1+1L our sheet showed as n/s) was a genuine
**search-lag / hidden-variant** capture bug. He suspects fkm is the same. **It is not.** I ran
the *exact same skeptical test* on fkm and the discovery mechanism is **complete**: every
in-stock Jivo SKU a dark store carries surfaces in our `q=jivo` fetch. The thin per-store
catalog is the real hyperlocal assortment. **No scraper change. No data merge. result.json
untouched.** Tomorrow's 08:32 sweep is unaffected.

---

## Why zepto broke but fkm doesn't — the mechanism is different
- **zepto:** a parent listing HIDES its sibling variants; a plain search for "jivo" returns the
  parent and never the variant SKUs → the seed/PDP pass was the only way to reach them, and an
  incomplete seed silently dropped 9 variants (CANOLA 1+1L etc.). Search truncation = real.
- **fkm:** every pack/size is its **own independent search listing** (its own pid + card). There
  is no parent-hides-variant mechanism. A broad `q=jivo` BROWSE_PAGE returns the store's full
  in-stock Jivo set in page 1. So the failure mode that bit zepto **cannot exist here** — and I
  proved the search isn't truncating by another route either (below).

## The decisive test (zepto methodology, applied to fkm) — lock-safe, /tmp only
For the two reference pincodes, I compared the broad `q=jivo` against **8 TARGETED per-product
searches** (`jivo canola oil`, `jivo mustard oil`, `jivo olive oil`, `jivo pomace olive`,
`jivo soybean oil`, `jivo mineral water`, `jivo extra light olive`). If the broad search were
hiding a live SKU (the zepto failure), a targeted search would surface it.

| pincode | store | broad `q=jivo` in-stock Jivo | UNION of ALL 8 targeted searches | EXTRA surfaced by targeting |
|---|---|---|---|---|
| 110095 Delhi | del_193_wh_hl_01 | Mustard Oil Can 5L (₹960), Extra Light Olive 2L (₹1903) | **same 2** | **NONE** |
| 560005 Bengaluru | ben_172_wh_hl_01 | Canola 1L (₹255) | **Canola 1L only** | **NONE** |

**Targeted search surfaced ZERO additional in-stock SKUs at either store.** This is the exact
opposite of zepto, where a targeted variant lookup revealed the hidden ₹469 listing. At 110095 a
specific `q=jivo mineral water` returns **0 Jivo** and `q=jivo canola oil` returns 0 canola — the
store genuinely does not carry them, even when asked for by name.

## Pagination ruled out (again, directly)
Every fetch returned the FULL result set in page 1 — total 30–35 cards, of which 1–2 are Jivo;
no `nextUrl`/`hasMore`/`totalPages`. The only count keys are `maxCardCount`/`resultCount`
(layout hints), not pagination cursors. Nothing is being dropped off a later page.

## The data is LIVE, not stale (bonus proof)
560005 Canola 1L was recorded `in_stock=0` in this morning's merged result.json but the live
probe now shows it **IN_STOCK ₹255**; 110095 caught 4 SKUs this morning vs 2 in-stock right now.
That is genuine **intraday dark-store stock fluctuation** (items sell out / restock through the
day), captured correctly each run — not a capture defect. It self-corrects at the next sweep, so
**no merge is warranted** (merging would just freeze a mid-day snapshot).

## PDP-by-pid path: deliberately NOT used (and why)
I first tried fetching each SKU's PDP by pid at the target store (the literal zepto "get_page"
move). The fkm BFF returns the **national marketplace** product page for a `PRODUCT_PAGE` fetch
(title: "…Price in India – Buy … online at Flipkart.com"), which carries no hyperlocal per-store
stock — so it can't confirm/deny store availability. The hyperlocal stock lives only in the
BROWSE_PAGE/search surface, which is exactly what the scraper already uses. Targeted search is
therefore the correct discriminator, and it says: complete.

## MUSTARD 4L (EDOHAUNQSDFDYPFC) note — not a capture gap
Mapped in sku_map but absent from every fkm pincode. Its PDP `itm` id is identical to MUSTARD 5L
(itmbc19c03fa6ee9) → a duplicate/delisted pid, not a live SKU any store stocks. Not surfaced by
even a targeted `q=jivo mustard oil`. This is a national-catalog mapping artifact, not an fkm
under-capture.

## Decision
- **Scraper: UNCHANGED.** `node --check` clean (not touched). result.json contract identical.
- **No pincode merged.** The probes wrote to /tmp only; production result.json never opened for write.
- **Owner answer:** unlike zepto, fkm is **genuinely thin** — each Flipkart Minutes dark store
  stocks only a small, fixed subset of Jivo's range, and our `q=jivo` capture gets all of it.
  The n/s wall is the truth of the dark-store network, not a missed listing. Re-confirmed live
  on 2026-06-09: SKU X = Mustard 1L / Canola 1L / Mineral Water genuinely **not at** store
  del_193 / ben_172 right now (targeted search returns them with 0 in-stock hits).

_Probe scripts (read-only, /tmp output): /tmp/fkm_probe3.js (PDP — inconclusive surface),_
_/tmp/fkm_probe4.js (targeted-search completeness — decisive). Raw: /tmp/fkm_probe4.out.json._
