---
type: app-dashboard
endpoint_key: state-sales__2026-07
source: app-dashboard
month: 2026-07
platform: ""
tags:
  - type/app-dashboard
  - source/app-dashboard
  - month/2026-07
---

# App dashboard — `state-sales__2026-07`

Up: [[dashboards-index]] · [[2026-07]]

> **source: app-dashboard `state-sales__2026-07`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "brands": [],
 "categories": [],
 "cities": [
  {
   "city": "Delhi",
   "value": 4271.0
  },
  {
   "city": "Mumbai",
   "value": 3883.0
  },
  {
   "city": "Hyderabad",
   "value": 3532.0
  },
  {
   "city": "Bangalore",
   "value": 2455.0
  },
  {
   "city": "Bengaluru",
   "value": 2102.0
  },
  {
   "city": "Chennai",
   "value": 2052.0
  },
  {
   "city": "Gurgaon",
   "value": 1098.0
  },
  {
   "city": "Chandigarh",
   "value": 868.0
  },
  {
   "city": "Kolkata",
   "value": 829.0
  },
  {
   "city": "Noida",
   "value": 719.0
  }
 ],
 "errors": [
  {
   "error": "column a.state does not exist\nLINE 2:             SELECT COALESCE(a.state::text, '') AS state,\n                                    ^",
   "source": "amazon_sec_state"
  }
 ],
 "filter_options": {
  "brands": [
   "JIVO",
   "SANO"
  ],
  "categories": [
   "BLENDED",
   "CANOLA",
   "CASSEROLE",
   "COCONUT",
   "COFFEE",
   "COTTON SEED",
   "CRYPTO",
   "DRINKS",
   "ELEGANCE",
   "FERRERO",
   "FIRST PRESSED",
   "FLIPPRO",
   "GHEE",
   "GIFT PACK",
   "GROUNDNUT",
   "HONEY",
   "LUNCH BOX",
   "MAKKI ATTA",
   "MUSTARD",
   "OLIVE",
   "RICE",
   "RICE BRAN",
   "ROSEMARY LEAVES",
   "SEEDS",
   "SESAME OIL",
   "SLICED OLIVE",
   "SOYABEAN",
   "SPICES",
   "SUNFLOWER",
   "TEA"
  ],
  "sub_categories": [
   {
    "category": "BLENDED",
    "sub_category": "GOLD"
   },
   {
    "category": "BLENDED",
    "sub_category": "RICE BRAN"
   },
   {
    "category": "BLENDED",
    "sub_category": "SO OLIVE"
   },
   {
    "category": "CANOLA",
    "sub_category": "CANOLA"
   },
   {
    "category": "CASSEROLE",
    "sub_category": "CASSEROLE"
   },
   {
    "category": "COCONUT",
    "sub_category": "COCONUT"
   },
   {
    "category": "COFFEE",
    "sub_category": "COFFEE"
   },
   {
    "category": "COTTON SEED",
    "sub_category": "COTTON SEED"
   },
   {
    "category": "CRYPTO",
    "sub_category": "CRYPTO"
   },
   {
    "category": "DRINKS",
    "sub_category": "APPLE"
   },
   {
    "category": "DRINKS",
    "sub_category": "APPLE SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "BLUEBERRY"
   },
   {
    "category": "DRINKS",
    "sub_category": "COLA"
   },
   {
    "category": "DRINKS",
    "sub_category": "ENEGRY DRINK"
   },
   {
    "category": "DRINKS",
    "sub_category": "ENERGY DRINK SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "GIGNGER ALE"
   },
   {
    "category": "DRINKS",
    "sub_category": "GINGER"
   },
   {
    "category": "DRINKS",
    "sub_category": "GINGER ALE SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "JEERA"
   },
   {
    "category": "DRINKS",
    "sub_category": "JEERA SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "LEMON"
   },
   {
    "category": "DRINKS",
    "sub_category": "MANGO"
   },
   {
    "category": "DRINKS",
    "sub_category": "MANGO SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "MINERAL WATER"
   },
   {
    "category": "DRINKS",
    "sub_category": "MOJITO"
   },
   {
    "category": "DRINKS",
    "sub_category": "MOJITO SF"
   },
   {
    "category": "DRINKS",
    "sub_category": "ORANGE"
   },
   {
    "category": "DRINKS",
    "sub_category": "PUNJABI JEERA"
   },
   {
    "category": "DRINKS",
    "sub_category": "ROSE"
   },
   {
    "category": "DRINKS",
    "sub_category": "SHIKANJI"
   },
   {
    "category": "DRINKS",
    "sub_category": "SODA"
   },
   {
    "category": "DRINKS",
    "sub_category": "TONIC WATER"
   },
   {
    "category": "ELEGANCE",
    "sub_category": "ELEGANCE"
   },
   {
    "category": "FERRERO",
    "sub_category": "FERRERO"
   },
   {
    "category": "FIRST PRESSED",
    "sub_category": "FIRST PRESSED MUSTARD"
   },
   {
    "category": "FIRST PRESSED",
    "sub_category": "FIRST PRESSED SUNFLOWER"
   },
   {
    "category": "FLIPPRO",
    "sub_category": "FLIPPRO"
   },
   {
    "category": "GHEE",
    "sub_category": "A2 GHEE"
   },
   {
    "category": "GHEE",
    "sub_category": "DESI GHEE"
   },
   {
    "category": "GIFT PACK",
    "sub_category": "DRY FRUITS"
   },
   {
    "category": "GROUNDNUT",
    "sub_category": "GROUNDNUT"
   },
   {
    "category": "HONEY",
    "sub_category": "HONEY"
   },
   {
    "category": "HONEY",
    "sub_category": "NATURAL HONEY"
   },
   {
    "category": "LUNCH BOX",
    "sub_category": "LUNCH BOX"
   },
   {
    "category": "MAKKI ATTA",
    "sub_category": "MAKKI ATTA"
   },
   {
    "category": "MUSTARD",
    "sub_category": "MUSTARD KACCHI GHANI"
   },
   {
    "category": "MUSTARD",
    "sub_category": "MUSTARD KACHI GHANI"
   },
   {
    "category": "MUSTARD",
    "sub_category": "YELLOW MUSTARD"
   },
   {
    "category": "OLIVE",
    "sub_category": "CLASSIC"
   },
   {
    "category": "OLIVE",
    "sub_category": "EXTRA LIGHT"
   },
   {
    "category": "OLIVE",
    "sub_category": "EXTRA VIRGIN"
   },
   {
    "category": "OLIVE",
    "sub_category": "JIVO POMACE"
   },
   {
    "category": "OLIVE",
    "sub_category": "POMACE"
   },
   {
    "category": "OLIVE",
    "sub_category": "PURE OLIVE"
   },
   {
    "category": "OLIVE",
    "sub_category": "SANO POMACE"
   },
   {
    "category": "RICE",
    "sub_category": "BASMATI"
   },
   {
    "category": "RICE",
    "sub_category": "RICE"
   },
   {
    "category": "RICE BRAN",
    "sub_category": "RICE BRAN"
   },
   {
    "category": "ROSEMARY LEAVES",
    "sub_category": "ROSEMARY LEAVES"
   },
   {
    "category": "SEEDS",
    "sub_category": "ALL SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "BASIL SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "CHIA SEED"
   },
   {
    "category": "SEEDS",
    "sub_category": "CHIA SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "FLAX SEED"
   },
   {
    "category": "SEEDS",
    "sub_category": "FLAX SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "PUMPKIN SEED"
   },
   {
    "category": "SEEDS",
    "sub_category": "PUMPKIN SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "QUINOA SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "SEEDS"
   },
   {
    "category": "SEEDS",
    "sub_category": "SUNFLOWER SEEDS"
   },
   {
    "category": "SESAME OIL",
    "sub_category": "SESAME OIL"
   },
   {
    "category": "SLICED OLIVE",
    "sub_category": "BLACK OLIVE"
   },
   {
    "category": "SOYABEAN",
    "sub_category": "SOYABEAN"
   },
   {
    "category": "SPICES",
    "sub_category": "BLACK CARDAMOM"
   },
   {
    "category": "SPICES",
    "sub_category": "BLACK PEPPER"
   },
   {
    "category": "SPICES",
    "sub_category": "CINNAMON"
   },
   {
    "category": "SPICES",
    "sub_category": "CLOVE"
   },
   {
    "category": "SPICES",
    "sub_category": "CUMIN"
   },
   {
    "category": "SPICES",
    "sub_category": "CUMIN SEEDS"
   },
   {
    "category": "SPICES",
    "sub_category": "GREEN CARDAMOM"
   },
   {
    "category": "SPICES",
    "sub_category": "JIVO CLOVE"
   },
   {
    "category": "SPICES",
    "sub_category": "SAFFRON"
   },
   {
    "category": "SUNFLOWER",
    "sub_category": "SUNFLOWER"
   },
   {
    "category": "TEA",
    "sub_category": "TEA"
   }
  ]
 },
 "mapped_units": 33345.0,
 "mapped_value": 33345.0,
 "metric": "units",
 "metric_label": "Units sold",
 "metric_unit": "units",
 "mode": "single",
 "month": 7,
 "pct_mapped": 100.0,
 "platform": null,
 "states": [
  {
   "by_platform": {
    "BIG BASKET": 82.0,
    "BLINKIT": 295.0,
    "SWIGGY": 2612.0,
    "ZEPTO": 1980.0
   },
   "state": "KARNATAKA",
   "units": 4969.0,
   "value": 4969.0
  },
  {
   "by_platform": {
    "BIG BASKET": 35.0,
    "BLINKIT": 499.0,
    "SWIGGY": 2491.0,
    "ZEPTO": 1918.0
   },
   "state": "MAHARASHTRA",
   "units": 4943.0,
   "value": 4943.0
  },
  {
   "by_platform": {
    "BLINKIT": 862.0,
    "SWIGGY": 2059.0,
    "ZEPTO": 1350.0
   },
   "state": "DELHI",
   "units": 4271.0,
   "value": 4271.0
  },
  {
   "by_platform": {
    "BIG BASKET": 192.0,
    "SWIGGY": 2088.0,
    "ZEPTO": 1411.0
   },
   "state": "TELANGANA",
   "units": 3691.0,
   "value": 3691.0
  },
  {
   "by_platform": {
    "BLINKIT": 2082.0,
    "SWIGGY": 453.0,
    "ZEPTO": 147.0
   },
   "state": "PUNJAB",
   "units": 2682.0,
   "value": 2682.0
  },
  {
   "by_platform": {
    "SWIGGY": 1570.0,
    "ZEPTO": 994.0
   },
   "state": "TAMIL NADU",
   "units": 2564.0,
   "value": 2564.0
  },
  {
   "by_platform": {
    "BIG BASKET": 464.0,
    "BLINKIT": 707.0,
    "SWIGGY": 611.0,
    "ZEPTO": 675.0
   },
   "state": "HARYANA",
   "units": 2457.0,
   "value": 2457.0
  },
  {
   "by_platform": {
    "BIG BASKET": 172.0,
    "BLINKIT": 364.0,
    "SWIGGY": 667.0,
    "ZEPTO": 806.0
   },
   "state": "UTTAR PRADESH",
   "units": 2009.0,
   "value": 2009.0
  },
  {
   "by_platform": {
    "BIG BASKET": 145.0,
    "BLINKIT": 482.0,
    "SWIGGY": 444.0,
    "ZEPTO": 26.0
   },
   "state": "CHANDIGARH",
   "units": 1097.0,
   "value": 1097.0
  },
  {
   "by_platform": {
    "BIG BASKET": 21.0,
    "BLINKIT": 26.0,
    "SWIGGY": 764.0,
    "ZEPTO": 53.0
   },
   "state": "WEST BENGAL",
   "units": 864.0,
   "value": 864.0
  },
  {
   "by_platform": {
    "BIG BASKET": 22.0,
    "SWIGGY": 593.0,
    "ZEPTO": 51.0
   },
   "state": "ANDHRA PRADESH",
   "units": 666.0,
   "value": 666.0
  },
  {
   "by_platform": {
    "BLINKIT": 26.0,
    "SWIGGY": 465.0,
    "ZEPTO": 82.0
   },
   "state": "RAJASTHAN",
   "units": 573.0,
   "value": 573.0
  },
  {
   "by_platform": {
    "SWIGGY": 326.0,
    "ZEPTO": 128.0
   },
   "state": "GUJARAT",
   "units": 454.0,
   "value": 454.0
  },
  {
   "by_platform": {
    "SWIGGY": 373.0,
    "ZEPTO": 21.0
   },
   "state": "KERALA",
   "units": 394.0,
   "value": 394.0
  },
  {
   "by_platform": {
    "BIG BASKET": 7.0,
    "BLINKIT": 100.0,
    "SWIGGY": 214.0,
    "ZEPTO": 65.0
   },
   "state": "UTTARAKHAND",
   "units": 386.0,
   "value": 386.0
  },
  {
   "by_platform": {
    "BLINKIT": 1.0,
    "SWIGGY": 232.0,
    "ZEPTO": 37.0
   },
   "state": "MADHYA PRADESH",
   "units": 270.0,
   "value": 270.0
  },
  {
   "by_platform": {
    "BLINKIT": 254.0
   },
   "state": "JAMMU AND KASHMIR",
   "units": 254.0,
   "value": 254.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2.0,
    "SWIGGY": 200.0
   },
   "state": "ODISHA",
   "units": 202.0,
   "value": 202.0
  },
  {
   "by_platform": {
    "BLINKIT": 200.0
   },
   "state": "HIMACHAL PRADESH",
   "units": 200.0,
   "value": 200.0
  },
  {
   "by_platform": {
    "BLINKIT": 21.0,
    "SWIGGY": 144.0
   },
   "state": "GOA",
   "units": 165.0,
   "value": 165.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1.0,
    "SWIGGY": 115.0
   },
   "state": "BIHAR",
   "units": 116.0,
   "value": 116.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2.0,
    "SWIGGY": 83.0
   },
   "state": "JHARKHAND",
   "units": 85.0,
   "value": 85.0
  },
  {
   "by_platform": {
    "BIG BASKET": 3.0,
    "SWIGGY": 16.0
   },
   "state": "CHHATTISGARH",
   "units": 19.0,
   "value": 19.0
  },
  {
   "by_platform": {
    "ZEPTO": 10.0
   },
   "state": "PUDUCHERRY",
   "units": 10.0,
   "value": 10.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2.0,
    "SWIGGY": 2.0
   },
   "state": "ASSAM",
   "units": 4.0,
   "value": 4.0
  }
 ],
 "sub_categories": [],
 "total_units": 33358.0,
 "total_value": 33358.0,
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*
