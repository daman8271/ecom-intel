---
type: factory-arr
id: 18
title: "HR69F6098"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR69F6098

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 18
- **arrival_no:** ARV-20260623-0015
- **vehicle:** 53
- **vehicle_no:** HR69F6098
- **driver:** 250
- **driver_name:** Rajvinder singh
- **gate_in_date:** 2026-06-23
- **in_time:** 16:40:00
- **tare_weight:** 7870.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-23
- **out_time:** 21:38:38
- **departed_at:** 2026-06-23T21:38:38.458045+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 116, "entry_no": "EVGI-20260623-0015", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-23T21:38:27.933444+05:30", "cover_count": 4}]
  ```
- **gate_outs:**
  ```json
  [{"id": 123, "entry_no": "DOCK-20260623-0014", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000032", "sap_doc_num": "626060417, 626060418, 626060422, 626060423"}]
  ```

## Related
- driver -> [[drv-250]]
- vehicle -> [[veh-53]]
