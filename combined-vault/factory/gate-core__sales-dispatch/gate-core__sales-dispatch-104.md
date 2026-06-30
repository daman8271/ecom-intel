---
type: factory-gate-core__sales-dispatch
id: 104
title: "HR67C6723"
entity: Sales Dispatch
source_endpoint: /gate-core/sales-dispatch/
company: JIVO_MART
tags:
  - type/factory-gate-core__sales-dispatch
  - source/factory
  - company/JIVO_MART
---
# HR67C6723

> Sales Dispatch from `/gate-core/sales-dispatch/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 104
- **entry_no:** DOCK-20260622-0010
- **company:** 2
- **company_code:** JIVO_MART
- **company_name:** Jivo Mart
- **arrival:** 1
- **arrival_status:** LOADING
- **arrival_company_count:** 3
- **arrival_can_depart:** False
- **gatepass_print_locked:** False
- **gatepass_lock_reason:** 
- **vehicle_entry:** 935
- **vehicle_entry_no:** DOCKV-20260622-0010
- **vehicle_entry_status:** IN_PROGRESS
- **dispatch_plan:** 431
- **vehicle:** 301
- **transporter:** 85
- **driver:** 264
- **dispatch_date:** 2026-06-19
- **documents:**
  ```json
  [{"id": 191, "dispatch_plan": 431, "document_type": "INVOICE", "sap_doc_entry": 34928, "sap_doc_num": "606260149", "sap_doc_date": "2026-06-18", "sap_doc_total": "130899.00", "sap_branch_id": 2, "sap_branch_name": "HARYANA", "sap_reference": "1706264604", "sap_comments": "", "customer_code": "CUSTA000773", "customer_name": "BAGRRYS INDIA PRIVATE LIMITED (AABCB8144N)", "ship_to_code": "BAGRRYS INDIA PRIVATE LIMITED BADDI", "ship_to_address": "SOLAN-173205\rIN", "place_of_supply": "HP", "bp_gstin": "02AABCB8144N2ZN", "eway_bill": "", "from_warehouse": "", "to_warehouse": "", "warehouses": "BH-FGM", "item_summary": "FG0000053 - COLD PRESS SUNFLOWER 5 LTR 4 PCS", "base_refs": "1706264604", "total_quantity": "154.000", "total_litres": "3080.000", "total_boxes": "0.000", "total_weight": "756.525", "created_at": "2026-06-22T16:21:40.494627+05:30", "updated_at": "2026-06-22T16:21:40.494641+05:30"}]
  ```
- **document_count:** 1
- **document_numbers:**
  ```json
  ["606260149"]
  ```
- **document_type:** INVOICE
- **sap_doc_entry:** 34928
- **sap_doc_num:** 606260149
- **sap_doc_date:** 2026-06-18
- **sap_doc_total:** 130899.00
- **sap_branch_id:** 2
- **sap_branch_name:** HARYANA
- **sap_reference:** 1706264604
- **sap_comments:** 
- **customer_code:** CUSTA000773
- **customer_name:** BAGRRYS INDIA PRIVATE LIMITED (AABCB8144N)
- **ship_to_code:** BAGRRYS INDIA PRIVATE LIMITED BADDI
- **ship_to_address:** SOLAN-173205IN
- **place_of_supply:** HP
- **bp_gstin:** 02AABCB8144N2ZN
- **eway_bill:** 
- **from_warehouse:** 
- **to_warehouse:** 
- **warehouses:** BH-FGM
- **item_summary:** FG0000053 - COLD PRESS SUNFLOWER 5 LTR 4 PCS
- **base_refs:** 1706264604
- **total_quantity:** 154.000
- **total_litres:** 3080.000
- **total_boxes:** 0.000
- **total_weight:** 756.525
- **challan_weight:** None
- **challan_weight_at:** None
- **challan_weight_by:** None
- **challan_weight_by_name:** 
- **vehicle_no:** HR67C6723
- **transporter_name:** PICK & SHIP
- **transporter_gstin:** 09AAQCP4145A1ZF
- **transporter_contact_person:** shukla
- **transporter_mobile_no:** 9958007610
- **driver_name:** Atul 9050073318
- **driver_mobile_no:** 9050073318
- **driver_license_no:** HR6020170001271
- **driver_id_proof_type:** Other
- **driver_id_proof_number:** HR6020170001271
- **bilty_no:** 2519
- **bilty_date:** 2026-06-22
- **freight:** None
- **total_freight:** None
- **dock_incharge:** 
- **docked_at:** 2026-06-22T16:21:40.490436+05:30
- **gate_out_date:** None
- **out_time:** None
- **security_name:** 
- **truck_photo:** None
- **photo_latitude:** None
- **photo_longitude:** None
- **photo_uploaded_by:** None
- **photo_uploaded_at:** None
- **gatepass_no:** None
- **random_code:** 
- **qr_payload:** 
- **uom:** 
- **physical_quantity:** None
- **seal_number:** 
- **pgi_reference:** 
- **printed_by:** None
- **printed_at:** None
- **print_committed_by:** None
- **print_committed_at:** None
- **dispatched_by:** None
- **dispatched_at:** None
- **status:** DOCKED
- **remarks:** 
- **reject_reason:** 
- **rejected_by:** None
- **rejected_at:** None
- **cancel_reason:** 
- **cancelled_by:** None
- **cancelled_at:** None
- **gross_weight:** None
- **tare_weight:** 2200.0
- **net_weight:** 0.0
- **weighbridge_slip_no:** 
- **first_weighment_time:** None
- **second_weighment_time:** None
- **items:**
  ```json
  [{"id": 475, "document": 191, "document_sap_doc_num": "606260149", "line_num": 0, "item_code": "FG0000053", "item_name": "COLD PRESS SUNFLOWER 5 LTR 4 PCS", "quantity": "154.000", "uom": "PCS", "rate": "809.5200", "line_total": "124666.08", "gross_total": "130899.38", "warehouse_code": "BH-FGM", "from_warehouse": "", "to_warehouse": "", "base_ref": "1706264604", "base_entry": 10472, "base_type": 17, "tax_code": "IGST@5", "total_litres": "3080.000", "total_boxes": "0.000", "total_weight": "756.525"}]
  ```
- **created_at:** 2026-06-22T16:21:40.491257+05:30
- **updated_at:** 2026-06-22T16:21:40.491302+05:30

## Related
- arrival -> [[arr-1]]
- company -> [[comp-2]]
- driver -> [[drv-264]]
- transporter -> [[trn-85]]
- vehicle -> [[veh-301]]
