---
type: app-dashboard
endpoint_key: pendency__blinkit
source: app-dashboard
month: ""
platform: blinkit
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/blinkit
---

# App dashboard — `pendency__blinkit`

Up: [[dashboards-index]] · [[pf-blinkit]]

> **source: app-dashboard `pendency__blinkit`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "by_city": [
  {
   "city": "LUDHIANA",
   "open_ltrs": 576.0,
   "open_pos": 1,
   "open_units": 576.0,
   "order_value": 102267.16,
   "pending_ltrs": 576.0,
   "pending_units": 576.0
  },
  {
   "city": "RAJPURA",
   "open_ltrs": 520.0,
   "open_pos": 1,
   "open_units": 520.0,
   "order_value": 77410.0,
   "pending_ltrs": 520.0,
   "pending_units": 520.0
  },
  {
   "city": "MUMBAI",
   "open_ltrs": 244.0,
   "open_pos": 3,
   "open_units": 244.0,
   "order_value": 49865.84,
   "pending_ltrs": 244.0,
   "pending_units": 244.0
  },
  {
   "city": "PUNE",
   "open_ltrs": 64.0,
   "open_pos": 1,
   "open_units": 64.0,
   "order_value": 20723.84,
   "pending_ltrs": 64.0,
   "pending_units": 64.0
  },
  {
   "city": "DASNA",
   "open_ltrs": 52.0,
   "open_pos": 1,
   "open_units": 52.0,
   "order_value": 14118.08,
   "pending_ltrs": 52.0,
   "pending_units": 52.0
  },
  {
   "city": "NOIDA",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 8.0,
   "order_value": 10895.2,
   "pending_ltrs": 40.0,
   "pending_units": 8.0
  },
  {
   "city": "Kundli - Feeder Warehouse",
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0
  },
  {
   "city": "Dehradun - Feeder Warehouse",
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "EVARA ENTERPRISES",
   "open_ltrs": 1096.0,
   "open_pos": 2,
   "open_units": 1096.0,
   "order_value": 179677.16,
   "pending_ltrs": 1096.0,
   "pending_units": 1096.0
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 308.0,
   "open_pos": 4,
   "open_units": 308.0,
   "order_value": 70589.68,
   "pending_ltrs": 308.0,
   "pending_units": 308.0
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "open_ltrs": 124.0,
   "open_pos": 4,
   "open_units": 92.0,
   "order_value": 35375.2,
   "pending_ltrs": 124.0,
   "pending_units": 92.0
  }
 ],
 "by_po": [
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Ludhiana L2 - Feeder Warehouse",
   "open_ltrs": 576.0,
   "open_pos": 1,
   "open_units": 576.0,
   "order_value": 102267.16,
   "pending_ltrs": 576.0,
   "pending_units": 576.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "3226810033223"
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Rajpura R2 - Feeder Warehouse",
   "open_ltrs": 520.0,
   "open_pos": 1,
   "open_units": 520.0,
   "order_value": 77410.0,
   "pending_ltrs": 520.0,
   "pending_units": 520.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "43886010050702"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M12 - Feeder Warehouse",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 120.0,
   "order_value": 19428.0,
   "pending_ltrs": 120.0,
   "pending_units": 120.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "10-07-2026",
   "po_number": "50033210018046"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Pune P2 - Feeder Warehouse",
   "open_ltrs": 64.0,
   "open_pos": 1,
   "open_units": 64.0,
   "order_value": 20723.84,
   "pending_ltrs": 64.0,
   "pending_units": 64.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "10-07-2026",
   "po_number": "1723710045924"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M10 - Feeder Warehouse",
   "open_ltrs": 64.0,
   "open_pos": 1,
   "open_units": 64.0,
   "order_value": 20723.84,
   "pending_ltrs": 64.0,
   "pending_units": 64.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "10-07-2026",
   "po_number": "2273910083898"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M11 - Feeder Warehouse",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 60.0,
   "order_value": 9714.0,
   "pending_ltrs": 60.0,
   "pending_units": 60.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "10-07-2026",
   "po_number": "5625710043284"
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "location": "Super Store Dasna 2 - Warehouse",
   "open_ltrs": 52.0,
   "open_pos": 1,
   "open_units": 52.0,
   "order_value": 14118.08,
   "pending_ltrs": 52.0,
   "pending_units": 52.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "11-07-2026",
   "po_number": "1724010038981"
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "location": "Noida N1 - Feeder Warehouse",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 8.0,
   "order_value": 10895.2,
   "pending_ltrs": 40.0,
   "pending_units": 8.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "2867410075688"
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "location": "Dehradun - Feeder Warehouse",
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "08-07-2026",
   "po_number": "2173110031258"
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "location": "Kundli - Feeder Warehouse",
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0,
   "po_date": "01-07-2026",
   "po_expiry_date": "07-07-2026",
   "po_number": "2011710071664"
  }
 ],
 "by_sku": [
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 940.0,
   "open_pos": 2,
   "open_units": 940.0,
   "order_value": 138762.8,
   "pending_ltrs": 940.0,
   "pending_units": 940.0,
   "sku_code": "10150509",
   "sku_name": "Jivo Kachi Ghani Cold Pressed Mustard Oil(PET Bottle)"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 256.0,
   "open_pos": 5,
   "open_units": 256.0,
   "order_value": 82895.36,
   "pending_ltrs": 256.0,
   "pending_units": 256.0,
   "sku_code": "10143020",
   "sku_name": "Jivo Pomace Olive Oil(Bottle)"
  },
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 240.0,
   "open_pos": 4,
   "open_units": 240.0,
   "order_value": 38970.6,
   "pending_ltrs": 240.0,
   "pending_units": 240.0,
   "sku_code": "10201963",
   "sku_name": "Jivo Cold Pressed Sunflower Oil(Bottle)"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 40.0,
   "order_value": 8152.4,
   "pending_ltrs": 40.0,
   "pending_units": 40.0,
   "sku_code": "10049199",
   "sku_name": "Jivo Cold Pressed Canola Oil(Pack)"
  },
  {
   "item": "JIVO POMACE 5L",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 7047.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0,
   "sku_code": "10049041",
   "sku_name": "Jivo Pomace Olive Oil(Tin)"
  },
  {
   "item": "CANOLA 5L",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 3847.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0,
   "sku_code": "10048295",
   "sku_name": "Jivo Cold Pressed Canola Oil (5 l)(Pack)"
  },
  {
   "item": "EXTRA LIGHT 1L",
   "open_ltrs": 12.0,
   "open_pos": 1,
   "open_units": 12.0,
   "order_value": 5965.68,
   "pending_ltrs": 12.0,
   "pending_units": 12.0,
   "sku_code": "10048294",
   "sku_name": "Jivo Extra Light Olive Oil(Pack)"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 576.0,
   "open_pos": 1,
   "open_units": 576.0,
   "order_value": 102267.16,
   "pending_ltrs": 576.0,
   "pending_units": 576.0,
   "warehouse": "Ludhiana L2 - Feeder Warehouse"
  },
  {
   "open_ltrs": 520.0,
   "open_pos": 1,
   "open_units": 520.0,
   "order_value": 77410.0,
   "pending_ltrs": 520.0,
   "pending_units": 520.0,
   "warehouse": "Rajpura R2 - Feeder Warehouse"
  },
  {
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 120.0,
   "order_value": 19428.0,
   "pending_ltrs": 120.0,
   "pending_units": 120.0,
   "warehouse": "Mumbai M12 - Feeder Warehouse"
  },
  {
   "open_ltrs": 64.0,
   "open_pos": 1,
   "open_units": 64.0,
   "order_value": 20723.84,
   "pending_ltrs": 64.0,
   "pending_units": 64.0,
   "warehouse": "Pune P2 - Feeder Warehouse"
  },
  {
   "open_ltrs": 64.0,
   "open_pos": 1,
   "open_units": 64.0,
   "order_value": 20723.84,
   "pending_ltrs": 64.0,
   "pending_units": 64.0,
   "warehouse": "Mumbai M10 - Feeder Warehouse"
  },
  {
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 60.0,
   "order_value": 9714.0,
   "pending_ltrs": 60.0,
   "pending_units": 60.0,
   "warehouse": "Mumbai M11 - Feeder Warehouse"
  },
  {
   "open_ltrs": 52.0,
   "open_pos": 1,
   "open_units": 52.0,
   "order_value": 14118.08,
   "pending_ltrs": 52.0,
   "pending_units": 52.0,
   "warehouse": "Super Store Dasna 2 - Warehouse"
  },
  {
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 8.0,
   "order_value": 10895.2,
   "pending_ltrs": 40.0,
   "pending_units": 8.0,
   "warehouse": "Noida N1 - Feeder Warehouse"
  },
  {
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0,
   "warehouse": "Kundli - Feeder Warehouse"
  },
  {
   "open_ltrs": 16.0,
   "open_pos": 1,
   "open_units": 16.0,
   "order_value": 5180.96,
   "pending_ltrs": 16.0,
   "pending_units": 16.0,
   "warehouse": "Dehradun - Feeder Warehouse"
  }
 ],
 "defaulted_to_latest": true,
 "format": "BLINKIT",
 "max_po_date": "01-07-2026",
 "min_po_date": "01-07-2026",
 "platform": "blinkit",
 "po_month": "JULY",
 "totals": {
  "open_ltrs": 1528.0,
  "open_pos": 10,
  "open_units": 1496.0,
  "pending_ltrs": 1528.0,
  "pending_units": 1496.0,
  "rows": 15
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - blinkit]]
