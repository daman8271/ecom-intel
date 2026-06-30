---
type: factory-arr
id: 43
title: "HR67E3663"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67E3663

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 43
- **arrival_no:** ARV-20260625-0009
- **vehicle:** 314
- **vehicle_no:** HR67E3663
- **driver:** 59
- **driver_name:** Amit
- **gate_in_date:** 2026-06-25
- **in_time:** 11:24:00
- **tare_weight:** 6670.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 15:23:17
- **departed_at:** 2026-06-25T15:23:17.695859+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 156, "entry_no": "EVGI-20260625-0009", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-25T15:23:17.695859+05:30", "cover_count": 4}]
  ```
- **gate_outs:**
  ```json
  [{"id": 152, "entry_no": "DOCK-20260625-0007", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000036", "sap_doc_num": "626060443, 626060445, 626060446, 626060453"}]
  ```

## Related
- driver -> [[drv-59]]
- vehicle -> [[veh-314]]
