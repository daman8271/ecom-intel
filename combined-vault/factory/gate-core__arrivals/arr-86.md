---
type: factory-arr
id: 86
title: "DL01LAR7208"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAR7208

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 86
- **arrival_no:** ARV-20260627-0011
- **vehicle:** 332
- **vehicle_no:** DL01LAR7208
- **driver:** 293
- **driver_name:** Hemant 7678297100
- **gate_in_date:** 2026-06-27
- **in_time:** 12:48:00
- **tare_weight:** 2120.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 15:52:05
- **departed_at:** 2026-06-27T15:52:05.424229+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 200, "entry_no": "EVGI-20260627-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T15:52:05.424229+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 198, "entry_no": "DOCK-20260627-0013", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000113", "sap_doc_num": "626068244"}]
  ```

## Related
- driver -> [[drv-293]]
- vehicle -> [[veh-332]]
