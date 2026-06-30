---
type: factory-arr
id: 24
title: "DL01MA6176"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01MA6176

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 24
- **arrival_no:** ARV-20260624-0004
- **vehicle:** 202
- **vehicle_no:** DL01MA6176
- **driver:** 113
- **driver_name:** raju
- **gate_in_date:** 2026-06-24
- **in_time:** 12:43:00
- **tare_weight:** 4980.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 19:19:41
- **departed_at:** 2026-06-24T19:19:41.896353+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 137, "entry_no": "EVGI-20260624-0019", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T19:19:41.896353+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 145, "entry_no": "DOCK-20260624-0019", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000080", "sap_doc_num": "626068193"}]
  ```

## Related
- driver -> [[drv-113]]
- vehicle -> [[veh-202]]
