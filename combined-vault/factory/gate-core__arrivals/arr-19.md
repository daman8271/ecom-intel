---
type: factory-arr
id: 19
title: "HR67D9270"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67D9270

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 19
- **arrival_no:** ARV-20260623-0016
- **vehicle:** 217
- **vehicle_no:** HR67D9270
- **driver:** 251
- **driver_name:** Binder
- **gate_in_date:** 2026-06-23
- **in_time:** 16:52:00
- **tare_weight:** 5660.000
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
  [{"id": 117, "entry_no": "EVGI-20260623-0016", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-23T19:21:16.069704+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 122, "entry_no": "DOCK-20260623-0013", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000018", "sap_doc_num": "606260171"}]
  ```

## Related
- driver -> [[drv-251]]
- vehicle -> [[veh-217]]
