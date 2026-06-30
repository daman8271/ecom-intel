---
type: factory-arr
id: 79
title: "DL01LAQ4445"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAQ4445

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 79
- **arrival_no:** ARV-20260627-0004
- **vehicle:** 271
- **vehicle_no:** DL01LAQ4445
- **driver:** 215
- **driver_name:** Sanjay 9958559288
- **gate_in_date:** 2026-06-27
- **in_time:** 09:48:00
- **tare_weight:** 1630.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 11:43:57
- **departed_at:** 2026-06-27T11:43:57.879713+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 192, "entry_no": "EVGI-20260627-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T11:43:57.879713+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 190, "entry_no": "DOCK-20260627-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000109", "sap_doc_num": "626068239"}]
  ```

## Related
- driver -> [[drv-215]]
- vehicle -> [[veh-271]]
