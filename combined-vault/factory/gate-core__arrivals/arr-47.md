---
type: factory-arr
id: 47
title: "DL01LAN4204"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN4204

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 47
- **arrival_no:** ARV-20260625-0013
- **vehicle:** 195
- **vehicle_no:** DL01LAN4204
- **driver:** 127
- **driver_name:** MAHESH
- **gate_in_date:** 2026-06-25
- **in_time:** 11:53:00
- **tare_weight:** 4280.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 18:02:41
- **departed_at:** 2026-06-25T18:02:41.765798+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 160, "entry_no": "EVGI-20260625-0013", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-25T18:02:41.765798+05:30", "cover_count": 5}]
  ```
- **gate_outs:**
  ```json
  [{"id": 158, "entry_no": "DOCK-20260625-0013", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000037", "sap_doc_num": "626060407, 626060408, 626060412, 626060437, 626060439"}]
  ```

## Related
- driver -> [[drv-127]]
- vehicle -> [[veh-195]]
