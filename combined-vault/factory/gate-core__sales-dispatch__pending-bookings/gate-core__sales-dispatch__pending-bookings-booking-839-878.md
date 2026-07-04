---
type: factory-gate-core__sales-dispatch__pending-bookings
id: booking:839,878
title: "RJ11GD2869"
entity: Pending Bookings
source_endpoint: /gate-core/sales-dispatch/pending-bookings/
company: JIVO_MART
tags:
  - type/factory-gate-core__sales-dispatch__pending-bookings
  - source/factory
  - company/JIVO_MART
---
# RJ11GD2869

> Pending Bookings from `/gate-core/sales-dispatch/pending-bookings/` (Jivo Mart / JIVO_MART).

## Fields
- **row_type:** PENDING_BOOKING
- **id:** booking:839,878
- **company:** 2
- **company_code:** JIVO_MART
- **company_name:** Jivo Mart
- **dispatch_plan_ids:**
  ```json
  [839, 878]
  ```
- **document_count:** 2
- **document_numbers:**
  ```json
  ["606260189", "607260105"]
  ```
- **documents:**
  ```json
  [{"document_type": "INVOICE", "doc_entry": 35568, "doc_num": "606260189", "doc_date": null, "doc_total": null, "card_code": "", "card_name": "", "place_of_supply": "KT", "eway_bill": "", "vehicle_no": "RJ11GD2869", "transporter_name": "Abhiman Express", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 5.0, "total_weight": 4.854, "line_count": 0, "items": [], "plan": {"id": 839, "sap_invoice_doc_entry": 35568, "sap_invoice_doc_num": "606260189", "booking_status": "BOOKED"}}, {"document_type": "INVOICE", "doc_entry": 35823, "doc_num": "607260105", "doc_date": null, "doc_total": 1417500.0, "card_code": "", "card_name": "", "place_of_supply": "KT", "eway_bill": "", "vehicle_no": "RJ11GD2869", "transporter_name": "Abhiman Express", "bilty_no": "", "bilty_date": null, "item_summary": "Oil", "total_litres": 9000.0, "total_weight": 8752.5, "line_count": 0, "items": [], "plan": {"id": 878, "sap_invoice_doc_entry": 35823, "sap_invoice_doc_num": "607260105", "booking_status": "BOOKED"}}]
  ```
- **document_type:** INVOICE
- **sap_doc_entry:** 35568
- **sap_doc_num:** 606260189, 607260105
- **sap_doc_date:** None
- **sap_doc_total:** 1417500.0
- **customer_code:** CUSTA000592
- **customer_name:** KNOWTABLE ONLINE SERVICES PRIVATE LIMITED
- **place_of_supply:** KT
- **eway_bill:** 
- **item_summary:** Oil
- **total_litres:** 9005.0
- **total_weight:** 8757.354
- **vehicle:** 365
- **vehicle_entry:** 1436
- **vehicle_entry_no:** EVGI-20260703-0009
- **vehicle_no:** RJ11GD2869
- **transporter:** 77
- **transporter_name:** Abhiman Express
- **transporter_gstin:** 
- **transporter_contact_person:** ABHISHEK SHARMA
- **transporter_mobile_no:** 8700926578
- **driver:** 327
- **driver_name:** Fareed 6006814214
- **driver_mobile_no:** 6006814214
- **driver_license_no:** JK0820110023815
- **driver_id_proof_type:** Other
- **driver_id_proof_number:** JK0820110023815
- **bilty_no:** 
- **bilty_date:** None
- **freight:** None
- **total_freight:** None
- **dispatch_date:** 2026-07-02
- **gate_out_date:** None
- **out_time:** None
- **gatepass_no:** None
- **status:** PENDING_DOCKING
- **created_at:** 2026-07-02T07:51:27.690521Z
- **updated_at:** 2026-07-03T09:14:18.910881Z

## Related
- company -> [[comp-2]]
- driver -> [[drv-327]]
- transporter -> [[trn-77]]
- vehicle -> [[veh-365]]
