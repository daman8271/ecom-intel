---
type: app-dashboard
endpoint_key: state-sales__2026-05
source: app-dashboard
month: 2026-05
platform: ""
tags:
  - type/app-dashboard
  - source/app-dashboard
  - month/2026-05
---

# App dashboard — `state-sales__2026-05`

Up: [[dashboards-index]] · [[2026-05]]

> **source: app-dashboard `state-sales__2026-05`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "brands": [],
 "categories": [],
 "cities": [
  {
   "city": "Delhi",
   "value": 45168.0
  },
  {
   "city": "Mumbai",
   "value": 30220.0
  },
  {
   "city": "Hyderabad",
   "value": 17441.0
  },
  {
   "city": "Bangalore",
   "value": 16505.0
  },
  {
   "city": "Bengaluru",
   "value": 13675.0
  },
  {
   "city": "Gurgaon",
   "value": 11394.0
  },
  {
   "city": "Pune",
   "value": 10702.0
  },
  {
   "city": "Chandigarh",
   "value": 9204.0
  },
  {
   "city": "Noida",
   "value": 8863.0
  },
  {
   "city": "Ghaziabad",
   "value": 8709.0
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
 "mapped_units": 279983.0,
 "mapped_value": 279983.0,
 "metric": "units",
 "metric_label": "Units sold",
 "metric_unit": "units",
 "mode": "single",
 "month": 5,
 "pct_mapped": 100.0,
 "platform": null,
 "states": [
  {
   "by_platform": {
    "BLINKIT": 11601.0,
    "FLIPKART": 1110.0,
    "SWIGGY": 10059.0,
    "ZEPTO": 23508.0
   },
   "state": "DELHI",
   "units": 46278.0,
   "value": 46278.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1455.0,
    "BLINKIT": 5223.0,
    "FLIPKART": 903.0,
    "SWIGGY": 20653.0,
    "ZEPTO": 16268.0
   },
   "state": "MAHARASHTRA",
   "units": 44502.0,
   "value": 44502.0
  },
  {
   "by_platform": {
    "BIG BASKET": 567.0,
    "BLINKIT": 3448.0,
    "FLIPKART": 572.0,
    "SWIGGY": 17432.0,
    "ZEPTO": 10779.0
   },
   "state": "KARNATAKA",
   "units": 32798.0,
   "value": 32798.0
  },
  {
   "by_platform": {
    "BLINKIT": 22459.0,
    "FLIPKART": 1043.0,
    "SWIGGY": 5144.0,
    "ZEPTO": 1597.0
   },
   "state": "PUNJAB",
   "units": 30243.0,
   "value": 30243.0
  },
  {
   "by_platform": {
    "BIG BASKET": 4221.0,
    "BLINKIT": 8476.0,
    "FLIPKART": 964.0,
    "SWIGGY": 5761.0,
    "ZEPTO": 10666.0
   },
   "state": "HARYANA",
   "units": 30088.0,
   "value": 30088.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1709.0,
    "BLINKIT": 5142.0,
    "FLIPKART": 1411.0,
    "SWIGGY": 5430.0,
    "ZEPTO": 11481.0
   },
   "state": "UTTAR PRADESH",
   "units": 25173.0,
   "value": 25173.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2251.0,
    "FLIPKART": 494.0,
    "SWIGGY": 11227.0,
    "ZEPTO": 4459.0
   },
   "state": "TELANGANA",
   "units": 18431.0,
   "value": 18431.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1109.0,
    "BLINKIT": 4193.0,
    "FLIPKART": 89.0,
    "SWIGGY": 5646.0,
    "ZEPTO": 181.0
   },
   "state": "CHANDIGARH",
   "units": 11218.0,
   "value": 11218.0
  },
  {
   "by_platform": {
    "BIG BASKET": 4.0,
    "BLINKIT": 5.0,
    "FLIPKART": 300.0,
    "SWIGGY": 6555.0,
    "ZEPTO": 1979.0
   },
   "state": "TAMIL NADU",
   "units": 8843.0,
   "value": 8843.0
  },
  {
   "by_platform": {
    "BIG BASKET": 194.0,
    "BLINKIT": 238.0,
    "FLIPKART": 1051.0,
    "SWIGGY": 2802.0
   },
   "state": "WEST BENGAL",
   "units": 4285.0,
   "value": 4285.0
  },
  {
   "by_platform": {
    "BLINKIT": 345.0,
    "FLIPKART": 322.0,
    "SWIGGY": 2969.0,
    "ZEPTO": 273.0
   },
   "state": "RAJASTHAN",
   "units": 3909.0,
   "value": 3909.0
  },
  {
   "by_platform": {
    "BIG BASKET": 40.0,
    "BLINKIT": 1120.0,
    "FLIPKART": 198.0,
    "SWIGGY": 1219.0,
    "ZEPTO": 575.0
   },
   "state": "UTTARAKHAND",
   "units": 3152.0,
   "value": 3152.0
  },
  {
   "by_platform": {
    "FLIPKART": 195.0,
    "SWIGGY": 2370.0,
    "ZEPTO": 526.0
   },
   "state": "GUJARAT",
   "units": 3091.0,
   "value": 3091.0
  },
  {
   "by_platform": {
    "BIG BASKET": 210.0,
    "BLINKIT": 11.0,
    "FLIPKART": 484.0,
    "SWIGGY": 1993.0,
    "ZEPTO": 32.0
   },
   "state": "ANDHRA PRADESH",
   "units": 2730.0,
   "value": 2730.0
  },
  {
   "by_platform": {
    "BLINKIT": 2458.0,
    "FLIPKART": 112.0
   },
   "state": "JAMMU AND KASHMIR",
   "units": 2570.0,
   "value": 2570.0
  },
  {
   "by_platform": {
    "BIG BASKET": 4.0,
    "FLIPKART": 235.0,
    "SWIGGY": 2149.0,
    "ZEPTO": 40.0
   },
   "state": "KERALA",
   "units": 2428.0,
   "value": 2428.0
  },
  {
   "by_platform": {
    "BLINKIT": 13.0,
    "FLIPKART": 458.0,
    "SWIGGY": 1524.0,
    "ZEPTO": 119.0
   },
   "state": "MADHYA PRADESH",
   "units": 2114.0,
   "value": 2114.0
  },
  {
   "by_platform": {
    "BIG BASKET": 21.0,
    "FLIPKART": 624.0,
    "SWIGGY": 1093.0
   },
   "state": "ODISHA",
   "units": 1738.0,
   "value": 1738.0
  },
  {
   "by_platform": {
    "BLINKIT": 1523.0,
    "FLIPKART": 114.0
   },
   "state": "HIMACHAL PRADESH",
   "units": 1637.0,
   "value": 1637.0
  },
  {
   "by_platform": {
    "BLINKIT": 61.0,
    "FLIPKART": 62.0,
    "SWIGGY": 1084.0
   },
   "state": "GOA",
   "units": 1207.0,
   "value": 1207.0
  },
  {
   "by_platform": {
    "BIG BASKET": 14.0,
    "FLIPKART": 455.0,
    "SWIGGY": 360.0
   },
   "state": "BIHAR",
   "units": 829.0,
   "value": 829.0
  },
  {
   "by_platform": {
    "BIG BASKET": 18.0,
    "FLIPKART": 605.0,
    "SWIGGY": 73.0
   },
   "state": "ASSAM",
   "units": 696.0,
   "value": 696.0
  },
  {
   "by_platform": {
    "BIG BASKET": 28.0,
    "BLINKIT": 1.0,
    "FLIPKART": 151.0,
    "SWIGGY": 423.0
   },
   "state": "CHHATTISGARH",
   "units": 603.0,
   "value": 603.0
  },
  {
   "by_platform": {
    "BIG BASKET": 25.0,
    "FLIPKART": 239.0,
    "SWIGGY": 320.0
   },
   "state": "JHARKHAND",
   "units": 584.0,
   "value": 584.0
  },
  {
   "by_platform": {
    "FLIPKART": 356.0
   },
   "state": "MIZORAM",
   "units": 356.0,
   "value": 356.0
  },
  {
   "by_platform": {
    "FLIPKART": 141.0
   },
   "state": "TRIPURA",
   "units": 141.0,
   "value": 141.0
  },
  {
   "by_platform": {
    "FLIPKART": 100.0
   },
   "state": "MANIPUR",
   "units": 100.0,
   "value": 100.0
  },
  {
   "by_platform": {
    "FLIPKART": 91.0
   },
   "state": "MEGHALAYA",
   "units": 91.0,
   "value": 91.0
  },
  {
   "by_platform": {
    "FLIPKART": 65.0
   },
   "state": "NAGALAND",
   "units": 65.0,
   "value": 65.0
  },
  {
   "by_platform": {
    "FLIPKART": 30.0
   },
   "state": "ARUNACHAL PRADESH",
   "units": 30.0,
   "value": 30.0
  },
  {
   "by_platform": {
    "FLIPKART": 7.0,
    "ZEPTO": 15.0
   },
   "state": "PUDUCHERRY",
   "units": 22.0,
   "value": 22.0
  },
  {
   "by_platform": {
    "FLIPKART": 20.0
   },
   "state": "SIKKIM",
   "units": 20.0,
   "value": 20.0
  },
  {
   "by_platform": {
    "FLIPKART": 10.0
   },
   "state": "DADRA AND NAGAR HAVELI AND DAMAN AND DIU",
   "units": 10.0,
   "value": 10.0
  },
  {
   "by_platform": {
    "FLIPKART": 1.0
   },
   "state": "LADAKH",
   "units": 1.0,
   "value": 1.0
  }
 ],
 "sub_categories": [],
 "total_units": 279992.0,
 "total_value": 279992.0,
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*
