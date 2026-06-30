---
type: factory-arr
id: 23
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
- **id:** 23
- **arrival_no:** ARV-20260624-0003
- **vehicle:** 274
- **vehicle_no:** DL01LAQ7967
- **driver:** 238
- **driver_name:** Arun
- **gate_in_date:** 2026-06-24
- **in_time:** 11:17:00
- **tare_weight:** 1790.000
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
  [{"id": 132, "entry_no": "EVGI-20260624-0014", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T12:18:40.364981+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 131, "entry_no": "DOCK-20260624-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000071", "sap_doc_num": "626068190"}]
  ```

## Related
- driver -> [[drv-238]]
- vehicle -> [[veh-274]]
