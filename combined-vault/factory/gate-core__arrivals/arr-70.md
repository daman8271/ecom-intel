---
type: factory-arr
id: 70
title: "HR55AX7276"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR55AX7276

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 70
- **arrival_no:** ARV-20260626-0013
- **vehicle:** 320
- **vehicle_no:** HR55AX7276
- **driver:** 283
- **driver_name:** Yudhister 6397969656
- **gate_in_date:** 2026-06-26
- **in_time:** 14:28:00
- **tare_weight:** 8600.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 17:50:49
- **departed_at:** 2026-06-26T17:50:49.376198+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 183, "entry_no": "EVGI-20260626-0013", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-26T17:50:49.376198+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 178, "entry_no": "DOCK-20260626-0012", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000023", "sap_doc_num": "706260740, 706260741, 706260742"}]
  ```

## Related
- driver -> [[drv-283]]
- vehicle -> [[veh-320]]
