---
type: factory-arr
id: 13
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
- **id:** 13
- **arrival_no:** ARV-20260623-0010
- **vehicle:** 198
- **vehicle_no:** DL01MB2623
- **driver:** 229
- **driver_name:** Jaivind 9582295755
- **gate_in_date:** 2026-06-23
- **in_time:** 11:33:00
- **tare_weight:** 5690.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 11:06:38
- **departed_at:** 2026-06-25T11:06:38.300223+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 125, "entry_no": "EVGI-20260624-0007", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-24T14:22:30.231665+05:30", "cover_count": 2}, {"id": 111, "entry_no": "EVGI-20260623-0010", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": "2026-06-23T17:35:03.740146+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 127, "entry_no": "DOCK-20260624-0001", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "CANCELLED", "gatepass_no": null, "sap_doc_num": "626060425, 626060426"}, {"id": 120, "entry_no": "DOCK-20260623-0011", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000016", "sap_doc_num": "606260163"}]
  ```

## Related
- driver -> [[drv-229]]
- vehicle -> [[veh-198]]
