---
type: factory-arr
id: 1
title: "HR67C6723"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# HR67C6723

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 1
- **arrival_no:** ARV-20260622-0001
- **vehicle:** 301
- **vehicle_no:** HR67C6723
- **driver:** 264
- **driver_name:** Atul 9050073318
- **gate_in_date:** 2026-06-22
- **in_time:** 12:18:00
- **tare_weight:** 2200.000
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
  [{"id": 99, "entry_no": "EVGI-20260622-0012", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": null, "cover_count": 1}, {"id": 98, "entry_no": "EVGI-20260622-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": null, "cover_count": 2}, {"id": 95, "entry_no": "EVGI-20260622-0008", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "retired_at": null, "cover_count": 8}]
  ```
- **gate_outs:**
  ```json
  [{"id": 109, "entry_no": "DOCK-20260622-0015", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "DOCKED", "gatepass_no": null, "sap_doc_num": "626060377, 626060378"}, {"id": 106, "entry_no": "DOCK-20260622-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "PRINT_COMMITTED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000057", "sap_doc_num": "626067978, 626067981"}, {"id": 104, "entry_no": "DOCK-20260622-0010", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DOCKED", "gatepass_no": null, "sap_doc_num": "606260149"}, {"id": 102, "entry_no": "DOCK-20260622-0008", "company_id": 1, "company_code": "JIVO_OIL", "company_name": "Jivo Oil", "status": "PRINT_COMMITTED", "gatepass_no": "DCK/JIVO_OIL/2026-27/000028", "sap_doc_num": "626060198, 626060203, 626060207, 626060220, 626060255, 626060261"}]
  ```

## Related
- driver -> [[drv-264]]
- vehicle -> [[veh-301]]
