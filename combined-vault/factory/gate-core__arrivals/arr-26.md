---
type: factory-arr
id: 26
title: "DL01LAL7290"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAL7290

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 26
- **arrival_no:** ARV-20260624-0006
- **vehicle:** 309
- **vehicle_no:** DL01LAL7290
- **driver:** 272
- **driver_name:** Satyam 8744049529
- **gate_in_date:** 2026-06-24
- **in_time:** 13:14:00
- **tare_weight:** 2210.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 16:27:45
- **departed_at:** 2026-06-24T16:27:45.219713+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 139, "entry_no": "EVGI-20260624-0021", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T16:27:45.219713+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 139, "entry_no": "DOCK-20260624-0013", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000075", "sap_doc_num": "626068199"}]
  ```

## Related
- driver -> [[drv-272]]
- vehicle -> [[veh-309]]
