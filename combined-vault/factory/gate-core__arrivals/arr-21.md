---
type: factory-arr
id: 21
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
- **id:** 21
- **arrival_no:** ARV-20260624-0001
- **vehicle:** 208
- **vehicle_no:** DL01LAM0715
- **driver:** 213
- **driver_name:** Bhagmal 8281997574
- **gate_in_date:** 2026-06-24
- **in_time:** 09:17:00
- **tare_weight:** 1640.000
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
  [{"id": 133, "entry_no": "EVGI-20260624-0015", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T11:54:48.067770+05:30", "cover_count": 1}, {"id": 124, "entry_no": "EVGI-20260624-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:35:30.530617+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 128, "entry_no": "DOCK-20260624-0002", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000067", "sap_doc_num": "626068191"}]
  ```

## Related
- driver -> [[drv-213]]
- vehicle -> [[veh-208]]
