---
type: app-dashboard
endpoint_key: state-sales__2024-10
source: app-dashboard
month: 2024-10
platform: ""
tags:
  - type/app-dashboard
  - source/app-dashboard
  - month/2024-10
---

# App dashboard — `state-sales__2024-10`

Up: [[dashboards-index]] · [[2024-10]]

> **source: app-dashboard `state-sales__2024-10`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "brands": [],
 "categories": [],
 "errors": [],
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
 "mapped_units": 21144.0,
 "mapped_value": 21144.0,
 "metric": "units",
 "metric_label": "Units sold",
 "metric_unit": "units",
 "mode": "single",
 "month": 10,
 "pct_mapped": 100.0,
 "platform": null,
 "states": [
  {
   "by_platform": {
    "BLINKIT": 6713.0
   },
   "state": "DELHI",
   "units": 6713.0,
   "value": 6713.0
  },
  {
   "by_platform": {
    "BLINKIT": 4859.0
   },
   "state": "PUNJAB",
   "units": 4859.0,
   "value": 4859.0
  },
  {
   "by_platform": {
    "BLINKIT": 4001.0
   },
   "state": "HARYANA",
   "units": 4001.0,
   "value": 4001.0
  },
  {
   "by_platform": {
    "BLINKIT": 2947.0
   },
   "state": "UTTAR PRADESH",
   "units": 2947.0,
   "value": 2947.0
  },
  {
   "by_platform": {
    "BLINKIT": 1121.0
   },
   "state": "CHANDIGARH",
   "units": 1121.0,
   "value": 1121.0
  },
  {
   "by_platform": {
    "BLINKIT": 446.0
   },
   "state": "MAHARASHTRA",
   "units": 446.0,
   "value": 446.0
  },
  {
   "by_platform": {
    "BLINKIT": 324.0
   },
   "state": "KARNATAKA",
   "units": 324.0,
   "value": 324.0
  },
  {
   "by_platform": {
    "BLINKIT": 268.0
   },
   "state": "UTTARAKHAND",
   "units": 268.0,
   "value": 268.0
  },
  {
   "by_platform": {
    "BLINKIT": 238.0
   },
   "state": "WEST BENGAL",
   "units": 238.0,
   "value": 238.0
  },
  {
   "by_platform": {
    "BLINKIT": 180.0
   },
   "state": "TELANGANA",
   "units": 180.0,
   "value": 180.0
  },
  {
   "by_platform": {
    "BLINKIT": 20.0
   },
   "state": "RAJASTHAN",
   "units": 20.0,
   "value": 20.0
  },
  {
   "by_platform": {
    "BLINKIT": 9.0
   },
   "state": "GUJARAT",
   "units": 9.0,
   "value": 9.0
  },
  {
   "by_platform": {
    "BLINKIT": 9.0
   },
   "state": "MADHYA PRADESH",
   "units": 9.0,
   "value": 9.0
  },
  {
   "by_platform": {
    "BLINKIT": 6.0
   },
   "state": "ANDHRA PRADESH",
   "units": 6.0,
   "value": 6.0
  },
  {
   "by_platform": {
    "BLINKIT": 3.0
   },
   "state": "TAMIL NADU",
   "units": 3.0,
   "value": 3.0
  }
 ],
 "sub_categories": [],
 "total_units": 21144.0,
 "total_value": 21144.0,
 "year": 2024
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*
