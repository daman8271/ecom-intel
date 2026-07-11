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
   "city": "NOIDA",
   "open_ltrs": 2836.0,
   "open_pos": 2,
   "open_units": 2130.0,
   "order_value": 531178.48,
   "pending_ltrs": 2836.0,
   "pending_units": 2130.0
  },
  {
   "city": "Sonipat",
   "open_ltrs": 1648.0,
   "open_pos": 1,
   "open_units": 1612.0,
   "order_value": 289099.76,
   "pending_ltrs": 1648.0,
   "pending_units": 1612.0
  },
  {
   "city": "PUNE",
   "open_ltrs": 720.0,
   "open_pos": 1,
   "open_units": 551.0,
   "order_value": 131170.47,
   "pending_ltrs": 720.0,
   "pending_units": 551.0
  },
  {
   "city": "BENGALURU",
   "open_ltrs": 340.0,
   "open_pos": 3,
   "open_units": 1200.0,
   "order_value": 92480.88,
   "pending_ltrs": 340.0,
   "pending_units": 1200.0
  },
  {
   "city": "KOLKATA",
   "open_ltrs": 106.0,
   "open_pos": 1,
   "open_units": 900.0,
   "order_value": 65592.4,
   "pending_ltrs": 106.0,
   "pending_units": 900.0
  },
  {
   "city": "LUCKNOW",
   "open_ltrs": 71.0,
   "open_pos": 1,
   "open_units": 27.0,
   "order_value": 14588.14,
   "pending_ltrs": 71.0,
   "pending_units": 27.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 4555.0,
   "open_pos": 4,
   "open_units": 3769.0,
   "order_value": 834866.38,
   "pending_ltrs": 4555.0,
   "pending_units": 3769.0
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 720.0,
   "open_pos": 1,
   "open_units": 551.0,
   "order_value": 131170.47,
   "pending_ltrs": 720.0,
   "pending_units": 551.0
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "open_ltrs": 340.0,
   "open_pos": 3,
   "open_units": 1200.0,
   "order_value": 92480.88,
   "pending_ltrs": 340.0,
   "pending_units": 1200.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 106.0,
   "open_pos": 1,
   "open_units": 900.0,
   "order_value": 65592.4,
   "pending_ltrs": 106.0,
   "pending_units": 900.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Sonipat",
   "open_ltrs": 1648.0,
   "open_pos": 1,
   "open_units": 1612.0,
   "order_value": 289099.76,
   "pending_ltrs": 1648.0,
   "pending_units": 1612.0,
   "po_date": "04-07-2026",
   "po_expiry_date": "19-07-2026",
   "po_number": "IRA40434322"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Noida",
   "open_ltrs": 1488.0,
   "open_pos": 1,
   "open_units": 1435.0,
   "order_value": 274700.3,
   "pending_ltrs": 1488.0,
   "pending_units": 1435.0,
   "po_date": "03-07-2026",
   "po_expiry_date": "18-07-2026",
   "po_number": "IRA40365980"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Noida",
   "open_ltrs": 1348.0,
   "open_pos": 1,
   "open_units": 695.0,
   "order_value": 256478.18,
   "pending_ltrs": 1348.0,
   "pending_units": 695.0,
   "po_date": "10-07-2026",
   "po_expiry_date": "25-07-2026",
   "po_number": "IRA40737719"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Pune",
   "open_ltrs": 720.0,
   "open_pos": 1,
   "open_units": 551.0,
   "order_value": 131170.47,
   "pending_ltrs": 720.0,
   "pending_units": 551.0,
   "po_date": "07-07-2026",
   "po_expiry_date": "22-07-2026",
   "po_number": "IRA40590633"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 200.0,
   "open_pos": 1,
   "open_units": 538.0,
   "order_value": 50711.92,
   "pending_ltrs": 200.0,
   "pending_units": 538.0,
   "po_date": "07-07-2026",
   "po_expiry_date": "22-07-2026",
   "po_number": "IRA40589289"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 140.0,
   "open_pos": 1,
   "open_units": 140.0,
   "order_value": 22593.2,
   "pending_ltrs": 140.0,
   "pending_units": 140.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "21-07-2026",
   "po_number": "IRA40546128"
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "location": "Kolkata",
   "open_ltrs": 106.0,
   "open_pos": 1,
   "open_units": 900.0,
   "order_value": 65592.4,
   "pending_ltrs": 106.0,
   "pending_units": 900.0,
   "po_date": "10-07-2026",
   "po_expiry_date": "25-07-2026",
   "po_number": "IRA40737006"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 71.0,
   "open_pos": 1,
   "open_units": 27.0,
   "order_value": 14588.14,
   "pending_ltrs": 71.0,
   "pending_units": 27.0,
   "po_date": "06-07-2026",
   "po_expiry_date": "05-08-2026",
   "po_number": "IRA40535712"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Bengaluru",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 522.0,
   "order_value": 19175.76,
   "pending_ltrs": 0.0,
   "pending_units": 522.0,
   "po_date": "07-07-2026",
   "po_expiry_date": "22-07-2026",
   "po_number": "IRA40588634"
  }
 ],
 "by_sku": [
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 1760.0,
   "open_pos": 5,
   "open_units": 1760.0,
   "order_value": 267150.0,
   "pending_ltrs": 1760.0,
   "pending_units": 1760.0,
   "sku_code": "40249993",
   "sku_name": "Jivo Cold Pressed Sunflower Oil 1 L Bottle"
  },
  {
   "item": "SUNFLOWER 5L",
   "open_ltrs": 1380.0,
   "open_pos": 4,
   "open_units": 276.0,
   "order_value": 206808.76,
   "pending_ltrs": 1380.0,
   "pending_units": 276.0,
   "sku_code": "40249992",
   "sku_name": "Jivo Sunflower Oil - Cold Pressed, Fortified With Vitamins A & D, Chemical Free 5 L Jar"
  },
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 1051.0,
   "open_pos": 4,
   "open_units": 1051.0,
   "order_value": 171979.82,
   "pending_ltrs": 1051.0,
   "pending_units": 1051.0,
   "sku_code": "40166395",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 1 L Bottle"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 465.0,
   "open_pos": 4,
   "open_units": 93.0,
   "order_value": 74078.75,
   "pending_ltrs": 465.0,
   "pending_units": 93.0,
   "sku_code": "40166396",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 5 L Bottle"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 391.0,
   "open_pos": 5,
   "open_units": 391.0,
   "order_value": 85639.09,
   "pending_ltrs": 391.0,
   "pending_units": 391.0,
   "sku_code": "282779",
   "sku_name": "Jivo Canola Oil - Cold Pressed 1 L"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 176.0,
   "open_pos": 4,
   "open_units": 176.0,
   "order_value": 59641.6,
   "pending_ltrs": 176.0,
   "pending_units": 176.0,
   "sku_code": "40197820",
   "sku_name": "Jivo Pomace Olive Oil 1 L"
  },
  {
   "item": "CANOLA 5L",
   "open_ltrs": 170.0,
   "open_pos": 4,
   "open_units": 34.0,
   "order_value": 37047.6,
   "pending_ltrs": 170.0,
   "pending_units": 34.0,
   "sku_code": "282780",
   "sku_name": "Jivo Canola Oil - Cold Pressed 5 L Bottle"
  },
  {
   "item": "CANOLA 1L POUCH",
   "open_ltrs": 108.0,
   "open_pos": 1,
   "open_units": 108.0,
   "order_value": 19683.0,
   "pending_ltrs": 108.0,
   "pending_units": 108.0,
   "sku_code": "40309979",
   "sku_name": "Jivo Canola Omega-3 Rich Cooking Oil 1 L 1 L Pouch"
  },
  {
   "item": "EXTRA LIGHT 1L",
   "open_ltrs": 100.0,
   "open_pos": 3,
   "open_units": 100.0,
   "order_value": 51187.2,
   "pending_ltrs": 100.0,
   "pending_units": 100.0,
   "sku_code": "40166398",
   "sku_name": "Jivo Extra Light Olive Oil 1 L Bottle"
  },
  {
   "item": "EXTRA LIGHT 5L",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 12.0,
   "order_value": 28788.6,
   "pending_ltrs": 60.0,
   "pending_units": 12.0,
   "sku_code": "40166397",
   "sku_name": "Jivo Extra Light Olive Oil 5 L Tin"
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
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 8219.6,
   "pending_ltrs": 20.0,
   "pending_units": 10.0,
   "sku_code": "40309980",
   "sku_name": "Jivo Pomace Olive Oil 2 L"
  },
  {
   "item": "LEMON 750ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 263.0,
   "order_value": 7491.29,
   "pending_ltrs": 0.0,
   "pending_units": 263.0,
   "sku_code": "40335332",
   "sku_name": "Jivo Fizzy Water Flavoured With Lemon 750 ml"
  },
  {
   "item": "WG APPLE JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 228.0,
   "order_value": 8297.04,
   "pending_ltrs": 0.0,
   "pending_units": 228.0,
   "sku_code": "40335334",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MOJITO SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 228.0,
   "order_value": 7650.6,
   "pending_ltrs": 0.0,
   "pending_units": 228.0,
   "sku_code": "40335331",
   "sku_name": "Jivo Mojito Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG APPLE JUICE SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 218.0,
   "order_value": 8156.12,
   "pending_ltrs": 0.0,
   "pending_units": 218.0,
   "sku_code": "40335329",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WATER PEACH 750ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 218.0,
   "order_value": 6201.86,
   "pending_ltrs": 0.0,
   "pending_units": 218.0,
   "sku_code": "40335333",
   "sku_name": "Jivo Fizzy Water Flavoured With Peach 750 ml"
  },
  {
   "item": "WG BLUEBERRY JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 6,
   "open_units": 205.0,
   "order_value": 6638.02,
   "pending_ltrs": 0.0,
   "pending_units": 205.0,
   "sku_code": "40335335",
   "sku_name": "Jivo Blueberry Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG GINGER ALE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 5,
   "open_units": 205.0,
   "order_value": 6637.9,
   "pending_ltrs": 0.0,
   "pending_units": 205.0,
   "sku_code": "40335330",
   "sku_name": "Jivo Ginger Ale Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG MANGO JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 4,
   "open_units": 204.0,
   "order_value": 7702.32,
   "pending_ltrs": 0.0,
   "pending_units": 204.0,
   "sku_code": "40335336",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MANGO JUICE 500ML",
   "open_ltrs": 0.0,
   "open_pos": 4,
   "open_units": 198.0,
   "order_value": 17658.72,
   "pending_ltrs": 0.0,
   "pending_units": 198.0,
   "sku_code": "40335340",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 500 ml"
  },
  {
   "item": "WG MOJITO 200ML",
   "open_ltrs": 0.0,
   "open_pos": 3,
   "open_units": 180.0,
   "order_value": 7108.56,
   "pending_ltrs": 0.0,
   "pending_units": 180.0,
   "sku_code": "40335337",
   "sku_name": "Jivo Mojito Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG ROSE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 4,
   "open_units": 168.0,
   "order_value": 6537.12,
   "pending_ltrs": 0.0,
   "pending_units": 168.0,
   "sku_code": "40335338",
   "sku_name": "Jivo Rose Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "TONIC WATER 200ML",
   "open_ltrs": 0.0,
   "open_pos": 3,
   "open_units": 74.0,
   "order_value": 3414.36,
   "pending_ltrs": 0.0,
   "pending_units": 74.0,
   "sku_code": "40335339",
   "sku_name": "Jivo Indian Tonic Water 200 ml"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 2836.0,
   "open_pos": 2,
   "open_units": 2130.0,
   "order_value": 531178.48,
   "pending_ltrs": 2836.0,
   "pending_units": 2130.0,
   "warehouse": "Noida"
  },
  {
   "open_ltrs": 1648.0,
   "open_pos": 1,
   "open_units": 1612.0,
   "order_value": 289099.76,
   "pending_ltrs": 1648.0,
   "pending_units": 1612.0,
   "warehouse": "Sonipat"
  },
  {
   "open_ltrs": 720.0,
   "open_pos": 1,
   "open_units": 551.0,
   "order_value": 131170.47,
   "pending_ltrs": 720.0,
   "pending_units": 551.0,
   "warehouse": "Pune"
  },
  {
   "open_ltrs": 340.0,
   "open_pos": 3,
   "open_units": 1200.0,
   "order_value": 92480.88,
   "pending_ltrs": 340.0,
   "pending_units": 1200.0,
   "warehouse": "Bengaluru"
  },
  {
   "open_ltrs": 106.0,
   "open_pos": 1,
   "open_units": 900.0,
   "order_value": 65592.4,
   "pending_ltrs": 106.0,
   "pending_units": 900.0,
   "warehouse": "Kolkata"
  },
  {
   "open_ltrs": 71.0,
   "open_pos": 1,
   "open_units": 27.0,
   "order_value": 14588.14,
   "pending_ltrs": 71.0,
   "pending_units": 27.0,
   "warehouse": "Lucknow"
  }
 ],
 "defaulted_to_latest": true,
 "format": "BIG BASKET",
 "max_po_date": "10-07-2026",
 "min_po_date": "03-07-2026",
 "platform": "bigbasket",
 "po_month": "JULY",
 "totals": {
  "open_ltrs": 5721.0,
  "open_pos": 9,
  "open_units": 6420.0,
  "pending_ltrs": 5721.0,
  "pending_units": 6420.0,
  "rows": 95
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - bigbasket]]
