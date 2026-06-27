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
   "city": "MUMBAI",
   "open_ltrs": 1084.0,
   "open_pos": 8,
   "open_units": 1084.0,
   "order_value": 228911.24,
   "pending_ltrs": 1084.0,
   "pending_units": 1084.0
  },
  {
   "city": "Visakhapatnam V1 - Feeder Warehouse",
   "open_ltrs": 140.0,
   "open_pos": 1,
   "open_units": 70.0,
   "order_value": 64000.3,
   "pending_ltrs": 140.0,
   "pending_units": 70.0
  },
  {
   "city": "Faridabad - Feeder Warehouse",
   "open_ltrs": 108.0,
   "open_pos": 1,
   "open_units": 108.0,
   "order_value": 27771.48,
   "pending_ltrs": 108.0,
   "pending_units": 108.0
  },
  {
   "city": "Guwahati G1 - Feeder Warehouse",
   "open_ltrs": 100.0,
   "open_pos": 2,
   "open_units": 50.0,
   "order_value": 45714.5,
   "pending_ltrs": 100.0,
   "pending_units": 50.0
  },
  {
   "city": "Bhubaneswar B1 - Feeder Warehouse",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0
  },
  {
   "city": "Goa G2 - Feeder Warehouse",
   "open_ltrs": 48.0,
   "open_pos": 1,
   "open_units": 48.0,
   "order_value": 15542.88,
   "pending_ltrs": 48.0,
   "pending_units": 48.0
  },
  {
   "city": "KOLKATA",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 9142.9,
   "pending_ltrs": 20.0,
   "pending_units": 10.0
  },
  {
   "city": "NOIDA",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 7047.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 1132.0,
   "open_pos": 9,
   "open_units": 1132.0,
   "order_value": 244454.12,
   "pending_ltrs": 1132.0,
   "pending_units": 1132.0
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 268.0,
   "open_pos": 4,
   "open_units": 188.0,
   "order_value": 100914.68,
   "pending_ltrs": 268.0,
   "pending_units": 188.0
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "open_ltrs": 140.0,
   "open_pos": 1,
   "open_units": 70.0,
   "order_value": 64000.3,
   "pending_ltrs": 140.0,
   "pending_units": 70.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 9142.9,
   "pending_ltrs": 20.0,
   "pending_units": 10.0
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 7047.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0
  }
 ],
 "by_po": [
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 376.0,
   "open_pos": 1,
   "open_units": 376.0,
   "order_value": 64303.16,
   "pending_ltrs": 376.0,
   "pending_units": 376.0,
   "po_date": "19-06-2026",
   "po_expiry_date": "28-06-2026",
   "po_number": "5625710039537"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "open_ltrs": 140.0,
   "open_pos": 1,
   "open_units": 70.0,
   "order_value": 64000.3,
   "pending_ltrs": 140.0,
   "pending_units": 70.0,
   "po_date": "16-06-2026",
   "po_expiry_date": "23-06-2026",
   "po_number": "2888510031122"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 128.0,
   "open_pos": 1,
   "open_units": 128.0,
   "order_value": 41447.68,
   "pending_ltrs": 128.0,
   "pending_units": 128.0,
   "po_date": "25-06-2026",
   "po_expiry_date": "04-07-2026",
   "po_number": "5625710041491"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 120.0,
   "order_value": 19428.0,
   "pending_ltrs": 120.0,
   "pending_units": 120.0,
   "po_date": "20-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "2273910081123"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 120.0,
   "open_pos": 1,
   "open_units": 120.0,
   "order_value": 19428.0,
   "pending_ltrs": 120.0,
   "pending_units": 120.0,
   "po_date": "22-06-2026",
   "po_expiry_date": "01-07-2026",
   "po_number": "2273910081597"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 116.0,
   "open_pos": 1,
   "open_units": 116.0,
   "order_value": 22209.16,
   "pending_ltrs": 116.0,
   "pending_units": 116.0,
   "po_date": "22-06-2026",
   "po_expiry_date": "01-07-2026",
   "po_number": "5625710040406"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 108.0,
   "open_pos": 1,
   "open_units": 108.0,
   "order_value": 27771.48,
   "pending_ltrs": 108.0,
   "pending_units": 108.0,
   "po_date": "16-06-2026",
   "po_expiry_date": "24-06-2026",
   "po_number": "49060410042778"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 88.0,
   "open_pos": 1,
   "open_units": 88.0,
   "order_value": 23695.28,
   "pending_ltrs": 88.0,
   "pending_units": 88.0,
   "po_date": "20-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "5625710039905"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 80.0,
   "open_pos": 1,
   "open_units": 80.0,
   "order_value": 25904.8,
   "pending_ltrs": 80.0,
   "pending_units": 80.0,
   "po_date": "15-06-2026",
   "po_expiry_date": "24-06-2026",
   "po_number": "5625710037905"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "03-07-2026",
   "po_number": "5407610018340"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0,
   "po_date": "15-06-2026",
   "po_expiry_date": "25-06-2026",
   "po_number": "7165810021548"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 56.0,
   "open_pos": 1,
   "open_units": 56.0,
   "order_value": 12495.16,
   "pending_ltrs": 56.0,
   "pending_units": 56.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "02-07-2026",
   "po_number": "5625710040791"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 48.0,
   "open_pos": 1,
   "open_units": 48.0,
   "order_value": 15542.88,
   "pending_ltrs": 48.0,
   "pending_units": 48.0,
   "po_date": "20-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "41315210028152"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 20.0,
   "order_value": 18285.8,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "03-07-2026",
   "po_number": "7165810023081"
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 9142.9,
   "pending_ltrs": 20.0,
   "pending_units": 10.0,
   "po_date": "17-06-2026",
   "po_expiry_date": "23-06-2026",
   "po_number": "48287510033707"
  },
  {
   "distributor": "ANTIZE FOODS PVT LTD",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 7047.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0,
   "po_date": "23-06-2026",
   "po_expiry_date": "28-06-2026",
   "po_number": "2867410072330"
  }
 ],
 "by_sku": [
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 680.0,
   "open_pos": 5,
   "open_units": 680.0,
   "order_value": 110092.0,
   "pending_ltrs": 680.0,
   "pending_units": 680.0,
   "sku_code": "10201963",
   "sku_name": "Jivo Cold Pressed Sunflower Oil(Bottle)"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 400.0,
   "open_pos": 8,
   "open_units": 400.0,
   "order_value": 129524.0,
   "pending_ltrs": 400.0,
   "pending_units": 400.0,
   "sku_code": "10143020",
   "sku_name": "Jivo Pomace Olive Oil(Bottle)"
  },
  {
   "item": "EXTRA LIGHT 2L",
   "open_ltrs": 320.0,
   "open_pos": 5,
   "open_units": 160.0,
   "order_value": 146286.4,
   "pending_ltrs": 320.0,
   "pending_units": 160.0,
   "sku_code": "10153585",
   "sku_name": "Jivo Extra Light Olive Oil"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 160.0,
   "open_pos": 5,
   "open_units": 160.0,
   "order_value": 32609.6,
   "pending_ltrs": 160.0,
   "pending_units": 160.0,
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
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 844.0,
   "open_pos": 6,
   "open_units": 844.0,
   "order_value": 190055.24,
   "pending_ltrs": 844.0,
   "pending_units": 844.0,
   "warehouse": "Mumbai M11 - Feeder Warehouse"
  },
  {
   "open_ltrs": 240.0,
   "open_pos": 2,
   "open_units": 240.0,
   "order_value": 38856.0,
   "pending_ltrs": 240.0,
   "pending_units": 240.0,
   "warehouse": "Mumbai M10 - Feeder Warehouse"
  },
  {
   "open_ltrs": 140.0,
   "open_pos": 1,
   "open_units": 70.0,
   "order_value": 64000.3,
   "pending_ltrs": 140.0,
   "pending_units": 70.0,
   "warehouse": "Visakhapatnam V1 - Feeder Warehouse"
  },
  {
   "open_ltrs": 108.0,
   "open_pos": 1,
   "open_units": 108.0,
   "order_value": 27771.48,
   "pending_ltrs": 108.0,
   "pending_units": 108.0,
   "warehouse": "Faridabad - Feeder Warehouse"
  },
  {
   "open_ltrs": 100.0,
   "open_pos": 2,
   "open_units": 50.0,
   "order_value": 45714.5,
   "pending_ltrs": 100.0,
   "pending_units": 50.0,
   "warehouse": "Guwahati G1 - Feeder Warehouse"
  },
  {
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0,
   "warehouse": "Bhubaneswar B1 - Feeder Warehouse"
  },
  {
   "open_ltrs": 48.0,
   "open_pos": 1,
   "open_units": 48.0,
   "order_value": 15542.88,
   "pending_ltrs": 48.0,
   "pending_units": 48.0,
   "warehouse": "Goa G2 - Feeder Warehouse"
  },
  {
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 9142.9,
   "pending_ltrs": 20.0,
   "pending_units": 10.0,
   "warehouse": "Kolkata K6 - Feeder Warehouse"
  },
  {
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 7047.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0,
   "warehouse": "Noida N1 - Feeder Warehouse"
  }
 ],
 "defaulted_to_latest": true,
 "format": "BLINKIT",
 "max_po_date": "25-06-2026",
 "min_po_date": "15-06-2026",
 "platform": "blinkit",
 "po_month": "JUNE",
 "totals": {
  "open_ltrs": 1580.0,
  "open_pos": 16,
  "open_units": 1404.0,
  "pending_ltrs": 1580.0,
  "pending_units": 1404.0,
  "rows": 24
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - blinkit]]
