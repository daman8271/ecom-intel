---
type: factory-arr
id: 58
title: "HR67C1036"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67C1036

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 58
- **arrival_no:** ARV-20260626-0001
- **vehicle:** 283
- **vehicle_no:** HR67C1036
- **driver:** 247
- **driver_name:** Tilakraj
- **gate_in_date:** 2026-06-26
- **in_time:** 09:16:00
- **tare_weight:** 4730.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 10:57:51
- **departed_at:** 2026-06-26T10:57:51.077329+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 171, "entry_no": "EVGI-20260626-0001", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T10:57:51.077329+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 167, "entry_no": "DOCK-20260626-0001", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000096", "sap_doc_num": "626068235"}]
  ```

## Related
- driver -> [[drv-247]]
- vehicle -> [[veh-283]]
