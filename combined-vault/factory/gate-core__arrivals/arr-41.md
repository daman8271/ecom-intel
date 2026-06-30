---
type: factory-arr
id: 41
title: "DL01LAM1528"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAM1528

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 41
- **arrival_no:** ARV-20260625-0007
- **vehicle:** 173
- **vehicle_no:** DL01LAM1528
- **driver:** 275
- **driver_name:** Rajesh 8800852698
- **gate_in_date:** 2026-06-25
- **in_time:** 10:38:00
- **tare_weight:** 1650.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 11:34:01
- **departed_at:** 2026-06-25T11:34:01.686208+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 154, "entry_no": "EVGI-20260625-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T11:34:01.686208+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 150, "entry_no": "DOCK-20260625-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000084", "sap_doc_num": "626068202"}]
  ```

## Related
- driver -> [[drv-275]]
- vehicle -> [[veh-173]]
