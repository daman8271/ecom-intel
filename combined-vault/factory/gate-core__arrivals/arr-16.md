---
type: factory-arr
id: 16
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
- **id:** 16
- **arrival_no:** ARV-20260623-0013
- **vehicle:** 213
- **vehicle_no:** HR67C4904
- **driver:** 269
- **driver_name:** Ramkaran 9918186361
- **gate_in_date:** 2026-06-23
- **in_time:** 14:22:00
- **tare_weight:** 5090.000
- **weighbridge_slip_no:** 
- **security_name:** 
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-23
- **out_time:** 21:55:09
- **departed_at:** 2026-06-23T21:55:09.795831+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 114, "entry_no": "EVGI-20260623-0013", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-23T21:55:04.583413+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 126, "entry_no": "DOCK-20260623-0017", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000019", "sap_doc_num": "606260164"}]
  ```

## Related
- driver -> [[drv-269]]
- vehicle -> [[veh-213]]
