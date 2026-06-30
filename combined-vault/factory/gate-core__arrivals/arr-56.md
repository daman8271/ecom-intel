---
type: factory-arr
id: 56
title: "DL01MB2623"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01MB2623

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 56
- **arrival_no:** ARV-20260625-0022
- **vehicle:** 198
- **vehicle_no:** DL01MB2623
- **driver:** 229
- **driver_name:** Jaivind 9582295755
- **gate_in_date:** 2026-06-25
- **in_time:** 18:54:00
- **tare_weight:** 5680.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 22:18:38
- **departed_at:** 2026-06-25T22:18:38.105193+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 169, "entry_no": "EVGI-20260625-0022", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T22:18:38.105193+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 166, "entry_no": "DOCK-20260625-0021", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000095", "sap_doc_num": "626068194, 626068195"}]
  ```

## Related
- driver -> [[drv-229]]
- vehicle -> [[veh-198]]
