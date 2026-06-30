---
type: factory-arr
id: 69
title: "DL01LAJ1087"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAJ1087

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 69
- **arrival_no:** ARV-20260626-0012
- **vehicle:** 234
- **vehicle_no:** DL01LAJ1087
- **driver:** 278
- **driver_name:** Reet lal 9911364119
- **gate_in_date:** 2026-06-26
- **in_time:** 14:25:00
- **tare_weight:** 2290.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 16:38:25
- **departed_at:** 2026-06-26T16:38:25.129477+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 182, "entry_no": "EVGI-20260626-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-26T16:38:25.129477+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 180, "entry_no": "DOCK-20260626-0014", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000103", "sap_doc_num": "626068238"}]
  ```

## Related
- driver -> [[drv-278]]
- vehicle -> [[veh-234]]
