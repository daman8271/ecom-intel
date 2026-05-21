# SKILL: scrape Flipkart marketplace — STATUS: WORKING (datacenter IP)

Flipkart's main marketplace is **scrapable from the VPS datacenter IP** — HTTP
200, no captcha, **no login needed**.

## The rule: scrape ONLY Jivo's official catalogue (no "search jivo" grab-bag)
The earlier version searched `q=jivo` and kept every card containing the string
"jivo" + a ₹ price. That pulled in **JIVOTTAM** (a different brand — "jivo" is a
substring), random combo listings, and other sellers' noise. **Do not do that.**

Jivo's real Flipkart catalogue is defined in **`skus.master.tsv`** — one row per
SKU, pasted from Jivo's internal sheet (18 cols). The column **`FORMAT SKU Code`
is the Flipkart FSN/PID** (16-char, e.g. `EDOFTX47SWWQPRVS`; the prefix encodes
the Flipkart analytics category: `EDO`=edible oil, `GHE`=ghee, `TEA`=tea,
`HNY`=honey, `RIC`=rice, `DAJ`=drinks, `EDS`=seeds, `SCM`=spices, `QWR`=Shopsy…).
We scrape **exactly these SKUs and nothing else.** To add/remove SKUs, edit the
TSV — the scraper reads it directly (dedupes on FSN, ~268 unique today).

## Procedure (direct per-SKU lookup)
1. For each master FSN: `goto https://www.flipkart.com/x/p/itme?pid=<FSN>`.
   The `pid` resolves to that exact product — no search, no fuzzy matching.
2. Read the embedded **JSON-LD** (`script[type="application/ld+json"]`,
   schema.org/Product). It is stable across Flipkart's rotating obfuscated CSS
   classes — always prefer it:
   - `offers.price` → **sale price**
   - `offers.availability` (`schema.org/InStock` / `OutOfStock`) → **stock**
   - `description` (`"… for Rs.1650.0 online"`) → **MRP**
   - `sku` → the FSN — **verify it equals the requested pid** (`sku_mismatch`)
   - `name`, `brand.name`, `category`, `aggregateRating`
3. **DOM fallback** for variant listings whose JSON-LD has no `offers`: the first
   leaf node whose whole text is `^₹[\d,]+$` (document order = buy-box before
   cross-sell carousels) is the sale; a higher one nearby is the MRP; first
   `N% off` in body text is the discount. MRP/sale/discount are kept consistent
   (reconstruct MRP from sale + % off when no explicit MRP).

## Marketplace pricing is NATIONAL
A listing's price is identical regardless of pincode (only delivery date varies).
So we do NOT loop pincodes — every row is tagged `city="All India"`. `pincodes.json`
is intentionally unused. Output stays Blinkit-compatible (`build_excel.py`), and
each row also carries rich identity (`fsn, item, sap_code, brand, category,
sub_category, is_oil, fk_name, availability, rating, price_src`).

## Quirks & tuning
- **Throttling:** under high concurrency Flipkart serves a transient
  "Something went wrong … E002 Retry" interstitial. The scraper detects it and
  retries (3 tries, backoff). Default `FK_CONCURRENCY=3` keeps it rare.
  `FK_LIMIT=N` scrapes only the first N SKUs (testing).
- **Shopsy (`QWR…`) listings** often render NO price on flipkart.com (Shopsy-app
  exclusive) → recorded as no-price / out-of-stock. That is correct, not a bug.
- Full run ≈ 268 pages, a few minutes. ~80%+ priced; the rest are genuinely
  price-less/OOS on the marketplace.
- Live in `setup_cron.sh` + `healthcheck.sh`. City matrices in the Excel show a
  single "All India" column by design.
