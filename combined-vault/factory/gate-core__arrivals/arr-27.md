---
type: factory-arr
id: 27
title: "DL01LX3089"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LX3089

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 27
- **arrival_no:** ARV-20260624-0007
- **vehicle:** 194
- **vehicle_no:** DL01LX3089
- **driver:** 177
- **driver_name:** PAWAN
- **gate_in_date:** 2026-06-24
- **in_time:** 13:58:00
- **tare_weight:** 3770.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 14:21:36
- **departed_at:** 2026-06-24T14:21:36.636810+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 140, "entry_no": "EVGI-20260624-0022", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T14:21:36.636810+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 137, "entry_no": "DOCK-20260624-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000074", "sap_doc_num": "626058311"}]
  ```

## Related
- driver -> [[drv-177]]
- vehicle -> [[veh-194]]
