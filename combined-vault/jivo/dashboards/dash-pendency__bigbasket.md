---
type: app-dashboard
endpoint_key: pendency__bigbasket
source: app-dashboard
month: ""
platform: bigbasket
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/bigbasket
---

# App dashboard — `pendency__bigbasket`

Up: [[dashboards-index]] · [[pf-bigbasket]]

> **source: app-dashboard `pendency__bigbasket`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "by_city": [
  {
   "city": "Sonipat",
   "open_ltrs": 1864.0,
   "open_pos": 2,
   "open_units": 2754.0,
   "order_value": 373589.08,
   "pending_ltrs": 1864.0,
   "pending_units": 2754.0
  },
  {
   "city": "NOIDA",
   "open_ltrs": 792.0,
   "open_pos": 1,
   "open_units": 1140.0,
   "order_value": 162073.56,
   "pending_ltrs": 792.0,
   "pending_units": 1140.0
  },
  {
   "city": "BENGALURU",
   "open_ltrs": 784.0,
   "open_pos": 6,
   "open_units": 1078.0,
   "order_value": 172091.2,
   "pending_ltrs": 784.0,
   "pending_units": 1078.0
  },
  {
   "city": "PUNE",
   "open_ltrs": 460.0,
   "open_pos": 1,
   "open_units": 753.0,
   "order_value": 101561.81,
   "pending_ltrs": 460.0,
   "pending_units": 753.0
  },
  {
   "city": "LUCKNOW",
   "open_ltrs": 383.0,
   "open_pos": 2,
   "open_units": 211.0,
   "order_value": 79606.38,
   "pending_ltrs": 383.0,
   "pending_units": 211.0
  },
  {
   "city": "KOLKATA",
   "open_ltrs": 110.0,
   "open_pos": 1,
   "open_units": 980.0,
   "order_value": 69811.88,
   "pending_ltrs": 110.0,
   "pending_units": 980.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 3039.0,
   "open_pos": 5,
   "open_units": 4105.0,
   "order_value": 615269.02,
   "pending_ltrs": 3039.0,
   "pending_units": 4105.0
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "open_ltrs": 784.0,
   "open_pos": 6,
   "open_units": 1078.0,
   "order_value": 172091.2,
   "pending_ltrs": 784.0,
   "pending_units": 1078.0
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 460.0,
   "open_pos": 1,
   "open_units": 753.0,
   "order_value": 101561.81,
   "pending_ltrs": 460.0,
   "pending_units": 753.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 110.0,
   "open_pos": 1,
   "open_units": 980.0,
   "order_value": 69811.88,
   "pending_ltrs": 110.0,
   "pending_units": 980.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Sonipat",
   "open_ltrs": 1014.0,
   "open_pos": 1,
   "open_units": 1028.0,
   "order_value": 171461.34,
   "pending_ltrs": 1014.0,
   "pending_units": 1028.0,
   "po_date": "27-06-2026",
   "po_expiry_date": "12-07-2026",
   "po_number": "IRA40055659"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Sonipat",
   "open_ltrs": 850.0,
   "open_pos": 1,
   "open_units": 1726.0,
   "order_value": 202127.74,
   "pending_ltrs": 850.0,
   "pending_units": 1726.0,
   "po_date": "20-06-2026",
   "po_expiry_date": "05-07-2026",
   "po_number": "IRA39709850"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Noida",
   "open_ltrs": 792.0,
   "open_pos": 1,
   "open_units": 1140.0,
   "order_value": 162073.56,
   "pending_ltrs": 792.0,
   "pending_units": 1140.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "11-07-2026",
   "po_number": "IRA40006030"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Pune",
   "open_ltrs": 460.0,
   "open_pos": 1,
   "open_units": 753.0,
   "order_value": 101561.81,
   "pending_ltrs": 460.0,
   "pending_units": 753.0,
   "po_date": "30-06-2026",
   "po_expiry_date": "15-07-2026",
   "po_number": "IRA40209517"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 312.0,
   "open_pos": 1,
   "open_units": 758.0,
   "order_value": 81383.36,
   "pending_ltrs": 312.0,
   "pending_units": 758.0,
   "po_date": "16-06-2026",
   "po_expiry_date": "04-07-2026",
   "po_number": "IRA39509180"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 234.0,
   "open_pos": 1,
   "open_units": 126.0,
   "order_value": 51846.79,
   "pending_ltrs": 234.0,
   "pending_units": 126.0,
   "po_date": "29-06-2026",
   "po_expiry_date": "29-07-2026",
   "po_number": "IRA40160789"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 149.0,
   "open_pos": 1,
   "open_units": 85.0,
   "order_value": 27759.59,
   "pending_ltrs": 149.0,
   "pending_units": 85.0,
   "po_date": "15-06-2026",
   "po_expiry_date": "15-07-2026",
   "po_number": "IRA39460571"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 136.0,
   "open_pos": 1,
   "open_units": 56.0,
   "order_value": 28050.56,
   "pending_ltrs": 136.0,
   "pending_units": 56.0,
   "po_date": "22-06-2026",
   "po_expiry_date": "07-07-2026",
   "po_number": "IRA39804294"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 120.0,
   "order_value": 20919.36,
   "pending_ltrs": 120.0,
   "pending_units": 120.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "08-07-2026",
   "po_number": "IRA39855445"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 24.0,
   "order_value": 19364.64,
   "pending_ltrs": 120.0,
   "pending_units": 24.0,
   "po_date": "30-06-2026",
   "po_expiry_date": "15-07-2026",
   "po_number": "IRA40208282"
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "location": "Kolkata",
   "open_ltrs": 110.0,
   "open_pos": 1,
   "open_units": 980.0,
   "order_value": 69811.88,
   "pending_ltrs": 110.0,
   "pending_units": 980.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "11-07-2026",
   "po_number": "IRA40005330"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 96.0,
   "open_pos": 1,
   "open_units": 96.0,
   "order_value": 21596.16,
   "pending_ltrs": 96.0,
   "pending_units": 96.0,
   "po_date": "29-06-2026",
   "po_expiry_date": "14-07-2026",
   "po_number": "IRA40151616"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 24.0,
   "order_value": 777.12,
   "pending_ltrs": 0.0,
   "pending_units": 24.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "08-07-2026",
   "po_number": "IRA39854978"
  }
 ],
 "by_sku": [
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 1820.0,
   "open_pos": 8,
   "open_units": 1820.0,
   "order_value": 274080.8,
   "pending_ltrs": 1820.0,
   "pending_units": 1820.0,
   "sku_code": "40249993",
   "sku_name": "Jivo Cold Pressed Sunflower Oil 1 L Bottle"
  },
  {
   "item": "SUNFLOWER 5L",
   "open_ltrs": 820.0,
   "open_pos": 7,
   "open_units": 164.0,
   "order_value": 128684.48,
   "pending_ltrs": 820.0,
   "pending_units": 164.0,
   "sku_code": "40249992",
   "sku_name": "Jivo Sunflower Oil - Cold Pressed, Fortified With Vitamins A & D, Chemical Free 5 L Jar"
  },
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 601.0,
   "open_pos": 5,
   "open_units": 601.0,
   "order_value": 97065.26,
   "pending_ltrs": 601.0,
   "pending_units": 601.0,
   "sku_code": "40166395",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 1 L Bottle"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 350.0,
   "open_pos": 6,
   "open_units": 350.0,
   "order_value": 76655.32,
   "pending_ltrs": 350.0,
   "pending_units": 350.0,
   "sku_code": "282779",
   "sku_name": "Jivo Canola Oil - Cold Pressed 1 L"
  },
  {
   "item": "CANOLA 1L POUCH",
   "open_ltrs": 199.0,
   "open_pos": 4,
   "open_units": 199.0,
   "order_value": 37133.56,
   "pending_ltrs": 199.0,
   "pending_units": 199.0,
   "sku_code": "40309979",
   "sku_name": "Jivo Canola Omega-3 Rich Cooking Oil 1 L 1 L Pouch"
  },
  {
   "item": "CANOLA 5L",
   "open_ltrs": 155.0,
   "open_pos": 3,
   "open_units": 31.0,
   "order_value": 33952.44,
   "pending_ltrs": 155.0,
   "pending_units": 31.0,
   "sku_code": "282780",
   "sku_name": "Jivo Canola Oil - Cold Pressed 5 L Bottle"
  },
  {
   "item": "EXTRA LIGHT 1L",
   "open_ltrs": 140.0,
   "open_pos": 7,
   "open_units": 140.0,
   "order_value": 73955.24,
   "pending_ltrs": 140.0,
   "pending_units": 140.0,
   "sku_code": "40166398",
   "sku_name": "Jivo Extra Light Olive Oil 1 L Bottle"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 128.0,
   "open_pos": 4,
   "open_units": 128.0,
   "order_value": 52437.12,
   "pending_ltrs": 128.0,
   "pending_units": 128.0,
   "sku_code": "40197820",
   "sku_name": "Jivo Pomace Olive Oil 1 L"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 100.0,
   "open_pos": 2,
   "open_units": 20.0,
   "order_value": 18333.4,
   "pending_ltrs": 100.0,
   "pending_units": 20.0,
   "sku_code": "40166396",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 5 L Bottle"
  },
  {
   "item": "EXTRA LIGHT 2L",
   "open_ltrs": 40.0,
   "open_pos": 2,
   "open_units": 20.0,
   "order_value": 20392.2,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "sku_code": "40250809",
   "sku_name": "Jivo Extra Light Olive Oil - Antioxidants Rich, Light Cooking Medium, For Frying, Grilling 2 L"
  },
  {
   "item": "JIVO POMACE 2L",
   "open_ltrs": 40.0,
   "open_pos": 2,
   "open_units": 20.0,
   "order_value": 16439.2,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "sku_code": "40309980",
   "sku_name": "Jivo Pomace Olive Oil 2 L"
  },
  {
   "item": "WG GINGER ALE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 394.0,
   "order_value": 12757.72,
   "pending_ltrs": 0.0,
   "pending_units": 394.0,
   "sku_code": "40335330",
   "sku_name": "Jivo Ginger Ale Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG APPLE JUICE SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 356.0,
   "order_value": 12624.56,
   "pending_ltrs": 0.0,
   "pending_units": 356.0,
   "sku_code": "40335329",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG BLUEBERRY JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 352.0,
   "order_value": 11398.72,
   "pending_ltrs": 0.0,
   "pending_units": 352.0,
   "sku_code": "40335335",
   "sku_name": "Jivo Blueberry Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MOJITO 200ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 333.0,
   "order_value": 11883.42,
   "pending_ltrs": 0.0,
   "pending_units": 333.0,
   "sku_code": "40335337",
   "sku_name": "Jivo Mojito Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MOJITO SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 324.0,
   "order_value": 11960.88,
   "pending_ltrs": 0.0,
   "pending_units": 324.0,
   "sku_code": "40335331",
   "sku_name": "Jivo Mojito Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG MANGO JUICE 500ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 304.0,
   "order_value": 23804.0,
   "pending_ltrs": 0.0,
   "pending_units": 304.0,
   "sku_code": "40335340",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 500 ml"
  },
  {
   "item": "WG ROSE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 7,
   "open_units": 279.0,
   "order_value": 10134.18,
   "pending_ltrs": 0.0,
   "pending_units": 279.0,
   "sku_code": "40335338",
   "sku_name": "Jivo Rose Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MANGO JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 7,
   "open_units": 277.0,
   "order_value": 10066.18,
   "pending_ltrs": 0.0,
   "pending_units": 277.0,
   "sku_code": "40335336",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "LEMON 750ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 277.0,
   "order_value": 7541.14,
   "pending_ltrs": 0.0,
   "pending_units": 277.0,
   "sku_code": "40335332",
   "sku_name": "Jivo Fizzy Water Flavoured With Lemon 750 ml"
  },
  {
   "item": "WATER PEACH 750ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 253.0,
   "order_value": 6892.81,
   "pending_ltrs": 0.0,
   "pending_units": 253.0,
   "sku_code": "40335333",
   "sku_name": "Jivo Fizzy Water Flavoured With Peach 750 ml"
  },
  {
   "item": "WG APPLE JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 4,
   "open_units": 192.0,
   "order_value": 7135.56,
   "pending_ltrs": 0.0,
   "pending_units": 192.0,
   "sku_code": "40335334",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "TONIC WATER 200ML",
   "open_ltrs": 0.0,
   "open_pos": 3,
   "open_units": 82.0,
   "order_value": 3405.72,
   "pending_ltrs": 0.0,
   "pending_units": 82.0,
   "sku_code": "40335339",
   "sku_name": "Jivo Indian Tonic Water 200 ml"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 1864.0,
   "open_pos": 2,
   "open_units": 2754.0,
   "order_value": 373589.08,
   "pending_ltrs": 1864.0,
   "pending_units": 2754.0,
   "warehouse": "Sonipat"
  },
  {
   "open_ltrs": 792.0,
   "open_pos": 1,
   "open_units": 1140.0,
   "order_value": 162073.56,
   "pending_ltrs": 792.0,
   "pending_units": 1140.0,
   "warehouse": "Noida"
  },
  {
   "open_ltrs": 784.0,
   "open_pos": 6,
   "open_units": 1078.0,
   "order_value": 172091.2,
   "pending_ltrs": 784.0,
   "pending_units": 1078.0,
   "warehouse": "Bengaluru"
  },
  {
   "open_ltrs": 460.0,
   "open_pos": 1,
   "open_units": 753.0,
   "order_value": 101561.81,
   "pending_ltrs": 460.0,
   "pending_units": 753.0,
   "warehouse": "Pune"
  },
  {
   "open_ltrs": 383.0,
   "open_pos": 2,
   "open_units": 211.0,
   "order_value": 79606.38,
   "pending_ltrs": 383.0,
   "pending_units": 211.0,
   "warehouse": "Lucknow"
  },
  {
   "open_ltrs": 110.0,
   "open_pos": 1,
   "open_units": 980.0,
   "order_value": 69811.88,
   "pending_ltrs": 110.0,
   "pending_units": 980.0,
   "warehouse": "Kolkata"
  }
 ],
 "defaulted_to_latest": true,
 "format": "BIG BASKET",
 "max_po_date": "30-06-2026",
 "min_po_date": "15-06-2026",
 "platform": "bigbasket",
 "po_month": "JUNE",
 "totals": {
  "open_ltrs": 4393.0,
  "open_pos": 13,
  "open_units": 6916.0,
  "pending_ltrs": 4393.0,
  "pending_units": 6916.0,
  "rows": 114
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - bigbasket]]
