# JIVO 25-City Per-Pincode Coverage — Status (2026-07-01)

> Physically scraped per-pincode census across all **1,885 pincodes** of the 25 tier-1 cities,
> on the 5 pincode-wise platforms. Source: `data/coverage/ledger.csv`. **No extrapolation.**

## 1. The pincode universe
- **25 tier-1 cities → 1,885 distinct pincodes** (India Post All-India directory).
- This is the honest denominator for everything below.

## 2. Coverage per platform — serviceable / not-serviceable / Jivo
Each platform was checked at **every one of the 1,885 pincodes**.

| Platform | Pincodes checked | Serviceable (delivers) | NOT serviceable | **Jivo on sale** | Delivers-but-no-Jivo gap | Daily scrape set |
|---|--:|--:|--:|--:|--:|--:|
| **Amazon Fresh** | 1,885 | 973 | 912 | 881 | 92 | 881 |
| **Blinkit** | 1,885 | 902 | 983 | 486 | 416 | 486 |
| **Zepto** | 1,885 | 693 | 1,192 | 693 | 0 | 693 |
| **Flipkart Minutes** | 1,885 | 340 | 1,545 | 340 | 0 | 340 |
| **Amazon Now** | 1,885 | 132 | 1,753 | 132 | 0 | 132 |
| **Combined (any platform)** | 1,885 | **1,173 (62%)** | 712 | **1,071 (57%)** | — | 2,532 / day |

**Read it as:** of the 1,885 city pincodes, **1,173 are reachable** by at least one platform and **1,071 have Jivo on sale** today. (Was 234 / 12% on the old anchor model.)

## 3. What the daily cron scrapes (the Jivo-priced subsets)
The daily run tracks only the pincodes where Jivo is actually sold (price-tracking set):

| Platform | Daily pincodes | Grain |
|---|--:|---|
| Amazon Fresh | 881 | per-pincode (in noon chain; ~5h, chain starts 01:19) |
| Zepto | 693 | per-pincode |
| Blinkit | 486 | per-pincode |
| Flipkart Minutes | 340 | per-pincode |
| Amazon Now | 132 | per-pincode |
| BigBasket | 227 | national price / pincode serviceability |
| Amazon.in / Flipkart.com | 40 each | national 40-pin sample |
| Swiggy Instamart | 0 | **NOT RUNNING** (VPS IP WAF-blocked) |

Reports land **12:00 noon** daily (deadline-aligned cron, fires 00:30).

## 4. Definitions
- **Serviceable** = the platform delivers to that pincode (`price_captured` + `serviceable_no_jivo`).
- **NOT serviceable** = the platform does not deliver there (`not_serviceable`).
- **Jivo on sale** = serviceable AND a Jivo product was priced (`price_captured`).
- **Gap** = serviceable − Jivo = delivers but carries no Jivo (distribution opportunity).

## 5. Honest limitations
- Numbers use the **core-district** definition of each city; greater-metro suburbs (Salt Lake→Kolkata, etc.) fall just outside — see the national-drop note in the run logs.
- Amazon exposes no `store_id`, so Amazon is measured by **pincodes**, not dark stores.
- Swiggy Instamart can't be scraped from the VPS datacenter IP (WAF). Per-pincode build is ready but unwired.
