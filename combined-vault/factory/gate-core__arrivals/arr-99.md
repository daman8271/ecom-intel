---
type: factory-arr
id: 99
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
- **id:** 99
- **arrival_no:** ARV-20260629-0004
- **vehicle:** 194
- **vehicle_no:** DL01LX3089
- **driver:** 177
- **driver_name:** PAWAN
- **gate_in_date:** 2026-06-29
- **in_time:** 10:18:00
- **tare_weight:** 3770.000
- **weighbridge_slip_no:** 
- **security_name:** Deepak
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-29
- **out_time:** 12:27:33
- **departed_at:** 2026-06-29T12:27:33.318681+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 215, "entry_no": "EVGI-20260629-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-29T12:27:33.318681+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 214, "entry_no": "DOCK-20260629-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000122", "sap_doc_num": "626068261, 626068262"}]
  ```

## Related
- driver -> [[drv-177]]
- vehicle -> [[veh-194]]
