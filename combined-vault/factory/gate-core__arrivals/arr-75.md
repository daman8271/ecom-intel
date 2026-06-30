---
type: factory-arr
id: 75
title: "DL01MA3485"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01MA3485

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 75
- **arrival_no:** ARV-20260626-0018
- **vehicle:** 323
- **vehicle_no:** DL01MA3485
- **driver:** 287
- **driver_name:** Sunil 7782846977
- **gate_in_date:** 2026-06-26
- **in_time:** 17:59:00
- **tare_weight:** 4930.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 20:19:15
- **departed_at:** 2026-06-26T20:19:15.222307+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 188, "entry_no": "EVGI-20260626-0018", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-26T20:19:15.222307+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 184, "entry_no": "DOCK-20260626-0018", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000024", "sap_doc_num": "706260622, 706260634"}]
  ```

## Related
- driver -> [[drv-287]]
- vehicle -> [[veh-323]]
