---
type: app-dashboard
endpoint_key: pendency__flipkart_grocery
source: app-dashboard
month: ""
platform: flipkart_grocery
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/flipkart_grocery
---

# App dashboard — `pendency__flipkart_grocery`

Up: [[dashboards-index]] · [[pf-flipkart_grocery]]

> **source: app-dashboard `pendency__flipkart_grocery`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "by_city": [
  {
   "city": "Manesar",
   "open_ltrs": 3660.0,
   "open_pos": 3,
   "open_units": 4430.0,
   "order_value": 606330.4761904762,
   "pending_ltrs": 3660.0,
   "pending_units": 4430.0
  },
  {
   "city": "LUCKNOW",
   "open_ltrs": 3440.0,
   "open_pos": 2,
   "open_units": 3440.0,
   "order_value": 509047.61904761905,
   "pending_ltrs": 3440.0,
   "pending_units": 3440.0
  },
  {
   "city": "Bijwasan",
   "open_ltrs": 2660.0,
   "open_pos": 1,
   "open_units": 2544.0,
   "order_value": 406571.4285714286,
   "pending_ltrs": 2660.0,
   "pending_units": 2544.0
  },
  {
   "city": "Sonipat",
   "open_ltrs": 2240.0,
   "open_pos": 1,
   "open_units": 2220.0,
   "order_value": 367142.85714285716,
   "pending_ltrs": 2240.0,
   "pending_units": 2220.0
  },
  {
   "city": "LUDHIANA",
   "open_ltrs": 1720.0,
   "open_pos": 3,
   "open_units": 1720.0,
   "order_value": 260095.2380952381,
   "pending_ltrs": 1720.0,
   "pending_units": 1720.0
  },
  {
   "city": "Hoskote",
   "open_ltrs": 720.0,
   "open_pos": 2,
   "open_units": 720.0,
   "order_value": 134761.90476190476,
   "pending_ltrs": 720.0,
   "pending_units": 720.0
  },
  {
   "city": "Thane",
   "open_ltrs": 240.0,
   "open_pos": 1,
   "open_units": 240.0,
   "order_value": 35428.57142857143,
   "pending_ltrs": 240.0,
   "pending_units": 240.0
  },
  {
   "city": "Howrah",
   "open_ltrs": 180.0,
   "open_pos": 1,
   "open_units": 180.0,
   "order_value": 26571.428571428572,
   "pending_ltrs": 180.0,
   "pending_units": 180.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 12000.0,
   "open_pos": 6,
   "open_units": 11824.0,
   "order_value": 1867878.0952380951,
   "pending_ltrs": 12000.0,
   "pending_units": 11824.0
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "open_ltrs": 1720.0,
   "open_pos": 3,
   "open_units": 1720.0,
   "order_value": 260095.2380952381,
   "pending_ltrs": 1720.0,
   "pending_units": 1720.0
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "open_ltrs": 720.0,
   "open_pos": 2,
   "open_units": 720.0,
   "order_value": 134761.90476190476,
   "pending_ltrs": 720.0,
   "pending_units": 720.0
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 240.0,
   "open_pos": 1,
   "open_units": 240.0,
   "order_value": 35428.57142857143,
   "pending_ltrs": 240.0,
   "pending_units": 240.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 180.0,
   "open_pos": 1,
   "open_units": 180.0,
   "order_value": 26571.428571428572,
   "pending_ltrs": 180.0,
   "pending_units": 180.0
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 810.0,
   "order_value": 21214.285714285714,
   "pending_ltrs": 0.0,
   "pending_units": 810.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 3580.0,
   "open_pos": 1,
   "open_units": 3580.0,
   "order_value": 528476.1904761905,
   "pending_ltrs": 3580.0,
   "pending_units": 3580.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "19-07-2026",
   "po_number": "FLS28675B3EE"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Bijwasan",
   "open_ltrs": 2660.0,
   "open_pos": 1,
   "open_units": 2544.0,
   "order_value": 406571.4285714286,
   "pending_ltrs": 2660.0,
   "pending_units": 2544.0,
   "po_date": "08-07-2026",
   "po_expiry_date": "23-07-2026",
   "po_number": "FLS46F455F19"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Sonipat",
   "open_ltrs": 2240.0,
   "open_pos": 1,
   "open_units": 2220.0,
   "order_value": 367142.85714285716,
   "pending_ltrs": 2240.0,
   "pending_units": 2220.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "17-07-2026",
   "po_number": "FLS104D90C6B"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 1720.0,
   "open_pos": 1,
   "open_units": 1720.0,
   "order_value": 253904.7619047619,
   "pending_ltrs": 1720.0,
   "pending_units": 1720.0,
   "po_date": "07-07-2026",
   "po_expiry_date": "17-07-2026",
   "po_number": "FLSA7F740187"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 1720.0,
   "open_pos": 1,
   "open_units": 1720.0,
   "order_value": 255142.85714285713,
   "pending_ltrs": 1720.0,
   "pending_units": 1720.0,
   "po_date": "03-07-2026",
   "po_expiry_date": "13-07-2026",
   "po_number": "FLSE02D00CF0"
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Ludhiana",
   "open_ltrs": 600.0,
   "open_pos": 1,
   "open_units": 600.0,
   "order_value": 88571.42857142857,
   "pending_ltrs": 600.0,
   "pending_units": 600.0,
   "po_date": "08-07-2026",
   "po_expiry_date": "20-07-2026",
   "po_number": "FLGWN08378650"
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Ludhiana",
   "open_ltrs": 580.0,
   "open_pos": 1,
   "open_units": 580.0,
   "order_value": 86857.14285714286,
   "pending_ltrs": 580.0,
   "pending_units": 580.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "16-07-2026",
   "po_number": "FLGWN08373066"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Hoskote",
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 97047.61904761905,
   "pending_ltrs": 540.0,
   "pending_units": 540.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "20-07-2026",
   "po_number": "FBHWN08373038"
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Ludhiana",
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 84666.66666666667,
   "pending_ltrs": 540.0,
   "pending_units": 540.0,
   "po_date": "07-07-2026",
   "po_expiry_date": "17-07-2026",
   "po_number": "FLGWN08376903"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Thane",
   "open_ltrs": 240.0,
   "open_pos": 1,
   "open_units": 240.0,
   "order_value": 35428.57142857143,
   "pending_ltrs": 240.0,
   "pending_units": 240.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "20-07-2026",
   "po_number": "FBPWN08373025"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Hoskote",
   "open_ltrs": 180.0,
   "open_pos": 1,
   "open_units": 180.0,
   "order_value": 37714.28571428571,
   "pending_ltrs": 180.0,
   "pending_units": 180.0,
   "po_date": "08-07-2026",
   "po_expiry_date": "23-07-2026",
   "po_number": "FBHWN08378632"
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "location": "Howrah",
   "open_ltrs": 180.0,
   "open_pos": 1,
   "open_units": 180.0,
   "order_value": 26571.428571428572,
   "pending_ltrs": 180.0,
   "pending_units": 180.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "20-07-2026",
   "po_number": "FUSWN08373044"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 80.0,
   "open_pos": 1,
   "open_units": 40.0,
   "order_value": 56639.99999999999,
   "pending_ltrs": 80.0,
   "pending_units": 40.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "19-07-2026",
   "po_number": "FLS85A6AF872"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 810.0,
   "order_value": 21214.285714285714,
   "pending_ltrs": 0.0,
   "pending_units": 810.0,
   "po_date": "09-07-2026",
   "po_expiry_date": "29-07-2026",
   "po_number": "FBSWN08380114"
  }
 ],
 "by_sku": [
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 13820.0,
   "open_pos": 11,
   "open_units": 13820.0,
   "order_value": 2040095.238095238,
   "pending_ltrs": 13820.0,
   "pending_units": 13820.0,
   "sku_code": "EDOGDVWYGJNDYRQP",
   "sku_name": "JIVO Cold Pressed Pure Cooking (Pack of 1) Mustard Oil 1 L Plastic Bottle"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 680.0,
   "open_pos": 6,
   "open_units": 680.0,
   "order_value": 142476.19047619047,
   "pending_ltrs": 680.0,
   "pending_units": 680.0,
   "sku_code": "EDOG9BP8GEWFW9XC",
   "sku_name": "JIVO Cold Press Canola Oil 1 L Plastic Bottle"
  },
  {
   "item": "EXTRA LIGHT 2L",
   "open_ltrs": 120.0,
   "open_pos": 3,
   "open_units": 60.0,
   "order_value": 76939.04761904762,
   "pending_ltrs": 120.0,
   "pending_units": 60.0,
   "sku_code": "EDOGHZTJZEYQJGME",
   "sku_name": "JIVO Extra Light Olive Oil 2 L Can"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 24.0,
   "order_value": 17714.285714285714,
   "pending_ltrs": 120.0,
   "pending_units": 24.0,
   "sku_code": "EDOGDVWEUPPWVGED",
   "sku_name": "JIVO Cold Pressed Pure Cooking Mustard Oil 5 L Can"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 80.0,
   "open_pos": 1,
   "open_units": 80.0,
   "order_value": 28190.476190476187,
   "pending_ltrs": 80.0,
   "pending_units": 80.0,
   "sku_code": "EDOFTHNH4YZ7GDHS",
   "sku_name": "JIVO Pomace Olive Oil 1 L Plastic Bottle"
  },
  {
   "item": "JIVO POMACE 2L",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 20.0,
   "order_value": 19319.999999999996,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "sku_code": "EDOGMHXYU2PHFW4N",
   "sku_name": "JIVO Pomace Cooking Olive Oil 2L Olive Oil 2 L Plastic Bottle"
  },
  {
   "item": "WG BLUEBERRY JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 368.0,
   "order_value": 9638.095238095239,
   "pending_ltrs": 0.0,
   "pending_units": 368.0,
   "sku_code": "AYDHFFYPJBCECYCZ",
   "sku_name": "JIVO Healthy Wheatgrass Blueberry Drink -Sugar Free 200 ml"
  },
  {
   "item": "WG MOJITO 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 300.0,
   "order_value": 7857.142857142857,
   "pending_ltrs": 0.0,
   "pending_units": 300.0,
   "sku_code": "AYDHFFYPBG3UKXRR",
   "sku_name": "JIVO Healthy Wheatgrass Mojito Drink -Sugar Free 200 ml"
  },
  {
   "item": "WG GINGER ALE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 142.0,
   "order_value": 3719.047619047619,
   "pending_ltrs": 0.0,
   "pending_units": 142.0,
   "sku_code": "AYDHFFYPKDHFFXN8",
   "sku_name": "JIVO Healthy Wheatgrass Ginger Ale Drink -Sugar Free 200 ml"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 3660.0,
   "open_pos": 3,
   "open_units": 4430.0,
   "order_value": 606330.4761904762,
   "pending_ltrs": 3660.0,
   "pending_units": 4430.0,
   "warehouse": "Manesar"
  },
  {
   "open_ltrs": 3440.0,
   "open_pos": 2,
   "open_units": 3440.0,
   "order_value": 509047.61904761905,
   "pending_ltrs": 3440.0,
   "pending_units": 3440.0,
   "warehouse": "Lucknow"
  },
  {
   "open_ltrs": 2660.0,
   "open_pos": 1,
   "open_units": 2544.0,
   "order_value": 406571.4285714286,
   "pending_ltrs": 2660.0,
   "pending_units": 2544.0,
   "warehouse": "Bijwasan"
  },
  {
   "open_ltrs": 2240.0,
   "open_pos": 1,
   "open_units": 2220.0,
   "order_value": 367142.85714285716,
   "pending_ltrs": 2240.0,
   "pending_units": 2220.0,
   "warehouse": "Sonipat"
  },
  {
   "open_ltrs": 1720.0,
   "open_pos": 3,
   "open_units": 1720.0,
   "order_value": 260095.2380952381,
   "pending_ltrs": 1720.0,
   "pending_units": 1720.0,
   "warehouse": "Ludhiana"
  },
  {
   "open_ltrs": 720.0,
   "open_pos": 2,
   "open_units": 720.0,
   "order_value": 134761.90476190476,
   "pending_ltrs": 720.0,
   "pending_units": 720.0,
   "warehouse": "Hoskote"
  },
  {
   "open_ltrs": 240.0,
   "open_pos": 1,
   "open_units": 240.0,
   "order_value": 35428.57142857143,
   "pending_ltrs": 240.0,
   "pending_units": 240.0,
   "warehouse": "Thane"
  },
  {
   "open_ltrs": 180.0,
   "open_pos": 1,
   "open_units": 180.0,
   "order_value": 26571.428571428572,
   "pending_ltrs": 180.0,
   "pending_units": 180.0,
   "warehouse": "Howrah"
  }
 ],
 "defaulted_to_latest": true,
 "format": "FLIPKART GROCERY",
 "max_po_date": "09-07-2026",
 "min_po_date": "01-07-2026",
 "platform": "flipkart_grocery",
 "po_month": "JULY",
 "totals": {
  "open_ltrs": 14860.0,
  "open_pos": 14,
  "open_units": 15494.0,
  "pending_ltrs": 14860.0,
  "pending_units": 15494.0,
  "rows": 26
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - flipkart]] · [[Platform - flipkart_grocery]]
