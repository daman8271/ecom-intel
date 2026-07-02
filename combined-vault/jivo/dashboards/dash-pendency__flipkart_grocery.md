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
   "open_ltrs": 3184.0,
   "open_pos": 3,
   "open_units": 2780.0,
   "order_value": 565872.380952381,
   "pending_ltrs": 3184.0,
   "pending_units": 2780.0
  },
  {
   "city": "LUCKNOW",
   "open_ltrs": 1680.0,
   "open_pos": 1,
   "open_units": 1680.0,
   "order_value": 252952.38095238095,
   "pending_ltrs": 1680.0,
   "pending_units": 1680.0
  },
  {
   "city": "LUDHIANA",
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 85904.76190476191,
   "pending_ltrs": 540.0,
   "pending_units": 540.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 4864.0,
   "open_pos": 4,
   "open_units": 4460.0,
   "order_value": 818824.7619047619,
   "pending_ltrs": 4864.0,
   "pending_units": 4460.0
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 85904.76190476191,
   "pending_ltrs": 540.0,
   "pending_units": 540.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 2020.0,
   "open_pos": 1,
   "open_units": 2020.0,
   "order_value": 298190.4761904762,
   "pending_ltrs": 2020.0,
   "pending_units": 2020.0,
   "po_date": "19-06-2026",
   "po_expiry_date": "06-07-2026",
   "po_number": "FBSWN08321049"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Lucknow",
   "open_ltrs": 1680.0,
   "open_pos": 1,
   "open_units": 1680.0,
   "order_value": 252952.38095238095,
   "pending_ltrs": 1680.0,
   "pending_units": 1680.0,
   "po_date": "29-06-2026",
   "po_expiry_date": "09-07-2026",
   "po_number": "FLGWN08356201"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 1124.0,
   "open_pos": 1,
   "open_units": 740.0,
   "order_value": 230361.90476190476,
   "pending_ltrs": 1124.0,
   "pending_units": 740.0,
   "po_date": "29-06-2026",
   "po_expiry_date": "13-07-2026",
   "po_number": "FBSWN08356115"
  },
  {
   "distributor": "EVARA ENTERPRISES",
   "location": "Ludhiana",
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 85904.76190476191,
   "pending_ltrs": 540.0,
   "pending_units": 540.0,
   "po_date": "30-06-2026",
   "po_expiry_date": "10-07-2026",
   "po_number": "FLGWN08361536"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Manesar",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 20.0,
   "order_value": 37319.99999999999,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "po_date": "29-06-2026",
   "po_expiry_date": "13-07-2026",
   "po_number": "FBSWN08356120"
  }
 ],
 "by_sku": [
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 4180.0,
   "open_pos": 4,
   "open_units": 4180.0,
   "order_value": 617047.619047619,
   "pending_ltrs": 4180.0,
   "pending_units": 4180.0,
   "sku_code": "EDOGDVWYGJNDYRQP",
   "sku_name": "JIVO Cold Pressed Pure Cooking (Pack of 1) Mustard Oil 1 L Plastic Bottle"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 480.0,
   "open_pos": 3,
   "open_units": 480.0,
   "order_value": 100571.42857142857,
   "pending_ltrs": 480.0,
   "pending_units": 480.0,
   "sku_code": "EDOG9BP8GEWFW9XC",
   "sku_name": "JIVO Cold Press Canola Oil 1 L Plastic Bottle"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 480.0,
   "open_pos": 1,
   "open_units": 96.0,
   "order_value": 70857.14285714286,
   "pending_ltrs": 480.0,
   "pending_units": 96.0,
   "sku_code": "EDOGDVWEUPPWVGED",
   "sku_name": "JIVO Cold Pressed Pure Cooking Mustard Oil 5 L Can"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 224.0,
   "open_pos": 1,
   "open_units": 224.0,
   "order_value": 78933.33333333333,
   "pending_ltrs": 224.0,
   "pending_units": 224.0,
   "sku_code": "EDOFTHNH4YZ7GDHS",
   "sku_name": "JIVO Pomace Olive Oil 1 L Plastic Bottle"
  },
  {
   "item": "EXTRA LIGHT 2L",
   "open_ltrs": 40.0,
   "open_pos": 1,
   "open_units": 20.0,
   "order_value": 37319.99999999999,
   "pending_ltrs": 40.0,
   "pending_units": 20.0,
   "sku_code": "EDOGHZTJZEYQJGME",
   "sku_name": "JIVO Extra Light Olive Oil 2 L Can"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 3184.0,
   "open_pos": 3,
   "open_units": 2780.0,
   "order_value": 565872.380952381,
   "pending_ltrs": 3184.0,
   "pending_units": 2780.0,
   "warehouse": "Manesar"
  },
  {
   "open_ltrs": 1680.0,
   "open_pos": 1,
   "open_units": 1680.0,
   "order_value": 252952.38095238095,
   "pending_ltrs": 1680.0,
   "pending_units": 1680.0,
   "warehouse": "Lucknow"
  },
  {
   "open_ltrs": 540.0,
   "open_pos": 1,
   "open_units": 540.0,
   "order_value": 85904.76190476191,
   "pending_ltrs": 540.0,
   "pending_units": 540.0,
   "warehouse": "Ludhiana"
  }
 ],
 "defaulted_to_latest": true,
 "format": "FLIPKART GROCERY",
 "max_po_date": "30-06-2026",
 "min_po_date": "19-06-2026",
 "platform": "flipkart_grocery",
 "po_month": "JUNE",
 "totals": {
  "open_ltrs": 5404.0,
  "open_pos": 5,
  "open_units": 5000.0,
  "pending_ltrs": 5404.0,
  "pending_units": 5000.0,
  "rows": 10
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - flipkart]] · [[Platform - flipkart_grocery]]
