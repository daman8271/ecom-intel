---
type: factory-arr
id: 51
title: "HR67C8170"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67C8170

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 51
- **arrival_no:** ARV-20260625-0017
- **vehicle:** 253
- **vehicle_no:** HR67C8170
- **driver:** 28
- **driver_name:** krishan
- **gate_in_date:** 2026-06-25
- **in_time:** 14:53:00
- **tare_weight:** 5470.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 18:58:31
- **departed_at:** 2026-06-25T18:58:31.421807+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 164, "entry_no": "EVGI-20260625-0017", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-25T18:58:31.421807+05:30", "cover_count": 7}]
  ```
- **gate_outs:**
  ```json
  [{"id": 159, "entry_no": "DOCK-20260625-0014", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000038", "sap_doc_num": "626060341, 626060353, 626060434, 626060435, 626060440, 626060441, 626060442"}]
  ```

## Related
- driver -> [[drv-28]]
- vehicle -> [[veh-253]]
