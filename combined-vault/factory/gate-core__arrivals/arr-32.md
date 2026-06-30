---
type: factory-arr
id: 32
title: "DL01LAC8007"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAC8007

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 32
- **arrival_no:** ARV-20260624-0012
- **vehicle:** 205
- **vehicle_no:** DL01LAC8007
- **driver:** 230
- **driver_name:** Pappu 9817807988
- **gate_in_date:** 2026-06-24
- **in_time:** 16:14:00
- **tare_weight:** 2110.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 17:57:45
- **departed_at:** 2026-06-24T17:57:45.745179+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 145, "entry_no": "EVGI-20260624-0027", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-24T17:57:45.745179+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 141, "entry_no": "DOCK-20260624-0015", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000033", "sap_doc_num": "626060427"}]
  ```

## Related
- driver -> [[drv-230]]
- vehicle -> [[veh-205]]
