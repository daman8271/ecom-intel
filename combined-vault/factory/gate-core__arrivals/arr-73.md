---
type: factory-arr
id: 73
title: "HR63F9826"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR63F9826

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 73
- **arrival_no:** ARV-20260626-0016
- **vehicle:** 322
- **vehicle_no:** HR63F9826
- **driver:** 285
- **driver_name:** Suraj 7495032810
- **gate_in_date:** 2026-06-26
- **in_time:** 17:12:00
- **tare_weight:** 10210.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 21:01:38
- **departed_at:** 2026-06-26T21:01:38.968982+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 186, "entry_no": "EVGI-20260626-0016", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-26T21:01:38.968982+05:30", "cover_count": 4}]
  ```
- **gate_outs:**
  ```json
  [{"id": 181, "entry_no": "DOCK-20260626-0015", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000025", "sap_doc_num": "706260728, 706260731, 706260735, 706260738"}]
  ```

## Related
- driver -> [[drv-285]]
- vehicle -> [[veh-322]]
