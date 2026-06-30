---
type: factory-arr
id: 36
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
- **id:** 36
- **arrival_no:** ARV-20260625-0002
- **vehicle:** 206
- **vehicle_no:** DL01LAR2914
- **driver:** 226
- **driver_name:** mohit
- **gate_in_date:** 2026-06-25
- **in_time:** 10:14:00
- **tare_weight:** 2100.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 11:25:27
- **departed_at:** 2026-06-25T11:25:27.462016+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 149, "entry_no": "EVGI-20260625-0002", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T11:25:27.462016+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 149, "entry_no": "DOCK-20260625-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000083", "sap_doc_num": "626068210"}]
  ```

## Related
- driver -> [[drv-226]]
- vehicle -> [[veh-206]]
