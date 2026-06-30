---
type: factory-arr
id: 17
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
- **id:** 17
- **arrival_no:** ARV-20260623-0014
- **vehicle:** 207
- **vehicle_no:** DL01LAR7060
- **driver:** 218
- **driver_name:** Maan singh 7355962044
- **gate_in_date:** 2026-06-23
- **in_time:** 16:00:00
- **tare_weight:** 2150.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 16:29:17
- **departed_at:** 2026-06-24T16:29:17.948892+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 121, "entry_no": "EVGI-20260624-0003", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:36:43.182387+05:30", "cover_count": 1}, {"id": 115, "entry_no": "EVGI-20260623-0014", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T18:51:51.221329+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 124, "entry_no": "DOCK-20260623-0015", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000066", "sap_doc_num": "626068176"}]
  ```

## Related
- driver -> [[drv-218]]
- vehicle -> [[veh-207]]
