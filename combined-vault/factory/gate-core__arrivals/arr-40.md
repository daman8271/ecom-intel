---
type: factory-arr
id: 40
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
- **id:** 40
- **arrival_no:** ARV-20260625-0006
- **vehicle:** 283
- **vehicle_no:** HR67C1036
- **driver:** 247
- **driver_name:** Tilakraj
- **gate_in_date:** 2026-06-25
- **in_time:** 10:34:00
- **tare_weight:** 4720.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 14:37:25
- **departed_at:** 2026-06-25T14:37:25.724425+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 153, "entry_no": "EVGI-20260625-0006", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-25T14:37:25.724425+05:30", "cover_count": 4}]
  ```
- **gate_outs:**
  ```json
  [{"id": 147, "entry_no": "DOCK-20260625-0002", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000021", "sap_doc_num": "706260166, 706260210, 706260390, 706260662"}]
  ```

## Related
- driver -> [[drv-247]]
- vehicle -> [[veh-283]]
