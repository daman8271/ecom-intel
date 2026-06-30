---
type: factory-arr
id: 33
title: "HR63F4834"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR63F4834

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 33
- **arrival_no:** ARV-20260624-0013
- **vehicle:** 311
- **vehicle_no:** HR63F4834
- **driver:** 107
- **driver_name:** Sonu
- **gate_in_date:** 2026-06-24
- **in_time:** 16:47:00
- **tare_weight:** 7380.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 18:20:51
- **departed_at:** 2026-06-24T18:20:51.316607+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 146, "entry_no": "EVGI-20260624-0028", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-24T18:20:51.316607+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 143, "entry_no": "DOCK-20260624-0017", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000034", "sap_doc_num": "626060429, 626060430"}]
  ```

## Related
- driver -> [[drv-107]]
- vehicle -> [[veh-311]]
