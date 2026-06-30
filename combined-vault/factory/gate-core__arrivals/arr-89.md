---
type: factory-arr
id: 89
title: "HR63F7981"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR63F7981

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 89
- **arrival_no:** ARV-20260627-0014
- **vehicle:** 333
- **vehicle_no:** HR63F7981
- **driver:** 295
- **driver_name:** Amit 7307939498
- **gate_in_date:** 2026-06-27
- **in_time:** 14:07:00
- **tare_weight:** 9920.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 17:30:52
- **departed_at:** 2026-06-27T17:30:52.030675+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 203, "entry_no": "EVGI-20260627-0015", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-27T17:30:52.030675+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 197, "entry_no": "DOCK-20260627-0012", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000028", "sap_doc_num": "706260779, 706260780, 706260781"}]
  ```

## Related
- driver -> [[drv-295]]
- vehicle -> [[veh-333]]
