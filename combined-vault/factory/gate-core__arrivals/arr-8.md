---
type: factory-arr
id: 8
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
- **id:** 8
- **arrival_no:** ARV-20260623-0005
- **vehicle:** 194
- **vehicle_no:** DL01LX3089
- **driver:** 177
- **driver_name:** PAWAN
- **gate_in_date:** 2026-06-23
- **in_time:** 10:08:00
- **tare_weight:** 3770.000
- **weighbridge_slip_no:** 
- **security_name:** Deepak
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 14:21:36
- **departed_at:** 2026-06-24T14:21:36.636810+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 129, "entry_no": "EVGI-20260624-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T11:04:12.216608+05:30", "cover_count": 1}, {"id": 126, "entry_no": "EVGI-20260624-0008", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:37:08.987488+05:30", "cover_count": 1}, {"id": 106, "entry_no": "EVGI-20260623-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T12:23:29.821463+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 115, "entry_no": "DOCK-20260623-0006", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000060", "sap_doc_num": "626068174"}]
  ```

## Related
- driver -> [[drv-177]]
- vehicle -> [[veh-194]]
