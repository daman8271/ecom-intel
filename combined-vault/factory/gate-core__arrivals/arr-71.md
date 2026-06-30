---
type: factory-arr
id: 71
title: "DL01LAR7021"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAR7021

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 71
- **arrival_no:** ARV-20260626-0014
- **vehicle:** 231
- **vehicle_no:** DL01LAR7021
- **driver:** 249
- **driver_name:** Anil 7248133746
- **gate_in_date:** 2026-06-26
- **in_time:** 16:19:00
- **tare_weight:** 2640.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 17:38:42
- **departed_at:** 2026-06-26T17:38:42.022592+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 184, "entry_no": "EVGI-20260626-0014", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T17:38:42.022592+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 182, "entry_no": "DOCK-20260626-0016", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000104", "sap_doc_num": "626068234"}]
  ```

## Related
- driver -> [[drv-249]]
- vehicle -> [[veh-231]]
