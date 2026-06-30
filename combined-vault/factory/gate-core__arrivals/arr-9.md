---
type: factory-arr
id: 9
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
- **id:** 9
- **arrival_no:** ARV-20260623-0006
- **vehicle:** 206
- **vehicle_no:** DL01LAR2914
- **driver:** 226
- **driver_name:** mohit
- **gate_in_date:** 2026-06-23
- **in_time:** 10:57:00
- **tare_weight:** 2110.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** LOADING
- **gate_out_date:** None
- **out_time:** None
- **departed_at:** None
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 107, "entry_no": "EVGI-20260623-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T15:14:37.986286+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 119, "entry_no": "DOCK-20260623-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000064", "sap_doc_num": "626068173"}]
  ```

## Related
- driver -> [[drv-226]]
- vehicle -> [[veh-206]]
