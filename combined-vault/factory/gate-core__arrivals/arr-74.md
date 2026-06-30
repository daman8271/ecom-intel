---
type: factory-arr
id: 74
title: "DL01LAC2818"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAC2818

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 74
- **arrival_no:** ARV-20260626-0017
- **vehicle:** 238
- **vehicle_no:** DL01LAC2818
- **driver:** 286
- **driver_name:** Ajay 8510944121
- **gate_in_date:** 2026-06-26
- **in_time:** 17:17:00
- **tare_weight:** 2190.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 18:42:19
- **departed_at:** 2026-06-26T18:42:19.153832+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 187, "entry_no": "EVGI-20260626-0017", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T18:42:19.153832+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 183, "entry_no": "DOCK-20260626-0017", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000106", "sap_doc_num": "626068230"}]
  ```

## Related
- driver -> [[drv-286]]
- vehicle -> [[veh-238]]
