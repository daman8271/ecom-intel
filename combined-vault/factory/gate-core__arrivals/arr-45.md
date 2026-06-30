---
type: factory-arr
id: 45
title: "DL01LAN7988"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN7988

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 45
- **arrival_no:** ARV-20260625-0011
- **vehicle:** 310
- **vehicle_no:** DL01LAN7988
- **driver:** 273
- **driver_name:** Anshul 8700393584
- **gate_in_date:** 2026-06-25
- **in_time:** 11:45:00
- **tare_weight:** 2500.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 14:51:48
- **departed_at:** 2026-06-25T14:51:48.585218+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 158, "entry_no": "EVGI-20260625-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T14:51:48.585218+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 157, "entry_no": "DOCK-20260625-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000090", "sap_doc_num": "626068225"}]
  ```

## Related
- driver -> [[drv-273]]
- vehicle -> [[veh-310]]
