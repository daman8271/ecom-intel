---
type: app-dashboard
endpoint_key: pendency__citymall
source: app-dashboard
month: ""
platform: citymall
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/citymall
---

# App dashboard — `pendency__citymall`

Up: [[dashboards-index]] · [[pf-citymall]]

> **source: app-dashboard `pendency__citymall`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "by_city": [
  {
   "city": "GURUGRAM",
   "open_ltrs": 10520.0,
   "open_pos": 1,
   "open_units": 9272.0,
   "order_value": 1503794.84,
   "pending_ltrs": 10520.0,
   "pending_units": 9272.0
  },
  {
   "city": "Sonipat",
   "open_ltrs": 10120.0,
   "open_pos": 1,
   "open_units": 8712.0,
   "order_value": 1439424.68,
   "pending_ltrs": 10120.0,
   "pending_units": 8712.0
  },
  {
   "city": "Bahadurgarh",
   "open_ltrs": 9848.0,
   "open_pos": 1,
   "open_units": 8968.0,
   "order_value": 1412815.84,
   "pending_ltrs": 9848.0,
   "pending_units": 8968.0
  }
 ],
 "by_distributor": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "open_ltrs": 30488.0,
   "open_pos": 3,
   "open_units": 26952.0,
   "order_value": 4356035.36,
   "pending_ltrs": 30488.0,
   "pending_units": 26952.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Gurugram",
   "open_ltrs": 10520.0,
   "open_pos": 1,
   "open_units": 9272.0,
   "order_value": 1503794.84,
   "pending_ltrs": 10520.0,
   "pending_units": 9272.0,
   "po_date": "21-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "PO-1420776"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Sonipat",
   "open_ltrs": 10120.0,
   "open_pos": 1,
   "open_units": 8712.0,
   "order_value": 1439424.68,
   "pending_ltrs": 10120.0,
   "pending_units": 8712.0,
   "po_date": "21-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "PO-1420787"
  },
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Bahadurgarh",
   "open_ltrs": 9848.0,
   "open_pos": 1,
   "open_units": 8968.0,
   "order_value": 1412815.84,
   "pending_ltrs": 9848.0,
   "pending_units": 8968.0,
   "po_date": "21-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "PO-1420772"
  }
 ],
 "by_sku": [
  {
   "item": "SOYABEAN 1L POUCH",
   "open_ltrs": 20520.0,
   "open_pos": 3,
   "open_units": 20520.0,
   "order_value": 2814112.8,
   "pending_ltrs": 20520.0,
   "pending_units": 20520.0,
   "sku_code": "CM02456490",
   "sku_name": "Jivo Soyabean Oil 1 L (Pouch)"
  },
  {
   "item": "MUSTARD POUCH 1L",
   "open_ltrs": 1900.0,
   "open_pos": 3,
   "open_units": 1900.0,
   "order_value": 285912.0,
   "pending_ltrs": 1900.0,
   "pending_units": 1900.0,
   "sku_code": "CM02975981",
   "sku_name": "Jivo Cold Press Kachi Ghani"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 1500.0,
   "open_pos": 3,
   "open_units": 300.0,
   "order_value": 228570.0,
   "pending_ltrs": 1500.0,
   "pending_units": 300.0,
   "sku_code": "CM02456487",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 5 L (Jar)"
  },
  {
   "item": "SOYABEAN 1L",
   "open_ltrs": 1340.0,
   "open_pos": 3,
   "open_units": 1340.0,
   "order_value": 204189.2,
   "pending_ltrs": 1340.0,
   "pending_units": 1340.0,
   "sku_code": "CM02456486",
   "sku_name": "Jivo Soyabean Oil 1 L (Bottle)"
  },
  {
   "item": "SOYABEAN 5L",
   "open_ltrs": 1100.0,
   "open_pos": 3,
   "open_units": 220.0,
   "order_value": 167618.0,
   "pending_ltrs": 1100.0,
   "pending_units": 220.0,
   "sku_code": "CM02456495",
   "sku_name": "Jivo Soyabean Oil 5 L (Jar)"
  },
  {
   "item": "RICE BRAN 5L",
   "open_ltrs": 1060.0,
   "open_pos": 3,
   "open_units": 212.0,
   "order_value": 159504.56,
   "pending_ltrs": 1060.0,
   "pending_units": 212.0,
   "sku_code": "CM02456488",
   "sku_name": "Jivo Rice Bran Oil 5 L (Jar)"
  },
  {
   "item": "RICE BRAN 1L",
   "open_ltrs": 784.0,
   "open_pos": 3,
   "open_units": 784.0,
   "order_value": 117976.32,
   "pending_ltrs": 784.0,
   "pending_units": 784.0,
   "sku_code": "CM02456496",
   "sku_name": "Jivo Rice Bran Oil 1 L (Bottle)"
  },
  {
   "item": "SUNFLOWER 5L",
   "open_ltrs": 760.0,
   "open_pos": 2,
   "open_units": 152.0,
   "order_value": 119427.92,
   "pending_ltrs": 760.0,
   "pending_units": 152.0,
   "sku_code": "CM02456497",
   "sku_name": "Jivo Cold Press Sunflower Oil 5 L"
  },
  {
   "item": "MUSTARD 1L",
   "open_ltrs": 500.0,
   "open_pos": 2,
   "open_units": 500.0,
   "order_value": 73810.0,
   "pending_ltrs": 500.0,
   "pending_units": 500.0,
   "sku_code": "CM02456493",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 1 L (Bottle)"
  },
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 320.0,
   "open_pos": 3,
   "open_units": 320.0,
   "order_value": 51200.0,
   "pending_ltrs": 320.0,
   "pending_units": 320.0,
   "sku_code": "CM02456491",
   "sku_name": "Jivo Cold Press Sunflower Oil 1 L (Bottle)"
  },
  {
   "item": "GROUNDNUT 1L",
   "open_ltrs": 272.0,
   "open_pos": 3,
   "open_units": 272.0,
   "order_value": 54400.0,
   "pending_ltrs": 272.0,
   "pending_units": 272.0,
   "sku_code": "CM02456489",
   "sku_name": "Jivo Cold Press Groundnut Oil 1 L"
  },
  {
   "item": "GOLD 1L",
   "open_ltrs": 240.0,
   "open_pos": 3,
   "open_units": 240.0,
   "order_value": 35428.8,
   "pending_ltrs": 240.0,
   "pending_units": 240.0,
   "sku_code": "CM02456494",
   "sku_name": "Jivo Gold Multisource Oil 1 L"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 80.0,
   "open_pos": 2,
   "open_units": 80.0,
   "order_value": 16761.6,
   "pending_ltrs": 80.0,
   "pending_units": 80.0,
   "sku_code": "CM02456498",
   "sku_name": "Jivo Cold Press Canola Oil 1 L (Bottle)"
  },
  {
   "item": "SO OLIVE 1L",
   "open_ltrs": 80.0,
   "open_pos": 3,
   "open_units": 80.0,
   "order_value": 15238.4,
   "pending_ltrs": 80.0,
   "pending_units": 80.0,
   "sku_code": "CM02456500",
   "sku_name": "Jivo So-Olive Multisource Olive Oil 1 L (Bottle)"
  },
  {
   "item": "JIVO POMACE 1L",
   "open_ltrs": 32.0,
   "open_pos": 1,
   "open_units": 32.0,
   "order_value": 11885.76,
   "pending_ltrs": 32.0,
   "pending_units": 32.0,
   "sku_code": "CM02456492",
   "sku_name": "Jivo Pomace Olive Oil 1 L (Bottle)"
  }
 ],
 "by_warehouse": [
  {
   "open_ltrs": 10520.0,
   "open_pos": 1,
   "open_units": 9272.0,
   "order_value": 1503794.84,
   "pending_ltrs": 10520.0,
   "pending_units": 9272.0,
   "warehouse": "Gurugram"
  },
  {
   "open_ltrs": 10120.0,
   "open_pos": 1,
   "open_units": 8712.0,
   "order_value": 1439424.68,
   "pending_ltrs": 10120.0,
   "pending_units": 8712.0,
   "warehouse": "Sonipat"
  },
  {
   "open_ltrs": 9848.0,
   "open_pos": 1,
   "open_units": 8968.0,
   "order_value": 1412815.84,
   "pending_ltrs": 9848.0,
   "pending_units": 8968.0,
   "warehouse": "Bahadurgarh"
  }
 ],
 "defaulted_to_latest": true,
 "format": "CITY MALL",
 "max_po_date": "21-06-2026",
 "min_po_date": "21-06-2026",
 "platform": "citymall",
 "po_month": "JUNE",
 "totals": {
  "open_ltrs": 30488.0,
  "open_pos": 3,
  "open_units": 26952.0,
  "pending_ltrs": 30488.0,
  "pending_units": 26952.0,
  "rows": 40
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - citymall]]
