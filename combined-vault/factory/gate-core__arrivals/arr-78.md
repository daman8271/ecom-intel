---
type: factory-arr
id: 78
title: "DL01GE5049"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01GE5049

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 78
- **arrival_no:** ARV-20260627-0003
- **vehicle:** 325
- **vehicle_no:** DL01GE5049
- **driver:** 289
- **driver_name:** Rajkumar 7451089453
- **gate_in_date:** 2026-06-27
- **in_time:** 09:42:00
- **tare_weight:** 7070.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 16:22:05
- **departed_at:** 2026-06-27T16:22:05.078634+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 191, "entry_no": "EVGI-20260627-0003", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-27T16:22:05.078634+05:30", "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 191, "entry_no": "DOCK-20260627-0006", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000027", "sap_doc_num": "606260176, 606260177, 606260178"}]
  ```

## Related
- driver -> [[drv-289]]
- vehicle -> [[veh-325]]
