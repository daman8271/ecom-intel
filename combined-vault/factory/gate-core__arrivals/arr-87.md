---
type: factory-arr
id: 87
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
- **id:** 87
- **arrival_no:** ARV-20260627-0012
- **vehicle:** 310
- **vehicle_no:** DL01LAN7988
- **driver:** 273
- **driver_name:** Anshul 8700393584
- **gate_in_date:** 2026-06-27
- **in_time:** 13:48:00
- **tare_weight:** 2500.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 18:56:45
- **departed_at:** 2026-06-27T18:56:45.458463+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 201, "entry_no": "EVGI-20260627-0013", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T18:56:45.458463+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 205, "entry_no": "DOCK-20260627-0020", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000116", "sap_doc_num": "626068229"}]
  ```

## Related
- driver -> [[drv-273]]
- vehicle -> [[veh-310]]
