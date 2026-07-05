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
   "open_ltrs": 1648.0,
   "open_pos": 1,
   "open_units": 1612.0,
   "order_value": 289099.76,
   "pending_ltrs": 1648.0,
   "pending_units": 1612.0
  },
  {
   "city": "NOIDA",
   "open_ltrs": 1488.0,
   "open_pos": 1,
   "open_units": 1435.0,
   "order_value": 274700.3,
   "pending_ltrs": 1488.0,
   "pending_units": 1435.0
  },
  {
   "city": "KOLKATA",
   "open_ltrs": 100.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 29732.72,
   "pending_ltrs": 100.0,
   "pending_units": 84.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 3136.0,
   "open_pos": 2,
   "open_units": 3047.0,
   "order_value": 563800.06,
   "pending_ltrs": 3136.0,
   "pending_units": 3047.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 100.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 29732.72,
   "pending_ltrs": 100.0,
   "pending_units": 84.0
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
   "distributor": "BABA LOKENATH TRADERS",
   "location": "Kolkata",
   "open_ltrs": 100.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 29732.72,
   "pending_ltrs": 100.0,
   "pending_units": 84.0,
   "po_date": "03-07-2026",
   "po_expiry_date": "18-07-2026",
   "po_number": "IRA40365361"
  }
 ],
 "by_sku": [
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 1100.0,
   "open_pos": 2,
   "open_units": 1100.0,
   "order_value": 157132.0,
   "pending_ltrs": 1100.0,
   "pending_units": 1100.0,
   "sku_code": "40249993",
   "sku_name": "Jivo Cold Pressed Sunflower Oil 1 L Bottle"
  },
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 816.0,
   "open_pos": 2,
   "open_units": 816.0,
   "order_value": 133662.56,
   "pending_ltrs": 816.0,
   "pending_units": 816.0,
   "sku_code": "40166395",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 1 L Bottle"
  },
  {
   "item": "SUNFLOWER 5L",
   "open_ltrs": 400.0,
   "open_pos": 1,
   "open_units": 80.0,
   "order_value": 56762.4,
   "pending_ltrs": 400.0,
   "pending_units": 80.0,
   "sku_code": "40249992",
   "sku_name": "Jivo Sunflower Oil - Cold Pressed, Fortified With Vitamins A & D, Chemical Free 5 L Jar"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 284.0,
   "open_pos": 3,
   "open_units": 284.0,
   "order_value": 62201.76,
   "pending_ltrs": 284.0,
   "pending_units": 284.0,
   "sku_code": "282779",
   "sku_name": "Jivo Canola Oil - Cold Pressed 1 L"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 260.0,
   "open_pos": 2,
   "open_units": 52.0,
   "order_value": 41352.48,
   "pending_ltrs": 260.0,
   "pending_units": 52.0,
   "sku_code": "40166396",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 5 L Bottle"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 112.0,
   "open_pos": 3,
   "open_units": 112.0,
   "order_value": 39649.28,
   "pending_ltrs": 112.0,
   "pending_units": 112.0,
   "sku_code": "40197820",
   "sku_name": "Jivo Pomace Olive Oil 1 L"
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
   "open_ltrs": 56.0,
   "open_pos": 2,
   "open_units": 56.0,
   "order_value": 28736.4,
   "pending_ltrs": 56.0,
   "pending_units": 56.0,
   "sku_code": "40166398",
   "sku_name": "Jivo Extra Light Olive Oil 1 L Bottle"
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
   "item": "CANOLA 5L",
   "open_ltrs": 40.0,
   "open_pos": 2,
   "open_units": 8.0,
   "order_value": 8571.36,
   "pending_ltrs": 40.0,
   "pending_units": 8.0,
   "sku_code": "282780",
   "sku_name": "Jivo Canola Oil - Cold Pressed 5 L Bottle"
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
   "item": "WG APPLE JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 2719.92,
   "pending_ltrs": 0.0,
   "pending_units": 84.0,
   "sku_code": "40335334",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "LEMON 750ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 72.0,
   "order_value": 2098.08,
   "pending_ltrs": 0.0,
   "pending_units": 72.0,
   "sku_code": "40335332",
   "sku_name": "Jivo Fizzy Water Flavoured With Lemon 750 ml"
  },
  {
   "item": "WATER PEACH 750ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 60.0,
   "order_value": 1748.4,
   "pending_ltrs": 0.0,
   "pending_units": 60.0,
   "sku_code": "40335333",
   "sku_name": "Jivo Fizzy Water Flavoured With Peach 750 ml"
  },
  {
   "item": "WG MANGO JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 48.0,
   "order_value": 1553.76,
   "pending_ltrs": 0.0,
   "pending_units": 48.0,
   "sku_code": "40335336",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MOJITO SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 2,
   "open_units": 48.0,
   "order_value": 1796.28,
   "pending_ltrs": 0.0,
   "pending_units": 48.0,
   "sku_code": "40335331",
   "sku_name": "Jivo Mojito Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG BLUEBERRY JUICE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 2,
   "open_units": 48.0,
   "order_value": 1554.36,
   "pending_ltrs": 0.0,
   "pending_units": 48.0,
   "sku_code": "40335335",
   "sku_name": "Jivo Blueberry Healthy Wheatgrass Juice 200 ml"
  },
  {
   "item": "WG MANGO JUICE 500ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 36.0,
   "order_value": 2486.88,
   "pending_ltrs": 0.0,
   "pending_units": 36.0,
   "sku_code": "40335340",
   "sku_name": "Jivo Mango Healthy Wheatgrass Juice 500 ml"
  },
  {
   "item": "WG APPLE JUICE SF 200ML",
   "open_ltrs": 0.0,
   "open_pos": 2,
   "open_units": 31.0,
   "order_value": 1003.78,
   "pending_ltrs": 0.0,
   "pending_units": 31.0,
   "sku_code": "40335329",
   "sku_name": "Jivo Apple Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "TONIC WATER 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 24.0,
   "order_value": 1107.36,
   "pending_ltrs": 0.0,
   "pending_units": 24.0,
   "sku_code": "40335339",
   "sku_name": "Jivo Indian Tonic Water 200 ml"
  },
  {
   "item": "WG GINGER ALE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 22.0,
   "order_value": 712.36,
   "pending_ltrs": 0.0,
   "pending_units": 22.0,
   "sku_code": "40335330",
   "sku_name": "Jivo Ginger Ale Healthy Wheatgrass Juice - Sugar Free 200 ml"
  },
  {
   "item": "WG ROSE 200ML",
   "open_ltrs": 0.0,
   "open_pos": 1,
   "open_units": 12.0,
   "order_value": 388.56,
   "pending_ltrs": 0.0,
   "pending_units": 12.0,
   "sku_code": "40335338",
   "sku_name": "Jivo Rose Healthy Wheatgrass Juice 200 ml"
  }
 ],
 "by_warehouse": [
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
   "open_ltrs": 1488.0,
   "open_pos": 1,
   "open_units": 1435.0,
   "order_value": 274700.3,
   "pending_ltrs": 1488.0,
   "pending_units": 1435.0,
   "warehouse": "Noida"
  },
  {
   "open_ltrs": 100.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 29732.72,
   "pending_ltrs": 100.0,
   "pending_units": 84.0,
   "warehouse": "Kolkata"
  }
 ],
 "defaulted_to_latest": true,
 "format": "BIG BASKET",
 "max_po_date": "04-07-2026",
 "min_po_date": "03-07-2026",
 "platform": "bigbasket",
 "po_month": "JULY",
 "totals": {
  "open_ltrs": 3236.0,
  "open_pos": 3,
  "open_units": 3131.0,
  "pending_ltrs": 3236.0,
  "pending_units": 3131.0,
  "rows": 35
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - bigbasket]]
