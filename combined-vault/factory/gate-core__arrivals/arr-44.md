---
type: factory-arr
id: 44
title: "DL01LAN4065"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAN4065

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 44
- **arrival_no:** ARV-20260625-0010
- **vehicle:** 312
- **vehicle_no:** DL01LAN4065
- **driver:** 277
- **driver_name:** Nishant 9311242313
- **gate_in_date:** 2026-06-25
- **in_time:** 11:31:00
- **tare_weight:** 1730.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-25
- **out_time:** 12:52:00
- **departed_at:** 2026-06-25T12:52:00.490294+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 157, "entry_no": "EVGI-20260625-0010", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-25T12:52:00.490294+05:30", "cover_count": 1}]
  ```
- **gate_outs:**
  ```json
  [{"id": 153, "entry_no": "DOCK-20260625-0008", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000086", "sap_doc_num": "626068192"}]
  ```

## Related
- driver -> [[drv-277]]
- vehicle -> [[veh-312]]
