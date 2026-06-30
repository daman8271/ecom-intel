---
type: factory-arr
id: 90
title: "DL01LAL2818"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAL2818

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 90
- **arrival_no:** ARV-20260627-0015
- **vehicle:** 291
- **vehicle_no:** DL01LAL2818
- **driver:** 286
- **driver_name:** Ajay 8510944121
- **gate_in_date:** 2026-06-27
- **in_time:** 14:54:00
- **tare_weight:** 2190.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-27
- **out_time:** 19:01:22
- **departed_at:** 2026-06-27T19:01:22.307857+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 210, "entry_no": "EVGI-20260627-0022", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-27T19:01:22.307857+05:30", "cover_count": 1}, {"id": 204, "entry_no": "EVGI-20260627-0016", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": "2026-06-27T17:29:00.907105+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 206, "entry_no": "DOCK-20260627-0021", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000117", "sap_doc_num": "626068257"}, {"id": 196, "entry_no": "DOCK-20260627-0011", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "CANCELLED", "gatepass_no": null, "sap_doc_num": "626060469"}]
  ```

## Related
- driver -> [[drv-286]]
- vehicle -> [[veh-291]]
