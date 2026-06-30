---
type: factory-arr
id: 12
title: "HR67C1036"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67C1036

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 12
- **arrival_no:** ARV-20260623-0009
- **vehicle:** 283
- **vehicle_no:** HR67C1036
- **driver:** 247
- **driver_name:** Tilakraj
- **gate_in_date:** 2026-06-23
- **in_time:** 11:18:00
- **tare_weight:** 4730.000
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
  [{"id": 109, "entry_no": "EVGI-20260623-0008", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-23T14:07:26.654634+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 112, "entry_no": "DOCK-20260623-0003", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000015", "sap_doc_num": "606260169"}]
  ```

## Related
- driver -> [[drv-247]]
- vehicle -> [[veh-283]]
