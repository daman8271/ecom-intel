---
type: factory-arr
id: 72
title: "DL01LAN4204"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN4204

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 72
- **arrival_no:** ARV-20260626-0015
- **vehicle:** 195
- **vehicle_no:** DL01LAN4204
- **driver:** 127
- **driver_name:** MAHESH
- **gate_in_date:** 2026-06-26
- **in_time:** 16:47:00
- **tare_weight:** 4280.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 18:26:02
- **departed_at:** 2026-06-26T18:26:02.956016+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 185, "entry_no": "EVGI-20260626-0015", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T18:26:02.956016+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 185, "entry_no": "DOCK-20260626-0019", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000105", "sap_doc_num": "626068240"}]
  ```

## Related
- driver -> [[drv-127]]
- vehicle -> [[veh-195]]
