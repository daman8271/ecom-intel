---
type: factory-arr
id: 94
title: "RJ18GC8499"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# RJ18GC8499

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 94
- **arrival_no:** ARV-20260627-0019
- **vehicle:** 336
- **vehicle_no:** RJ18GC8499
- **driver:** 297
- **driver_name:** Robin 9983919794
- **gate_in_date:** 2026-06-27
- **in_time:** 16:46:00
- **tare_weight:** 10380.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 22:49:46
- **departed_at:** 2026-06-27T22:49:46.864544+05:30
- **gatepass_no:** ARV/2026-27/000001
- **gatepass_printed_at:** 2026-06-27T22:47:47.373510+05:30
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 209, "entry_no": "EVGI-20260627-0021", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-27T22:49:46.864544+05:30", "cover_count": 1}, {"id": 208, "entry_no": "EVGI-20260627-0020", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-27T22:49:46.840461+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 203, "entry_no": "DOCK-20260627-0018", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000046", "sap_doc_num": "626060431, 626060451, 626060461"}, {"id": 202, "entry_no": "DOCK-20260627-0017", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000030", "sap_doc_num": "606260180"}]
  ```

## Related
- driver -> [[drv-297]]
- vehicle -> [[veh-336]]
