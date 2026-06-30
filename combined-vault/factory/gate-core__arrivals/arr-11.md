---
type: factory-arr
id: 11
title: "RJ11GD2629"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# RJ11GD2629

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 11
- **arrival_no:** ARV-20260623-0008
- **vehicle:** 305
- **vehicle_no:** RJ11GD2629
- **driver:** 268
- **driver_name:** Pankaj 7807602322
- **gate_in_date:** 2026-06-23
- **in_time:** 11:23:00
- **tare_weight:** 11730.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-23
- **out_time:** 18:52:11
- **departed_at:** 2026-06-23T18:52:11.113580+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 110, "entry_no": "EVGI-20260623-0009", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-23T18:52:00.807795+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 113, "entry_no": "DOCK-20260623-0004", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000017", "sap_doc_num": "606260162, 606260166, 606260170"}]
  ```

## Related
- driver -> [[drv-268]]
- vehicle -> [[veh-305]]
