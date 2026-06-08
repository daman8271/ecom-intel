# W2 — CODE/SURFACE AUDIT: can amazon-now structurally copy amazon-core prices?

**Date:** 2026-06-08 · **Scope:** read-only code/surface audit · **Author:** W2

## VERDICT: **NO** — amazon-now cannot structurally copy amazon-core (marketplace) prices.

Every published price in `amazon-now/result.json` is extracted fresh from the genuine
Amazon Now storefront (`almBrandId=ctnow`) HTML response, gated behind a Now-only badge +
Now-branded-page filter. There is **no code path** by which a marketplace `/dp` price,
`amazon/result.json`, `amazon/products.json` price, or any shared cache reaches a Now row.
The one file shared with amazon-core supplies **name/category labels only, never price**.

---

## 1. The surfaces are different (endpoint diff)

**amazon-now (live, `scrape.ctnow.js`)** hits the genuine Now storefront search:
```js
// scrape.ctnow.js:146
const url = '/s?k=' + encodeURIComponent(query) + '&almBrandId=ctnow' + (pageNo > 1 ? '&page=' + pageNo : '');
const r = await fetch(url, { headers: { accept: 'text/html' } });   // :147
```
→ `https://www.amazon.in/s?k=jivo&almBrandId=ctnow` — the `alm`/ctnow backend (sibling of
Amazon Fresh's `i=freshstore`), driven on its **own dedicated logged-in account**
(`secrets/amazon-now.storageState.json`, `scrape.ctnow.js:39`) with a per-pincode GLOW
address-change POST (`scrape.ctnow.js:141-144`).

**amazon-core (`amazon/scrape.js`)** hits the guest marketplace product page:
```js
// amazon/scrape.js:77
const url = `https://www.amazon.in/dp/${asin}`;
resp = await page.goto(url, ...);   // :80  (NO login, NO location)
```
→ `https://www.amazon.in/dp/<asin>` — national guest pricing, `city="All India"`
(`amazon/scrape.js:312`).

Different host path, different surface, different auth context. They never query the same URL.

## 2. Each reads its PRICE from its OWN response (price-extraction proof)

**Now** parses the price out of the ctnow search-card it just fetched — nothing else:
```js
// scrape.ctnow.js:161  (inside the cards.map over the ctnow HTML doc)
price: clean(c.querySelector('.a-price[data-a-color="base"] .a-offscreen, .a-price .a-offscreen')),
mrp:   clean(c.querySelector('[data-a-strike="true"] .a-offscreen')),
```
That `card.price` is the ONLY price source for a row:
```js
// scrape.ctnow.js:182-184  (toRow)
const sale = numPrice(card.price);
let mrp = numPrice(card.mrp);
```
`toRow` builds `sale`, `mrp`, `discount_pct`, `per_litre` purely from `card.price`/`card.mrp`.
**There is no fallback to a marketplace price when Now is missing** — a missing card is simply
not iterated, so it produces no row (not a borrowed price).

**Core** independently parses `/dp` buy-box DOM (`amazon/scrape.js:125-165`,
`#corePriceDisplay…/.priceToPay/.a-offscreen`). Wholly separate extraction.

**No cross-reads.** `scrape.ctnow.js` opens only its own `pincodes.json`, `secrets/…`, and a
(non-existent) local `products.json` (see §3). It never reads `amazon/result.json`,
`amazon/products.json`, or any shared cache — grep for `amazon/result|amazon/products|../amazon`
in `scrape.ctnow.js` returns nothing.

## 3. The only shared input is a label file — NO price flows through it

`amazon-now/products.json` **does not exist** (`ls` confirms), so in `scrape.ctnow.js:52-56`
the try/catch leaves `PRODUCTS = {}`. `PRODUCTS[asin]` is only ever consulted for *name / pack /
category fallback* (`scrape.ctnow.js:180,183,199`) — never price.

`build_excel.py` DOES read the core catalog:
```python
# build_excel.py:27
for cat_path in ('../amazon/products.json', 'products.json'):
```
But `CATALOG` is used **only to enumerate the 314-ASIN universe and supply name/category** for
the Catalog-Coverage sheet (`build_excel.py:42-50, 279-284`). Every price displayed comes from
the scraped Now rows, not the catalog:
```python
# build_excel.py:282-285
rs = now_by_asin.get(asin, [])                       # rs = scraped Now rows for this ASIN
sales = [x['sale'] for x in rs if x.get('sale') is not None]
ws.append([asin, p.get('name')…, p.get('category')…, st, (min(sales) if sales else None)])
```
`CATALOG[asin].get('price')` is **never** read. The shared file is a name/category lookup,
nothing more. → A common ASIN *seed* exists, but prices are fetched fresh from the Now surface,
exactly as the task allows.

## 4. The Now-only GATE exists and is enforced (marketplace-bleed dropped)

Two layers drop any non-Now (marketplace/Fresh) row:

**Per-card instant-Now gate** — a card is kept only if it carries an *instant minute* tier:
```js
// scrape.ctnow.js:109-111
function isInstantNow(card) { return nowTier(card.badge, card.deliv) === '10 min'; }
// scrape.ctnow.js:269  (inside the keep loop)
if (!card.isJivo || !isInstantNow(card)) continue;   // scheduled tomorrow/today/overnight = Fresh → dropped
```
The badge itself must be the blue Now chip with non-empty text
(`.dex-text-slanted-blue-highlight`, `scrape.ctnow.js:159-165`).

**Per-pincode Now-branded-page gate** — rows are only collected when the page is genuinely
Amazon-Now-branded AND the GLOW location resolved:
```js
// scrape.ctnow.js:258
const nowPage = res.amazonNowPage;            // /amazon\s*now/i.test(html)  (:173)
// scrape.ctnow.js:263
if (matched && nowPage) { …collect instant-Now Jivo cards… }
// scrape.ctnow.js:285
const serviceable = matched && nowPage && rows.length > 0;
```
So a pincode that renders only scheduled (Fresh) chips, or a non-Now city, yields **0 rows** —
it can never inherit a marketplace price. This is the exact fix for the old bug.

## 5. Old surface (`scrape.js`, i=nowstore) is FROZEN and unused

- **Old bug (ROOTCAUSE-AmazonNow-2026-06-01.md):** the feed scraped `i=nowstore`
  (`scrape.js:150` → `/s?k=jivo&i=nowstore`), the legacy Prime-Now/**marketplace** SEARCH —
  0 minute-ETAs, ~8% catalog, card prices off by up to ~17%, and a loose `isNowSlot`
  (`scrape.js:108`) that waved through "Tomorrow" windows as "Now". That published marketplace
  data labelled as Now.
- **v2 fix:** rebuilt on `almBrandId=ctnow` with its own account + the instant-minute /
  Now-branded-page gates above (commits `66dbfc06`, `9911c2b8`, `33967301`).
- **Frozen & unused:** `run.sh:16-17` selects the scraper —
  `SCRAPER="scrape.js"; [ "$P" = "amazon-now" ] && SCRAPER="scrape.ctnow.js"` — so run.sh runs
  **scrape.ctnow.js** for amazon-now. The old `scrape.js` self-declares frozen
  (`scrape.js:16-17`, commit `1f0ce447` "freeze i=nowstore surface") and is on no execution path.

## 6. Git history — no regression reintroducing marketplace bleed

`git log` over `scrape.ctnow.js`/`scrape.js`: the trajectory only *tightens* the gate
(`ae263663` never count marketplace fallback → `1f0ce447` freeze i=nowstore → `66dbfc06` ctnow
rebuild → `9911c2b8` gate on amazon_now_page + instant tier → `33967301` finalize/tighten
serviceable). No commit re-adds a marketplace price source or loosens the gate.

---

## Bottom line
- **Endpoint:** Now = `/s?k=jivo&almBrandId=ctnow` (logged-in, per-pincode); Core = `/dp/<asin>`
  (guest, national). Disjoint.
- **Price:** Now's `sale`/`mrp` come solely from its own ctnow card's `.a-offscreen`
  (`scrape.ctnow.js:161,182`). No read of any core price, no missing-Now fallback.
- **Shared file:** only `../amazon/products.json`, used for name/category labels in the Excel —
  never price.
- **Gate:** instant-minute tier + Amazon-Now-branded page enforced
  (`scrape.ctnow.js:269,263,285`); non-Now → 0 rows.

**Can amazon-now copy core prices? NO.** (Caveat: this is a *code/surface* proof that no copy
path exists; the *empirical* price-divergence/time-series proof is W1's, the live ctnow probe
is W3's.)
