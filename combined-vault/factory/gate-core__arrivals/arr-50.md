---
type: factory-arr
id: 50
title: "DL01LAC8007"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAC8007

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 50
- **arrival_no:** ARV-20260625-0016
- **vehicle:** 205
- **vehicle_no:** DL01LAC8007
- **driver:** 230
- **driver_name:** Pappu 9817807988
- **gate_in_date:** 2026-06-25
- **in_time:** 14:08:00
- **tare_weight:** 2100.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 16:12:59
- **departed_at:** 2026-06-25T16:12:59.159252+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 163, "entry_no": "EVGI-20260625-0016", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T16:12:59.159252+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 160, "entry_no": "DOCK-20260625-0015", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000091", "sap_doc_num": "626068090, 626068208"}]
  ```

## Related
- driver -> [[drv-230]]
- vehicle -> [[veh-205]]
