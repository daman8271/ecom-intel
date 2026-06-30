---
type: factory-arr
id: 30
title: "HR69F9627"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR69F9627

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 30
- **arrival_no:** ARV-20260624-0010
- **vehicle:** 308
- **vehicle_no:** HR69F9627
- **driver:** 227
- **driver_name:** Milkha singh
- **gate_in_date:** 2026-06-24
- **in_time:** 14:45:00
- **tare_weight:** 13090.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
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
  [{"id": 143, "entry_no": "EVGI-20260624-0025", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": null, "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 138, "entry_no": "DOCK-20260624-0012", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "PRINT_COMMITTED", "gatepass_no": "DCK/JIVO_MART/2026-27/000020", "sap_doc_num": "706260496, 706260499, 706260501"}]
  ```

## Related
- driver -> [[drv-227]]
- vehicle -> [[veh-308]]
