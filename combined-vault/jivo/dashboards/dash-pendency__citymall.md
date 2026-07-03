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
   "city": "Dadri",
   "open_ltrs": 11484.0,
   "open_pos": 1,
   "open_units": 9884.0,
   "order_value": 1632663.76,
   "pending_ltrs": 11484.0,
   "pending_units": 9884.0
  },
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
   "open_ltrs": 41972.0,
   "open_pos": 4,
   "open_units": 36836.0,
   "order_value": 5988699.12,
   "pending_ltrs": 41972.0,
   "pending_units": 36836.0
  }
 ],
 "by_po": [
  {
   "distributor": "SUSTAINQUEST PRIVATE LIMITED",
   "location": "Dadri",
   "open_ltrs": 11484.0,
   "open_pos": 1,
   "open_units": 9884.0,
   "order_value": 1632663.76,
   "pending_ltrs": 11484.0,
   "pending_units": 9884.0,
   "po_date": "21-06-2026",
   "po_expiry_date": "29-06-2026",
   "po_number": "PO-1420774"
  },
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
   "open_ltrs": 28524.0,
   "open_pos": 4,
   "open_units": 28524.0,
   "order_value": 3911781.36,
   "pending_ltrs": 28524.0,
   "pending_units": 28524.0,
   "sku_code": "CM02456490",
   "sku_name": "Jivo Soyabean Oil 1 L (Pouch)"
  },
  {
   "item": "MUSTARD 5L",
   "open_ltrs": 2500.0,
   "open_pos": 4,
   "open_units": 500.0,
   "order_value": 380950.0,
   "pending_ltrs": 2500.0,
   "pending_units": 500.0,
   "sku_code": "CM02456487",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 5 L (Jar)"
  },
  {
   "item": "MUSTARD POUCH 1L",
   "open_ltrs": 2400.0,
   "open_pos": 4,
   "open_units": 2400.0,
   "order_value": 361152.0,
   "pending_ltrs": 2400.0,
   "pending_units": 2400.0,
   "sku_code": "CM02975981",
   "sku_name": "Jivo Cold Press Kachi Ghani"
  },
  {
   "item": "SOYABEAN 1L",
   "open_ltrs": 1740.0,
   "open_pos": 4,
   "open_units": 1740.0,
   "order_value": 265141.2,
   "pending_ltrs": 1740.0,
   "pending_units": 1740.0,
   "sku_code": "CM02456486",
   "sku_name": "Jivo Soyabean Oil 1 L (Bottle)"
  },
  {
   "item": "SOYABEAN 5L",
   "open_ltrs": 1600.0,
   "open_pos": 4,
   "open_units": 320.0,
   "order_value": 243808.0,
   "pending_ltrs": 1600.0,
   "pending_units": 320.0,
   "sku_code": "CM02456495",
   "sku_name": "Jivo Soyabean Oil 5 L (Jar)"
  },
  {
   "item": "RICE BRAN 5L",
   "open_ltrs": 1560.0,
   "open_pos": 4,
   "open_units": 312.0,
   "order_value": 234742.56,
   "pending_ltrs": 1560.0,
   "pending_units": 312.0,
   "sku_code": "CM02456488",
   "sku_name": "Jivo Rice Bran Oil 5 L (Jar)"
  },
  {
   "item": "RICE BRAN 1L",
   "open_ltrs": 992.0,
   "open_pos": 4,
   "open_units": 992.0,
   "order_value": 149276.16,
   "pending_ltrs": 992.0,
   "pending_units": 992.0,
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
   "open_ltrs": 580.0,
   "open_pos": 3,
   "open_units": 580.0,
   "order_value": 85619.6,
   "pending_ltrs": 580.0,
   "pending_units": 580.0,
   "sku_code": "CM02456493",
   "sku_name": "Jivo Cold Press Kachi Ghani Mustard Oil 1 L (Bottle)"
  },
  {
   "item": "SUNFLOWER 1L",
   "open_ltrs": 480.0,
   "open_pos": 4,
   "open_units": 480.0,
   "order_value": 76800.0,
   "pending_ltrs": 480.0,
   "pending_units": 480.0,
   "sku_code": "CM02456491",
   "sku_name": "Jivo Cold Press Sunflower Oil 1 L (Bottle)"
  },
  {
   "item": "GROUNDNUT 1L",
   "open_ltrs": 352.0,
   "open_pos": 4,
   "open_units": 352.0,
   "order_value": 70400.0,
   "pending_ltrs": 352.0,
   "pending_units": 352.0,
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
   "item": "SO OLIVE 1L",
   "open_ltrs": 112.0,
   "open_pos": 4,
   "open_units": 112.0,
   "order_value": 21333.76,
   "pending_ltrs": 112.0,
   "pending_units": 112.0,
   "sku_code": "CM02456500",
   "sku_name": "Jivo So-Olive Multisource Olive Oil 1 L (Bottle)"
  },
  {
   "item": "CANOLA 1L",
   "open_ltrs": 100.0,
   "open_pos": 3,
   "open_units": 100.0,
   "order_value": 20952.0,
   "pending_ltrs": 100.0,
   "pending_units": 100.0,
   "sku_code": "CM02456498",
   "sku_name": "Jivo Cold Press Canola Oil 1 L (Bottle)"
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
   "open_ltrs": 11484.0,
   "open_pos": 1,
   "open_units": 9884.0,
   "order_value": 1632663.76,
   "pending_ltrs": 11484.0,
   "pending_units": 9884.0,
   "warehouse": "Dadri"
  },
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
  "open_ltrs": 41972.0,
  "open_pos": 4,
  "open_units": 36836.0,
  "pending_ltrs": 41972.0,
  "pending_units": 36836.0,
  "rows": 52
 },
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - citymall]]
