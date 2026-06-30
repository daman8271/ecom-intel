---
type: factory-arr
id: 7
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
- **id:** 7
- **arrival_no:** ARV-20260623-0004
- **vehicle:** 173
- **vehicle_no:** DL01LAM1528
- **driver:** 219
- **driver_name:** Rajesh 6388125387
- **gate_in_date:** 2026-06-23
- **in_time:** 09:55:00
- **tare_weight:** 1640.000
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
  [{"id": 131, "entry_no": "EVGI-20260624-0013", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T12:03:42.235157+05:30", "cover_count": 1}, {"id": 122, "entry_no": "EVGI-20260624-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:36:11.002702+05:30", "cover_count": 1}, {"id": 105, "entry_no": "EVGI-20260623-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T12:17:46.805771+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 132, "entry_no": "DOCK-20260624-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000070", "sap_doc_num": "626068188"}, {"id": 116, "entry_no": "DOCK-20260623-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000061", "sap_doc_num": "626068181"}]
  ```

## Related
- driver -> [[drv-219]]
- vehicle -> [[veh-173]]
