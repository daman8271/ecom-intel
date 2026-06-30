---
type: factory-arr
id: 88
title: "DL01LAD1397"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LAD1397

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 88
- **arrival_no:** ARV-20260627-0013
- **vehicle:** 334
- **vehicle_no:** DL01LAD1397
- **driver:** 294
- **driver_name:** Arun 9667679734
- **gate_in_date:** 2026-06-27
- **in_time:** 13:58:00
- **tare_weight:** 4530.000
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
  [{"id": 202, "entry_no": "EVGI-20260627-0014", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "retired_at": null, "cover_count": 5}]
  ```
- **gate_outs:**
  ```json
  [{"id": 200, "entry_no": "DOCK-20260627-0015", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DOCKED", "gatepass_no": null, "sap_doc_num": "706260620, 706260625, 706260627, 706260628"}, {"id": 199, "entry_no": "DOCK-20260627-0014", "company_id": 2, "company_code": "JIVO_MART", "company_name": "Jivo Mart", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_MART/2026-27/000029", "sap_doc_num": "606260182"}]
  ```

## Related
- driver -> [[drv-294]]
- vehicle -> [[veh-334]]
