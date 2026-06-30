---
type: factory-arr
id: 64
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
- **id:** 64
- **arrival_no:** ARV-20260626-0007
- **vehicle:** 193
- **vehicle_no:** DL01LY5728
- **driver:** 224
- **driver_name:** DULLI CHAND
- **gate_in_date:** 2026-06-26
- **in_time:** 11:00:00
- **tare_weight:** 4610.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-26
- **out_time:** 12:53:51
- **departed_at:** 2026-06-26T12:53:51.329622+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 177, "entry_no": "EVGI-20260626-0007", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-26T12:53:51.329622+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 169, "entry_no": "DOCK-20260626-0003", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000040", "sap_doc_num": "626060463"}]
  ```

## Related
- driver -> [[drv-224]]
- vehicle -> [[veh-193]]
