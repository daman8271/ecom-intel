---
type: factory-arr
id: 5
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
- **id:** 5
- **arrival_no:** ARV-20260623-0002
- **vehicle:** 273
- **vehicle_no:** DL01LAN3959
- **driver:** 64
- **driver_name:** Rajesh
- **gate_in_date:** 2026-06-23
- **in_time:** 09:47:00
- **tare_weight:** 1790.000
- **weighbridge_slip_no:** 
- **security_name:** 
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-23
- **out_time:** 11:33:24
- **departed_at:** 2026-06-23T11:33:24.626866+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 103, "entry_no": "EVGI-20260623-0002", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T11:33:19.891728+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 111, "entry_no": "DOCK-20260623-0002", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000059", "sap_doc_num": "626068180"}]
  ```

## Related
- driver -> [[drv-64]]
- vehicle -> [[veh-273]]
