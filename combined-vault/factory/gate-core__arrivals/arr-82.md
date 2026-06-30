---
type: factory-arr
id: 82
title: "DL01MB2623"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01MB2623

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 82
- **arrival_no:** ARV-20260627-0007
- **vehicle:** 198
- **vehicle_no:** DL01MB2623
- **driver:** 229
- **driver_name:** Jaivind 9582295755
- **gate_in_date:** 2026-06-27
- **in_time:** 10:42:00
- **tare_weight:** 5680.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 14:50:07
- **departed_at:** 2026-06-27T14:50:07.339113+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 196, "entry_no": "EVGI-20260627-0008", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-27T14:50:07.339113+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 189, "entry_no": "DOCK-20260627-0004", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000026", "sap_doc_num": "606260175"}]
  ```

## Related
- driver -> [[drv-229]]
- vehicle -> [[veh-198]]
