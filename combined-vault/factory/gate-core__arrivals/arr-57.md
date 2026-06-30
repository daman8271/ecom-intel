---
type: factory-arr
id: 57
title: "DL01LAR7060"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAR7060

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 57
- **arrival_no:** ARV-20260625-0023
- **vehicle:** 207
- **vehicle_no:** DL01LAR7060
- **driver:** 218
- **driver_name:** Maan singh 7355962044
- **gate_in_date:** 2026-06-25
- **in_time:** 19:07:00
- **tare_weight:** 2150.000
- **weighbridge_slip_no:** 
- **security_name:** 
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 19:49:50
- **departed_at:** 2026-06-25T19:49:50.616427+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 170, "entry_no": "EVGI-20260625-0023", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T19:49:50.616427+05:30", "cover_count": 6}]
  ```
- **gate_outs:**
  ```json
  [{"id": 165, "entry_no": "DOCK-20260625-0020", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000094", "sap_doc_num": "626068095, 626068096, 626068212, 626068221, 626068222, 626068223"}]
  ```

## Related
- driver -> [[drv-218]]
- vehicle -> [[veh-207]]
