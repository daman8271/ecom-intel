---
type: factory-arr
id: 3
title: "HR67E9670"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67E9670

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 3
- **arrival_no:** ARV-20260622-0003
- **vehicle:** 282
- **vehicle_no:** HR67E9670
- **driver:** 252
- **driver_name:** Vimlesh
- **gate_in_date:** 2026-06-22
- **in_time:** 17:16:00
- **tare_weight:** 6710.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** LOADING
- **gate_out_date:** None
- **out_time:** None
- **departed_at:** None
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 101, "entry_no": "EVGI-20260622-0014", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-22T19:55:57.289034+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 108, "entry_no": "DOCK-20260622-0014", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000029", "sap_doc_num": "626060405"}]
  ```

## Related
- driver -> [[drv-252]]
- vehicle -> [[veh-282]]
