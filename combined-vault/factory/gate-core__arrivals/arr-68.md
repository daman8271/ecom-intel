---
type: factory-arr
id: 68
title: "HR67C4904"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67C4904

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 68
- **arrival_no:** ARV-20260626-0011
- **vehicle:** 213
- **vehicle_no:** HR67C4904
- **driver:** 269
- **driver_name:** Ramkaran 9918186361
- **gate_in_date:** 2026-06-26
- **in_time:** 12:43:00
- **tare_weight:** 5100.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 17:56:37
- **departed_at:** 2026-06-26T17:56:37.298803+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 181, "entry_no": "EVGI-20260626-0011", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-26T17:56:37.298803+05:30", "cover_count": 4}]
  ```
- **gate_outs:**
  ```json
  [{"id": 177, "entry_no": "DOCK-20260626-0011", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000042", "sap_doc_num": "626060432, 626060433, 626060455, 626060456"}]
  ```

## Related
- driver -> [[drv-269]]
- vehicle -> [[veh-213]]
