---
type: factory-arr
id: 80
title: "DL01LAC8007"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAC8007

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 80
- **arrival_no:** ARV-20260627-0005
- **vehicle:** 205
- **vehicle_no:** DL01LAC8007
- **driver:** 230
- **driver_name:** Pappu 9817807988
- **gate_in_date:** 2026-06-27
- **in_time:** 09:59:00
- **tare_weight:** 2110.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-29
- **out_time:** 15:46:17
- **departed_at:** 2026-06-29T15:46:17.358339+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 194, "entry_no": "EVGI-20260627-0006", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-27T12:12:46.054310+05:30", "cover_count": 1}, {"id": 193, "entry_no": "EVGI-20260627-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-29T12:59:46.881716+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 186, "entry_no": "DOCK-20260627-0001", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000044", "sap_doc_num": "626060465"}]
  ```

## Related
- driver -> [[drv-230]]
- vehicle -> [[veh-205]]
