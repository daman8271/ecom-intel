---
type: factory-arr
id: 98
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
- **id:** 98
- **arrival_no:** ARV-20260629-0003
- **vehicle:** 202
- **vehicle_no:** DL01MA6176
- **driver:** 113
- **driver_name:** raju
- **gate_in_date:** 2026-06-29
- **in_time:** 10:16:00
- **tare_weight:** 4990.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-29
- **out_time:** 14:11:21
- **departed_at:** 2026-06-29T14:11:21.813128+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 214, "entry_no": "EVGI-20260629-0003", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-29T14:11:21.813128+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 209, "entry_no": "DOCK-20260629-0001", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000047", "sap_doc_num": "626060483"}]
  ```

## Related
- driver -> [[drv-113]]
- vehicle -> [[veh-202]]
