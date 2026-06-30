---
type: factory-arr
id: 76
title: "DL01LAR2914"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAR2914

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 76
- **arrival_no:** ARV-20260627-0001
- **vehicle:** 206
- **vehicle_no:** DL01LAR2914
- **driver:** 226
- **driver_name:** mohit
- **gate_in_date:** 2026-06-27
- **in_time:** 09:37:00
- **tare_weight:** 2110.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 23:04:31
- **departed_at:** 2026-06-27T23:04:31.084438+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 189, "entry_no": "EVGI-20260627-0001", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T23:04:31.084438+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 188, "entry_no": "DOCK-20260627-0003", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000107", "sap_doc_num": "626068241"}]
  ```

## Related
- driver -> [[drv-226]]
- vehicle -> [[veh-206]]
