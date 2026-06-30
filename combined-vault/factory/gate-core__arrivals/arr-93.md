---
type: factory-arr
id: 93
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
- **id:** 93
- **arrival_no:** ARV-20260627-0018
- **vehicle:** 314
- **vehicle_no:** HR67E3663
- **driver:** 99
- **driver_name:** Amit
- **gate_in_date:** 2026-06-27
- **in_time:** 16:24:00
- **tare_weight:** 6590.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 19:52:42
- **departed_at:** 2026-06-27T19:52:42.170411+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 207, "entry_no": "EVGI-20260627-0019", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-27T19:52:42.170411+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 201, "entry_no": "DOCK-20260627-0016", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000045", "sap_doc_num": "626060470, 626060471"}]
  ```

## Related
- driver -> [[drv-99]]
- vehicle -> [[veh-314]]
