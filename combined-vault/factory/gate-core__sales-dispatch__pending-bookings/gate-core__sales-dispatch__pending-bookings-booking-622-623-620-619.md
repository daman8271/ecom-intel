---
type: factory-gate-core__sales-dispatch__pending-bookings
id: booking:622,623,620,619
title: "DL01LAD1397"
entity: Pending Bookings
source_endpoint: /gate-core/sales-dispatch/pending-bookings/
company: JIVO_MART
tags:
  - type/factory-gate-core__sales-dispatch__pending-bookings
  - source/factory
  - company/JIVO_MART
---
# DL01LAD1397

> Pending Bookings from `/gate-core/sales-dispatch/pending-bookings/` (Jivo Mart / JIVO_MART).

## Fields
- **row_type:** PENDING_BOOKING
- **id:** booking:622,623,620,619
- **company:** 2
- **company_code:** JIVO_MART
- **company_name:** Jivo Mart
- **dispatch_plan_ids:**
  ```json
  [622, 623, 620, 619]
  ```
- **document_count:** 4
- **document_numbers:**
  ```json
  ["706260620", "706260625", "706260627", "706260628"]
  ```
- **documents:**
  ```json
  [{"document_type": "INVOICE", "doc_entry": 35186, "doc_num": "706260620", "doc_date": null, "doc_total": 587785.0, "card_code": "", "card_name": "", "place_of_supply": "KT", "eway_bill": "", "vehicle_no": "DL01LAD1397", "transporter_name": "PICK & SHIP", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 2604.0, "total_weight": 2588.049, "line_count": 0, "items": [], "plan": {"id": 622, "sap_invoice_doc_entry": 35186, "sap_invoice_doc_num": "706260620", "booking_status": "BOOKED"}}, {"document_type": "INVOICE", "doc_entry": 35194, "doc_num": "706260625", "doc_date": null, "doc_total": 527842.0, "card_code": "", "card_name": "", "place_of_supply": "KT", "eway_bill": "", "vehicle_no": "DL01LAD1397", "transporter_name": "PICK & SHIP", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 2438.0, "total_weight": 2409.628, "line_count": 0, "items": [], "plan": {"id": 623, "sap_invoice_doc_entry": 35194, "sap_invoice_doc_num": "706260625", "booking_status": "BOOKED"}}, {"document_type": "INVOICE", "doc_entry": 35197, "doc_num": "706260627", "doc_date": null, "doc_total": 120144.0, "card_code": "", "card_name": "", "place_of_supply": "WB", "eway_bill": "", "vehicle_no": "DL01LAD1397", "transporter_name": "PICK & SHIP", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 484.0, "total_weight": 501.599, "line_count": 0, "items": [], "plan": {"id": 620, "sap_invoice_doc_entry": 35197, "sap_invoice_doc_num": "706260627", "booking_status": "BOOKED"}}, {"document_type": "INVOICE", "doc_entry": 35198, "doc_num": "706260628", "doc_date": null, "doc_total": 525540.0, "card_code": "", "card_name": "", "place_of_supply": "KT", "eway_bill": "", "vehicle_no": "DL01LAD1397", "transporter_name": "PICK & SHIP", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 1646.0, "total_weight": 1810.99, "line_count": 0, "items": [], "plan": {"id": 619, "sap_invoice_doc_entry": 35198, "sap_invoice_doc_num": "706260628", "booking_status": "BOOKED"}}]
  ```
- **document_type:** INVOICE
- **sap_doc_entry:** 35186
- **sap_doc_num:** 706260620, 706260625, 706260627, 706260628
- **sap_doc_date:** None
- **sap_doc_total:** 1761311.0
- **customer_code:** CUSTA000048
- **customer_name:** R K WORLDINFOCOM PVT LTD
- **place_of_supply:** KT, WB
- **eway_bill:** 
- **item_summary:** Oil
- **total_litres:** 7172.0
- **total_weight:** 7310.266
- **vehicle:** 334
- **vehicle_entry:** 1899
- **vehicle_entry_no:** EVGI-20260713-0017
- **vehicle_no:** DL01LAD1397
- **transporter:** 85
- **transporter_name:** PICK & SHIP
- **transporter_gstin:** 09AAQCP4145A1ZF
- **transporter_contact_person:** shukla
- **transporter_mobile_no:** 9958007610
- **driver:** 398
- **driver_name:** Tinku 8506002256
- **driver_mobile_no:** 8506002256
- **driver_license_no:** UP3620230012872
- **driver_id_proof_type:** Other
- **driver_id_proof_number:** UP3620230012872
- **bilty_no:** 
- **bilty_date:** None
- **freight:** None
- **total_freight:** None
- **dispatch_date:** 2026-06-26
- **gate_out_date:** None
- **out_time:** None
- **gatepass_no:** None
- **status:** PENDING_DOCKING
- **created_at:** 2026-06-25T13:31:28.926420Z
- **updated_at:** 2026-07-13T09:31:12.862627Z

## Related
- company -> [[comp-2]]
- driver -> [[drv-398]]
- transporter -> [[trn-85]]
- vehicle -> [[veh-334]]
