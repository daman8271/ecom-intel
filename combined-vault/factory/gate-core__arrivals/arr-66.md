---
type: factory-arr
id: 66
title: "HR67D9270"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67D9270

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 66
- **arrival_no:** ARV-20260626-0009
- **vehicle:** 217
- **vehicle_no:** HR67D9270
- **driver:** 251
- **driver_name:** Binder
- **gate_in_date:** 2026-06-26
- **in_time:** 11:34:00
- **tare_weight:** 5560.000
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
  [{"id": 179, "entry_no": "EVGI-20260626-0009", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": null, "cover_count": 3}]
  ```
- **gate_outs:**
  ```json
  [{"id": 172, "entry_no": "DOCK-20260626-0006", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DOCKED", "gatepass_no": null, "sap_doc_num": "626060447"}, {"id": 171, "entry_no": "DOCK-20260626-0005", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000041", "sap_doc_num": "626060452, 626060466"}]
  ```

## Related
- driver -> [[drv-251]]
- vehicle -> [[veh-217]]
