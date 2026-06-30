---
type: factory-arr
id: 2
title: "HR69F7125"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR69F7125

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 2
- **arrival_no:** ARV-20260622-0002
- **vehicle:** 266
- **vehicle_no:** HR69F7125
- **driver:** 265
- **driver_name:** Gurpreet 9872987038
- **gate_in_date:** 2026-06-22
- **in_time:** 16:43:00
- **tare_weight:** 11300.000
- **weighbridge_slip_no:** 
- **security_name:** 
- **remarks:** 
- **status:** LOADING
- **gate_out_date:** None
- **out_time:** None
- **departed_at:** None
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 100, "entry_no": "EVGI-20260622-0013", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-22T20:15:14.903559+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 107, "entry_no": "DOCK-20260622-0013", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000014", "sap_doc_num": "706260558, 706260560, 706260561"}]
  ```

## Related
- driver -> [[drv-265]]
- vehicle -> [[veh-266]]
