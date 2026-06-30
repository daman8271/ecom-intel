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
   "open_pos": 10,
   "open_units": 1084.0,
   "order_value": 243540.44,
   "pending_ltrs": 1084.0,
   "pending_units": 1084.0
  },
  {
   "city": "Guwahati G1 - Feeder Warehouse",
   "open_ltrs": 160.0,
   "open_pos": 3,
   "open_units": 80.0,
   "order_value": 73143.2,
   "pending_ltrs": 160.0,
   "pending_units": 80.0
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
   "city": "Bhubaneswar B1 - Feeder Warehouse",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0
  },
  {
   "city": "NOIDA",
   "open_ltrs": 60.0,
   "open_pos": 2,
   "open_units": 12.0,
   "order_value": 14742.8,
   "pending_ltrs": 60.0,
   "pending_units": 12.0
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
  }
 ],
 "by_distributor": [
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "open_ltrs": 1132.0,
   "open_pos": 11,
   "open_units": 1132.0,
   "order_value": 259083.32,
   "pending_ltrs": 1132.0,
   "pending_units": 1132.0
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "open_ltrs": 328.0,
   "open_pos": 5,
   "open_units": 218.0,
   "order_value": 128343.38,
   "pending_ltrs": 328.0,
   "pending_units": 218.0
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
   "distributor": "ANTIZE FOODS PVT LTD",
   "open_ltrs": 60.0,
   "open_pos": 2,
   "open_units": 12.0,
   "order_value": 14742.8,
   "pending_ltrs": 60.0,
   "pending_units": 12.0
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 10.0,
   "order_value": 9142.9,
   "pending_ltrs": 20.0,
   "pending_units": 10.0
  }
 ],
 "by_po": [
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M11 - Feeder Warehouse",
   "open_ltrs": 148.0,
   "open_pos": 1,
   "open_units": 148.0,
   "order_value": 33409.28,
   "pending_ltrs": 148.0,
   "pending_units": 148.0,
   "po_date": "27-06-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "5625710042078"
  },
  {
   "distributor": "KNOWTABLE ONLINE SERVICES PRIVATE LIMITED",
   "location": "Visakhapatnam V1 - Feeder Warehouse",
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
   "location": "Mumbai M11 - Feeder Warehouse",
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
   "location": "Mumbai M10 - Feeder Warehouse",
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
   "location": "Mumbai M10 - Feeder Warehouse",
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
   "location": "Mumbai M11 - Feeder Warehouse",
   "open_ltrs": 116.0,
   "open_pos": 1,
   "open_units": 116.0,
   "order_value": 22209.16,
   "pending_ltrs": 116.0,
   "pending_units": 116.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "05-07-2026",
   "po_number": "5625710041864"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M11 - Feeder Warehouse",
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
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M12 - Feeder Warehouse",
   "open_ltrs": 116.0,
   "open_pos": 1,
   "open_units": 116.0,
   "order_value": 23047.36,
   "pending_ltrs": 116.0,
   "pending_units": 116.0,
   "po_date": "27-06-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "50033210016175"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "location": "Faridabad - Feeder Warehouse",
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
   "location": "Mumbai M10 - Feeder Warehouse",
   "open_ltrs": 84.0,
   "open_pos": 1,
   "open_units": 84.0,
   "order_value": 23961.84,
   "pending_ltrs": 84.0,
   "pending_units": 84.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "05-07-2026",
   "po_number": "2273910082558"
  },
  {
   "distributor": "CHIRAG ENTERPRISES MUMBAI",
   "location": "Mumbai M11 - Feeder Warehouse",
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
   "location": "Guwahati G1 - Feeder Warehouse",
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "7165810023727"
  },
  {
   "distributor": "JIVO MART PRIVATE LIMITED",
   "location": "Bhubaneswar B1 - Feeder Warehouse",
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
   "location": "Guwahati G1 - Feeder Warehouse",
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
   "location": "Mumbai M11 - Feeder Warehouse",
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
   "location": "Goa G2 - Feeder Warehouse",
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
   "location": "Guwahati G1 - Feeder Warehouse",
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
   "distributor": "ANTIZE FOODS PVT LTD",
   "location": "Noida N1 - Feeder Warehouse",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 8.0,
   "order_value": 10895.2,
   "pending_ltrs": 40.0,
   "pending_units": 8.0,
   "po_date": "26-06-2026",
   "po_expiry_date": "01-07-2026",
   "po_number": "2867410073475"
  },
  {
   "distributor": "BABA LOKENATH TRADERS",
   "location": "Kolkata K6 - Feeder Warehouse",
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
   "location": "Noida N1 - Feeder Warehouse",
   "open_ltrs": 20.0,
   "open_pos": 1,
   "open_units": 4.0,
   "order_value": 3847.6,
   "pending_ltrs": 20.0,
   "pending_units": 4.0,
   "po_date": "27-06-2026",
   "po_expiry_date": "02-07-2026",
   "po_number": "2867410073967"
  }
 ],
 "by_sku": [
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 560.0,
   "open_pos": 8,
   "open_units": 560.0,
   "order_value": 90664.0,
   "pending_ltrs": 560.0,
   "pending_units": 560.0,
   "sku_code": "10201963",
   "sku_name": "Jivo Cold Pressed Sunflower Oil(Bottle)"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 480.0,
   "open_pos": 10,
   "open_units": 480.0,
   "order_value": 155428.8,
   "pending_ltrs": 480.0,
   "pending_units": 480.0,
   "sku_code": "10143020",
   "sku_name": "Jivo Pomace Olive Oil(Bottle)"
  },
  {
   "item": "EXTRA LIGHT 2L",
   "open_ltrs": 380.0,
   "open_pos": 6,
   "open_units": 190.0,
   "order_value": 173715.1,
   "pending_ltrs": 380.0,
   "pending_units": 190.0,
   "sku_code": "10153585",
   "sku_name": "Jivo Extra Light Olive Oil"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 200.0,
   "open_pos": 6,
   "open_units": 200.0,
   "order_value": 40762.0,
   "pending_ltrs": 200.0,
   "pending_units": 200.0,
   "sku_code": "10049199",
   "sku_name": "Jivo Cold Pressed Canola Oil(Pack)"
  },
  {
   "item": "CANOLA 5L",
   "open_ltrs": 40.0,
   "open_pos": 2,
   "open_units": 8.0,
   "order_value": 7695.2,
   "pending_ltrs": 40.0,
   "pending_units": 8.0,
   "sku_code": "10048295",
   "sku_name": "Jivo Cold Pressed Canola Oil (5 l)(Pack)"
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
   "open_ltrs": 644.0,
   "open_pos": 6,
   "open_units": 644.0,
   "order_value": 157675.24,
   "pending_ltrs": 644.0,
   "pending_units": 644.0,
   "warehouse": "Mumbai M11 - Feeder Warehouse"
  },
  {
   "open_ltrs": 324.0,
   "open_pos": 3,
   "open_units": 324.0,
   "order_value": 62817.84,
   "pending_ltrs": 324.0,
   "pending_units": 324.0,
   "warehouse": "Mumbai M10 - Feeder Warehouse"
  },
  {
   "open_ltrs": 160.0,
   "open_pos": 3,
   "open_units": 80.0,
   "order_value": 73143.2,
   "pending_ltrs": 160.0,
   "pending_units": 80.0,
   "warehouse": "Guwahati G1 - Feeder Warehouse"
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
   "open_ltrs": 116.0,
   "open_pos": 1,
   "open_units": 116.0,
   "order_value": 23047.36,
   "pending_ltrs": 116.0,
   "pending_units": 116.0,
   "warehouse": "Mumbai M12 - Feeder Warehouse"
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
   "open_ltrs": 60.0,
   "open_pos": 1,
   "open_units": 30.0,
   "order_value": 27428.7,
   "pending_ltrs": 60.0,
   "pending_units": 30.0,
   "warehouse": "Bhubaneswar B1 - Feeder Warehouse"
  },
  {
   "open_ltrs": 60.0,
   "open_pos": 2,
   "open_units": 12.0,
   "order_value": 14742.8,
   "pending_ltrs": 60.0,
   "pending_units": 12.0,
   "warehouse": "Noida N1 - Feeder Warehouse"
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
  }
 ],
 "defaulted_to_latest": true,
 "format": "BLINKIT",
 "max_po_date": "27-06-2026",
 "min_po_date": "15-06-2026",
 "platform": "blinkit",
 "po_month": "JUNE",
 "totals": {
  "open_ltrs": 1680.0,
  "open_pos": 20,
  "open_units": 1442.0,
  "pending_ltrs": 1680.0,
  "pending_units": 1442.0,
  "rows": 33
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - blinkit]]
