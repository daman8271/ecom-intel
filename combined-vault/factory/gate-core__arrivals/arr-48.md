---
type: factory-arr
id: 48
title: "DL01LAN0395"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN0395

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 48
- **arrival_no:** ARV-20260625-0014
- **vehicle:** 259
- **vehicle_no:** DL01LAN0395
- **driver:** 248
- **driver_name:** Saurav 8802622617
- **gate_in_date:** 2026-06-25
- **in_time:** 11:55:00
- **tare_weight:** 1730.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 14:10:41
- **departed_at:** 2026-06-25T14:10:41.661437+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 161, "entry_no": "EVGI-20260625-0014", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T14:10:41.661437+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 155, "entry_no": "DOCK-20260625-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000087", "sap_doc_num": "626068214"}]
  ```

## Related
- driver -> [[drv-248]]
- vehicle -> [[veh-259]]
