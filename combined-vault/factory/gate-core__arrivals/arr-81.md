---
type: factory-arr
id: 81
title: "DL01LAN3959"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN3959

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 81
- **arrival_no:** ARV-20260627-0006
- **vehicle:** 273
- **vehicle_no:** DL01LAN3959
- **driver:** 275
- **driver_name:** Rajesh 8800852698
- **gate_in_date:** 2026-06-27
- **in_time:** 10:02:00
- **tare_weight:** 1790.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 11:48:30
- **departed_at:** 2026-06-27T11:48:30.040634+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 195, "entry_no": "EVGI-20260627-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T11:48:30.040634+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 192, "entry_no": "DOCK-20260627-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000110", "sap_doc_num": "626068242"}]
  ```

## Related
- driver -> [[drv-275]]
- vehicle -> [[veh-273]]
