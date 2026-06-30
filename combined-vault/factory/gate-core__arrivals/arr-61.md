---
type: factory-arr
id: 61
title: "DL01LAQ7967"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAQ7967

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 61
- **arrival_no:** ARV-20260626-0004
- **vehicle:** 274
- **vehicle_no:** DL01LAQ7967
- **driver:** 238
- **driver_name:** Arun
- **gate_in_date:** 2026-06-26
- **in_time:** 10:48:00
- **tare_weight:** 1800.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 13:06:51
- **departed_at:** 2026-06-26T13:06:51.739233+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 175, "entry_no": "EVGI-20260626-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T13:06:51.739233+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 176, "entry_no": "DOCK-20260626-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000102", "sap_doc_num": "626068232"}]
  ```

## Related
- driver -> [[drv-238]]
- vehicle -> [[veh-274]]
