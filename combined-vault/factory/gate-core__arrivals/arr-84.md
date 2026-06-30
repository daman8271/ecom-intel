---
type: factory-arr
id: 84
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
- **id:** 84
- **arrival_no:** ARV-20260627-0009
- **vehicle:** 202
- **vehicle_no:** DL01MA6176
- **driver:** 113
- **driver_name:** raju
- **gate_in_date:** 2026-06-27
- **in_time:** 11:19:00
- **tare_weight:** 5000.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 14:24:13
- **departed_at:** 2026-06-27T14:24:13.276290+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 198, "entry_no": "EVGI-20260627-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T14:24:13.276290+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 195, "entry_no": "DOCK-20260627-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000112", "sap_doc_num": "626068254, 626068255, 626068256"}]
  ```

## Related
- driver -> [[drv-113]]
- vehicle -> [[veh-202]]
