---
type: factory-arr
id: 63
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
- **id:** 63
- **arrival_no:** ARV-20260626-0006
- **vehicle:** 273
- **vehicle_no:** DL01LAN3959
- **driver:** 275
- **driver_name:** Rajesh 8800852698
- **gate_in_date:** 2026-06-26
- **in_time:** 10:51:00
- **tare_weight:** 1780.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 12:11:43
- **departed_at:** 2026-06-26T12:11:43.726452+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 176, "entry_no": "EVGI-20260626-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T12:11:43.726452+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 173, "entry_no": "DOCK-20260626-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000098", "sap_doc_num": "626068231"}]
  ```

## Related
- driver -> [[drv-275]]
- vehicle -> [[veh-273]]
