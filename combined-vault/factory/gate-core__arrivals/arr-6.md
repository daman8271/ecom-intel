---
type: factory-arr
id: 6
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
- **id:** 6
- **arrival_no:** ARV-20260623-0003
- **vehicle:** 202
- **vehicle_no:** DL01MA6176
- **driver:** 113
- **driver_name:** raju
- **gate_in_date:** 2026-06-23
- **in_time:** 09:52:00
- **tare_weight:** 5000.000
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
  [{"id": 136, "entry_no": "EVGI-20260624-0018", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T12:42:07.503403+05:30", "cover_count": 1}, {"id": 104, "entry_no": "EVGI-20260623-0003", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-23T21:51:40.937521+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 114, "entry_no": "DOCK-20260623-0005", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000030", "sap_doc_num": "626060414, 626060415, 626060420"}]
  ```

## Related
- driver -> [[drv-113]]
- vehicle -> [[veh-202]]
