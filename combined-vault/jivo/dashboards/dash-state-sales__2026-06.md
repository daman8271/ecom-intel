---
type: app-dashboard
endpoint_key: state-sales__2026-06
source: app-dashboard
month: 2026-06
platform: ""
tags:
  - type/app-dashboard
  - source/app-dashboard
  - month/2026-06
---

# App dashboard — `state-sales__2026-06`

Up: [[dashboards-index]] · [[2026-06]]

> **source: app-dashboard `state-sales__2026-06`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "brands": [],
 "categories": [],
 "cities": [
  {
   "city": "Delhi",
   "value": 46637.0
  },
  {
   "city": "Mumbai",
   "value": 41791.0
  },
  {
   "city": "Hyderabad",
   "value": 32490.0
  },
  {
   "city": "Bangalore",
   "value": 27739.0
  },
  {
   "city": "Bengaluru",
   "value": 23771.0
  },
  {
   "city": "Chennai",
   "value": 16629.0
  },
  {
   "city": "Pune",
   "value": 14851.0
  },
  {
   "city": "Gurgaon",
   "value": 11690.0
  },
  {
   "city": "Chandigarh",
   "value": 11344.0
  },
  {
   "city": "Noida",
   "value": 7828.0
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
 "mapped_units": 348104.0,
 "mapped_value": 348104.0,
 "metric": "units",
 "metric_label": "Units sold",
 "metric_unit": "units",
 "mode": "single",
 "month": 6,
 "pct_mapped": 100.0,
 "platform": null,
 "states": [
  {
   "by_platform": {
    "BIG BASKET": 1345.0,
    "BLINKIT": 5033.0,
    "SWIGGY": 28772.0,
    "ZEPTO": 25247.0
   },
   "state": "MAHARASHTRA",
   "units": 60397.0,
   "value": 60397.0
  },
  {
   "by_platform": {
    "BIG BASKET": 457.0,
    "BLINKIT": 3678.0,
    "SWIGGY": 29258.0,
    "ZEPTO": 21313.0
   },
   "state": "KARNATAKA",
   "units": 54706.0,
   "value": 54706.0
  },
  {
   "by_platform": {
    "BLINKIT": 10195.0,
    "SWIGGY": 16345.0,
    "ZEPTO": 20097.0
   },
   "state": "DELHI",
   "units": 46637.0,
   "value": 46637.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1684.0,
    "SWIGGY": 18625.0,
    "ZEPTO": 13064.0
   },
   "state": "TELANGANA",
   "units": 33373.0,
   "value": 33373.0
  },
  {
   "by_platform": {
    "BLINKIT": 23049.0,
    "SWIGGY": 4222.0,
    "ZEPTO": 1802.0
   },
   "state": "PUNJAB",
   "units": 29073.0,
   "value": 29073.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2949.0,
    "BLINKIT": 8215.0,
    "SWIGGY": 7302.0,
    "ZEPTO": 10110.0
   },
   "state": "HARYANA",
   "units": 28576.0,
   "value": 28576.0
  },
  {
   "by_platform": {
    "BIG BASKET": 1207.0,
    "BLINKIT": 4388.0,
    "SWIGGY": 7421.0,
    "ZEPTO": 9902.0
   },
   "state": "UTTAR PRADESH",
   "units": 22918.0,
   "value": 22918.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2.0,
    "BLINKIT": 2.0,
    "SWIGGY": 13040.0,
    "ZEPTO": 7700.0
   },
   "state": "TAMIL NADU",
   "units": 20744.0,
   "value": 20744.0
  },
  {
   "by_platform": {
    "BIG BASKET": 946.0,
    "BLINKIT": 4664.0,
    "SWIGGY": 7418.0,
    "ZEPTO": 223.0
   },
   "state": "CHANDIGARH",
   "units": 13251.0,
   "value": 13251.0
  },
  {
   "by_platform": {
    "BLINKIT": 405.0,
    "SWIGGY": 4229.0,
    "ZEPTO": 1367.0
   },
   "state": "RAJASTHAN",
   "units": 6001.0,
   "value": 6001.0
  },
  {
   "by_platform": {
    "BLINKIT": 7.0,
    "SWIGGY": 3448.0,
    "ZEPTO": 2351.0
   },
   "state": "GUJARAT",
   "units": 5806.0,
   "value": 5806.0
  },
  {
   "by_platform": {
    "BIG BASKET": 227.0,
    "BLINKIT": 28.0,
    "SWIGGY": 2979.0,
    "ZEPTO": 476.0
   },
   "state": "ANDHRA PRADESH",
   "units": 3710.0,
   "value": 3710.0
  },
  {
   "by_platform": {
    "BIG BASKET": 2.0,
    "SWIGGY": 3337.0,
    "ZEPTO": 292.0
   },
   "state": "KERALA",
   "units": 3631.0,
   "value": 3631.0
  },
  {
   "by_platform": {
    "BIG BASKET": 30.0,
    "BLINKIT": 1100.0,
    "SWIGGY": 1630.0,
    "ZEPTO": 730.0
   },
   "state": "UTTARAKHAND",
   "units": 3490.0,
   "value": 3490.0
  },
  {
   "by_platform": {
    "BIG BASKET": 195.0,
    "BLINKIT": 236.0,
    "SWIGGY": 2713.0,
    "ZEPTO": 54.0
   },
   "state": "WEST BENGAL",
   "units": 3198.0,
   "value": 3198.0
  },
  {
   "by_platform": {
    "BLINKIT": 2764.0
   },
   "state": "JAMMU AND KASHMIR",
   "units": 2764.0,
   "value": 2764.0
  },
  {
   "by_platform": {
    "BLINKIT": 18.0,
    "SWIGGY": 2137.0,
    "ZEPTO": 570.0
   },
   "state": "MADHYA PRADESH",
   "units": 2725.0,
   "value": 2725.0
  },
  {
   "by_platform": {
    "BLINKIT": 272.0,
    "SWIGGY": 2074.0
   },
   "state": "GOA",
   "units": 2346.0,
   "value": 2346.0
  },
  {
   "by_platform": {
    "BLINKIT": 1984.0
   },
   "state": "HIMACHAL PRADESH",
   "units": 1984.0,
   "value": 1984.0
  },
  {
   "by_platform": {
    "BIG BASKET": 14.0,
    "SWIGGY": 1062.0
   },
   "state": "ODISHA",
   "units": 1076.0,
   "value": 1076.0
  },
  {
   "by_platform": {
    "BIG BASKET": 34.0,
    "BLINKIT": 5.0,
    "SWIGGY": 560.0
   },
   "state": "CHHATTISGARH",
   "units": 599.0,
   "value": 599.0
  },
  {
   "by_platform": {
    "BIG BASKET": 14.0,
    "SWIGGY": 488.0
   },
   "state": "BIHAR",
   "units": 502.0,
   "value": 502.0
  },
  {
   "by_platform": {
    "BIG BASKET": 19.0,
    "SWIGGY": 384.0
   },
   "state": "JHARKHAND",
   "units": 403.0,
   "value": 403.0
  },
  {
   "by_platform": {
    "ZEPTO": 130.0
   },
   "state": "PUDUCHERRY",
   "units": 130.0,
   "value": 130.0
  },
  {
   "by_platform": {
    "BIG BASKET": 13.0,
    "SWIGGY": 51.0
   },
   "state": "ASSAM",
   "units": 64.0,
   "value": 64.0
  }
 ],
 "sub_categories": [],
 "total_units": 348125.0,
 "total_value": 348125.0,
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*
