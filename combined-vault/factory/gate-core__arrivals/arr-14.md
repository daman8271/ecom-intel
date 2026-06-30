---
type: factory-arr
id: 14
title: "DL01LY5728"
entity: Gate Arrival
source_endpoint: /gate-core/arrivals/
company: JIVO_MART
tags:
  - type/factory-arr
  - source/factory
  - company/JIVO_MART
---
# DL01LY5728

> Gate Arrival from `/gate-core/arrivals/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 14
- **arrival_no:** ARV-20260623-0011
- **vehicle:** 193
- **vehicle_no:** DL01LY5728
- **driver:** 224
- **driver_name:** DULLI CHAND
- **gate_in_date:** 2026-06-23
- **in_time:** 11:37:00
- **tare_weight:** 4610.000
- **weighbridge_slip_no:** 
- **security_name:** Sachin
- **remarks:** 
- **status:** DEPARTED
- **gate_out_date:** 2026-06-24
- **out_time:** 13:40:15
- **departed_at:** 2026-06-24T13:40:15.638459+05:30
- **gatepass_no:** None
- **gatepass_printed_at:** None
- **gatepass_committed_at:** None
- **gate_ins:**
  ```json
  [{"id": 130, "entry_no": "EVGI-20260624-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T13:40:15.638459+05:30", "cover_count": 4}, {"id": 123, "entry_no": "EVGI-20260624-0005", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-24T10:34:04.160271+05:30", "cover_count": 4}, {"id": 112, "entry_no": "EVGI-20260623-0011", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "retired_at": "2026-06-23T15:48:40.607331+05:30", "cover_count": 2}]
  ```
- **gate_outs:**
  ```json
  [{"id": 133, "entry_no": "DOCK-20260624-0007", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000072", "sap_doc_num": "626068204, 626068205, 626068206, 626068207"}, {"id": 121, "entry_no": "DOCK-20260623-0012", "company_id": 3, "company_code": "JIVO_BEVERAGES", "company_name": "Jivo Beverages", "status": "DISPATCHED", "gatepass_no": "DCK/JIVO_BEVERAGES/2026-27/000065", "sap_doc_num": "626068185, 626068186"}]
  ```

## Related
- driver -> [[drv-224]]
- vehicle -> [[veh-193]]
