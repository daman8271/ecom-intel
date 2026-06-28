# Jivo Availability Deep-Dive — Hyderabad / Chennai / Ahmedabad
**Date:** 2026-06-27 · **Source:** licensed QuickCommerce API (same key + endpoint as the daily BigBasket pincode cron) · one-off live pull, 2 pincodes per city, query = "jivo".

## TL;DR
- **Zepto is the ONLY platform meaningfully carrying Jivo in these 3 cities.** Strong in Hyderabad, decent in Chennai, almost empty in Ahmedabad (1 SKU).
- **BigBasket** (the only platform we track daily by pincode) carries Jivo in **Hyderabad only**; it is serviceable in Chennai & Ahmedabad but lists **zero** Jivo there.
- **Blinkit & Swiggy Instamart: zero Jivo** in all three cities (verified — search returns competitor oils, no Jivo brand).
- **None of these 3 cities is in the daily pincode panel** — that panel is a hand-curated 92-pincode / 12-city list that simply never included them.

## Live results (in-stock SKU count)
| City (pincodes) | BigBasket | Zepto | Blinkit | Swiggy IM |
|---|---|---|---|---|
| **Hyderabad** (Gachibowli 500032 / Banjara Hills 500034) | Banjara Hills **13** (11 in stock); Gachibowli **0** (no store mapped) | **14 / 11** (all in stock) | 0 (15 competitor oils) | no data |
| **Chennai** (Anna Nagar 600040 / Velachery 600042) | **0** (serviceable, 11–13 results, none Jivo) | **8 / 7** (all in stock) | 0 (15 competitor oils) | no data |
| **Ahmedabad** (Bodakdev 380054 / Navrangpura 380009) | **0** (serviceable, 14 results, none Jivo) | **1 / 1** (Groundnut 200 ml @ ₹49 only) | 0 (15 competitor oils) | no data |

### Notes
- **Hyderabad** is the only one of the three with healthy multi-platform Jivo presence (Zepto + BigBasket). Within the city, BigBasket is patchy by store (Banjara Hills served, Gachibowli returned nothing).
- **Chennai** depends entirely on Zepto (7–8 SKUs). BigBasket carries no Jivo despite serving the city.
- **Ahmedabad** is the weakest: only Zepto, only 1 SKU (Groundnut 200 ml). Effectively a distribution white-space for Jivo edible oils.
- **Swiggy Instamart** returns 0 results from our datacenter IP for all pincodes (known WAF/coverage limit) — treat as "unknown", not confirmed absent.
- Blinkit zeros are confirmed real (brand filter works; it found 13 Jivo in Hyderabad). The 15 results per Blinkit query are substitutes (Borges, Figaro, Del Monte, Oleev, Fortune…).

## Why this isn't tracked daily / isn't in the cron
1. **The daily pincode job exists, but its city list excludes these 3.** `platforms/bigbasket/run_pincode.sh` runs every day at **08:00** against `pincodes_jivo.json` = **92 pincodes across 12 cities**: Delhi(28), Mumbai(18), Pune(16), Gurgaon(6), Kolkata(6), Bengaluru(4), Chandigarh(4), Mysuru(3), Ghaziabad(2), Ludhiana(2), Noida(2), Faridabad(1). Hyderabad, Chennai, Ahmedabad were never added.
2. **Only BigBasket has per-pincode tracking at all.** Every other platform (Zepto, Blinkit, Amazon, Flipkart…) runs as a **national** scrape — one snapshot per platform, no city granularity — because their pricing is largely national and per-pincode multiplies cost/runtime. So even for in-panel cities there's no daily Zepto-by-city data.
3. **Scope was deliberately locked.** The pincode/price-match panel was frozen at the existing ~92-pincode / ~96–114-SKU master ("stick to the existing system"). Adding cities = more paid QC credits/day + a bigger emailed report.
4. **The capability is recent.** The pincode pull only became a daily cron after switching from the (classifier-blocked) stealth scraper to the **licensed** QuickCommerce API. It hasn't been expanded to more cities since.

**Bottom line:** it's a scope/curation gap, not a technical block. This entire 3-city pull took ~30s and ~37 QC credits (1118 remaining). Adding 6 pincodes (2/city) to the daily panel would cost ~6 extra credits/day and land these cities in the 08:00 report automatically.

## Other data source unavailable right now
The first-party JIVO API (`ecom.jivo.in`, via `jivo-ecom-pp-cli`) — which holds Jivo's own sell-through/listing analytics and may have city-level data — is returning **HTTP 401 (token expired, ~24h life)**. Refreshing it needs an interactive `auth login` with the owner's password (not stored on disk, never hardcoded). Worth a re-login if first-party city data is wanted.
