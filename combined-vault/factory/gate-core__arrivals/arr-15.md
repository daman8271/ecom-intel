---
type: factory-arr
id: 15
title: "DL01LAN4204"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN4204

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 15
- **arrival_no:** ARV-20260623-0012
- **vehicle:** 195
- **vehicle_no:** DL01LAN4204
- **driver:** 127
- **driver_name:** MAHESH
- **gate_in_date:** 2026-06-23
- **in_time:** 11:58:00
- **tare_weight:** 4220.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 14:08:31
- **departed_at:** 2026-06-24T14:08:31.669137+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 135, "entry_no": "EVGI-20260624-0017", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T14:08:31.669137+05:30", "cover_count": 1}, {"id": 120, "entry_no": "EVGI-20260624-0002", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T11:15:15.486838+05:30", "cover_count": 1}, {"id": 113, "entry_no": "EVGI-20260623-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T13:21:13.573874+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 135, "entry_no": "DOCK-20260624-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000073", "sap_doc_num": "626068189"}, {"id": 117, "entry_no": "DOCK-20260623-0008", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000062", "sap_doc_num": "626068175"}]
  ```

## Related
- driver -> [[drv-127]]
- vehicle -> [[veh-195]]
