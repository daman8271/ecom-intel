---
type: factory-arr
id: 85
title: "DL01LY5728"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LY5728

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 85
- **arrival_no:** ARV-20260627-0010
- **vehicle:** 193
- **vehicle_no:** DL01LY5728
- **driver:** 224
- **driver_name:** DULLI CHAND
- **gate_in_date:** 2026-06-27
- **in_time:** 11:32:00
- **tare_weight:** 4610.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 17:34:46
- **departed_at:** 2026-06-27T17:34:46.576472+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 199, "entry_no": "EVGI-20260627-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T17:34:46.576472+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 194, "entry_no": "DOCK-20260627-0009", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000114", "sap_doc_num": "626068251"}]
  ```

## Related
- driver -> [[drv-224]]
- vehicle -> [[veh-193]]
