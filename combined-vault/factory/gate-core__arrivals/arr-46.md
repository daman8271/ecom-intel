---
type: factory-arr
id: 46
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
- **id:** 46
- **arrival_no:** ARV-20260625-0012
- **vehicle:** 234
- **vehicle_no:** DL01LAJ1087
- **driver:** 278
- **driver_name:** Reet lal 9911364119
- **gate_in_date:** 2026-06-25
- **in_time:** 11:48:00
- **tare_weight:** 2300.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 14:50:59
- **departed_at:** 2026-06-25T14:50:59.113369+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 159, "entry_no": "EVGI-20260625-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T14:50:59.113369+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 156, "entry_no": "DOCK-20260625-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000089", "sap_doc_num": "626068209"}]
  ```

## Related
- driver -> [[drv-278]]
- vehicle -> [[veh-234]]
