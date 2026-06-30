---
type: factory-arr
id: 83
title: "DL01LX3089"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LX3089

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 83
- **arrival_no:** ARV-20260627-0008
- **vehicle:** 194
- **vehicle_no:** DL01LX3089
- **driver:** 177
- **driver_name:** PAWAN
- **gate_in_date:** 2026-06-27
- **in_time:** 10:52:00
- **tare_weight:** 3770.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 14:06:39
- **departed_at:** 2026-06-27T14:06:39.339077+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 197, "entry_no": "EVGI-20260627-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T14:06:39.339077+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 193, "entry_no": "DOCK-20260627-0008", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000111", "sap_doc_num": "626068236"}]
  ```

## Related
- driver -> [[drv-177]]
- vehicle -> [[veh-194]]
