---
type: factory-arr
id: 22
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
- **id:** 22
- **arrival_no:** ARV-20260624-0002
- **vehicle:** 273
- **vehicle_no:** DL01LAN3959
- **driver:** 67
- **driver_name:** RAJESH
- **gate_in_date:** 2026-06-24
- **in_time:** 10:04:00
- **tare_weight:** 1760.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** LOADING
- **gate_out_date:** None
- **out_time:** None
- **departed_at:** None
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 134, "entry_no": "EVGI-20260624-0016", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T11:52:37.075885+05:30", "cover_count": 1}, {"id": 127, "entry_no": "EVGI-20260624-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:34:41.385845+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 129, "entry_no": "DOCK-20260624-0003", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000068", "sap_doc_num": "626068200"}]
  ```

## Related
- driver -> [[drv-67]]
- vehicle -> [[veh-273]]
