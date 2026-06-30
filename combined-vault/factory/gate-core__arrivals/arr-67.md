---
type: factory-arr
id: 67
title: "DL01LAG7948"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAG7948

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 67
- **arrival_no:** ARV-20260626-0010
- **vehicle:** 319
- **vehicle_no:** DL01LAG7948
- **driver:** 282
- **driver_name:** Ramsaroop 9956925913
- **gate_in_date:** 2026-06-26
- **in_time:** 12:37:00
- **tare_weight:** 1460.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 18:14:26
- **departed_at:** 2026-06-26T18:14:26.892835+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 180, "entry_no": "EVGI-20260626-0010", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-26T18:14:26.892835+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 179, "entry_no": "DOCK-20260626-0013", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000043", "sap_doc_num": "626060304, 626060413"}]
  ```

## Related
- driver -> [[drv-282]]
- vehicle -> [[veh-319]]
