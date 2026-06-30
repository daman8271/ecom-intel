---
type: factory-arr
id: 10
title: "DL01LAQ4445"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAQ4445

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 10
- **arrival_no:** ARV-20260623-0007
- **vehicle:** 271
- **vehicle_no:** DL01LAQ4445
- **driver:** 215
- **driver_name:** Sanjay 9958559288
- **gate_in_date:** 2026-06-23
- **in_time:** 11:06:00
- **tare_weight:** 1630.000
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
  [{"id": 128, "entry_no": "EVGI-20260624-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T11:45:22.159822+05:30", "cover_count": 1}, {"id": 119, "entry_no": "EVGI-20260624-0001", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:32:31.731890+05:30", "cover_count": 1}, {"id": 108, "entry_no": "EVGI-20260623-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T13:57:12.670233+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 130, "entry_no": "DOCK-20260624-0004", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000069", "sap_doc_num": "626068201"}, {"id": 118, "entry_no": "DOCK-20260623-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000063", "sap_doc_num": "626068178"}]
  ```

## Related
- driver -> [[drv-215]]
- vehicle -> [[veh-271]]
