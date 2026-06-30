---
type: factory-arr
id: 25
title: "DL01LAL2818"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAL2818

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 25
- **arrival_no:** ARV-20260624-0005
- **vehicle:** 291
- **vehicle_no:** DL01LAL2818
- **driver:** 42
- **driver_name:** Ajay
- **gate_in_date:** 2026-06-24
- **in_time:** 12:51:00
- **tare_weight:** 2200.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 18:02:50
- **departed_at:** 2026-06-24T18:02:50.164698+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 138, "entry_no": "EVGI-20260624-0020", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T18:02:50.164698+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 134, "entry_no": "DOCK-20260624-0008", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000078", "sap_doc_num": "626068198"}]
  ```

## Related
- driver -> [[drv-42]]
- vehicle -> [[veh-291]]
