---
type: factory-arr
id: 37
title: "DL01LAM0715"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAM0715

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 37
- **arrival_no:** ARV-20260625-0003
- **vehicle:** 208
- **vehicle_no:** DL01LAM0715
- **driver:** 213
- **driver_name:** Bhagmal 8281997574
- **gate_in_date:** 2026-06-25
- **in_time:** 10:18:00
- **tare_weight:** 1640.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 11:21:18
- **departed_at:** 2026-06-25T11:21:18.028232+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 150, "entry_no": "EVGI-20260625-0003", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T11:21:18.028232+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 148, "entry_no": "DOCK-20260625-0003", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000082", "sap_doc_num": "626068184"}]
  ```

## Related
- driver -> [[drv-213]]
- vehicle -> [[veh-208]]
