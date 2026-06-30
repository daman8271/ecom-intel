---
type: factory-arr
id: 38
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
- **id:** 38
- **arrival_no:** ARV-20260625-0004
- **vehicle:** 213
- **vehicle_no:** HR67C4904
- **driver:** 269
- **driver_name:** Ramkaran 9918186361
- **gate_in_date:** 2026-06-25
- **in_time:** 10:20:00
- **tare_weight:** 5100.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 14:58:13
- **departed_at:** 2026-06-25T14:58:13.001870+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 151, "entry_no": "EVGI-20260625-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T14:58:13.001870+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 154, "entry_no": "DOCK-20260625-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000088", "sap_doc_num": "626068218"}]
  ```

## Related
- driver -> [[drv-269]]
- vehicle -> [[veh-213]]
