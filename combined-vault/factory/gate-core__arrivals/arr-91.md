---
type: factory-arr
id: 91
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
- **id:** 91
- **arrival_no:** ARV-20260627-0016
- **vehicle:** 53
- **vehicle_no:** HR69F6098
- **driver:** 250
- **driver_name:** Rajvinder singh
- **gate_in_date:** 2026-06-27
- **in_time:** 16:04:00
- **tare_weight:** 7890.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 21:05:22
- **departed_at:** 2026-06-27T21:05:22.517593+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 205, "entry_no": "EVGI-20260627-0017", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-27T21:05:22.517593+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 208, "entry_no": "DOCK-20260627-0023", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000031", "sap_doc_num": "706260766, 706260767, 706260782"}]
  ```

## Related
- driver -> [[drv-250]]
- vehicle -> [[veh-53]]
