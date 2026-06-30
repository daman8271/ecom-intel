---
type: factory-barcode__dispatch__sessions__active
id: 182
title: "Active 182"
entity: Active
source_endpoint: /barcode/dispatch/sessions/active/
company: JIVO_MART
tags:
  - type/factory-barcode__dispatch__sessions__active
  - source/factory
  - company/JIVO_MART
---
# Active 182

> Active from `/barcode/dispatch/sessions/active/` (Jivo Mart / JIVO_MART).

## Fields
- **id:** 182
- **bill_number:** 706260388
- **sap_system_type:** BUSINESS_ONE
- **sap_object_type:** AR_INVOICE
- **sap_doc_entry:** 34784
- **sap_doc_num:** 706260388
- **delivery_number:** 1706264513
- **reference_delivery_number:** 1706264513
- **customer_code:** CUSTA000048
- **customer_name:** R K WORLDINFOCOM PVT LTD
- **ship_to_code:** R K WORLDINFOCOM  KOLAR
- **ship_to_name:** VILLAGE NARASPURA HOBLI  SURVEY 1105 BELLURU KRISHNAPURAKOLAR TALUK-563133IN
- **bill_date:** 2026-06-17
- **status:** PARTIAL
- **total_expected_qty:** 54.000
- **total_scanned_qty:** 24.000
- **pending_qty:** 30.000
- **total_remaining_qty:** 8.000
- **removed_box_count:** 0
- **sap_dispatch_status:** DISPATCHED
- **sap_update_status:** NOT_CONFIGURED
- **sap_update_error:** 
- **sap_sync_status:** NOT_CONFIGURED
- **sap_sync_error:** 
- **started_at:** 2026-06-20T18:44:10.539940+05:30
- **completed_at:** None
- **dispatched_at:** None
- **dispatched_by:** None
- **dispatched_by_name:** 
- **completed_by:** None
- **completed_by_name:** 
- **closed_at:** None
- **closed_by:** None
- **closed_by_name:** 
- **close_reason:** 
- **cancelled_at:** None
- **cancel_reason:** 
- **created_by:** 37
- **created_by_name:** Sonu
- **created_at:** 2026-06-20T18:43:57.561691+05:30
- **updated_at:** 2026-06-20T18:44:13.969218+05:30
- **line_count:** 2
- **completed_line_count:** 1
- **accepted_scan_count:** 2
- **rejected_scan_count:** 2
- **pallet_scan_count:** 0
- **box_scan_count:** 2
- **active_line:**
  ```json
  {"id": 574, "sequence_no": 2, "sap_line_no": "6", "material_code": "FG0000192", "material_description": "SOYABEAN OIL 5 LTR 4 PCS", "bill_qty": "30.000", "expected_qty": "30.000", "scanned_qty": "0.000", "remaining_qty": "30.000", "pending_qty": "30.000", "bill_boxes": "7.500", "expected_boxes": "7.500", "scanned_boxes": "0", "pending_boxes": "7.500", "uom": "PCS", "batch_number": "", "warehouse_code": "DL-FG", "serial_required": false, "status": "PENDING"}
  ```
- **can_dispatch:** True
- **can_scan:** True
- **lines:**
  ```json
  [{"id": 573, "sequence_no": 1, "sap_line_no": "2", "material_code": "FG0000227", "material_description": "RICE BRAN 1L 16 PCS", "bill_qty": "24.000", "expected_qty": "24.000", "scanned_qty": "24.000", "remaining_qty": "0.000", "pending_qty": "0.000", "bill_boxes": "1.500", "expected_boxes": "1.500", "scanned_boxes": "2", "pending_boxes": "0", "uom": "PCS", "batch_number": "", "warehouse_code": "DL-FG", "serial_required": false, "status": "COMPLETE"}, {"id": 574, "sequence_no": 2, "sap_line_no": "6", "material_code": "FG0000192", "material_description": "SOYABEAN OIL 5 LTR 4 PCS", "bill_qty": "30.000", "expected_qty": "30.000", "scanned_qty": "0.000", "remaining_qty": "30.000", "pending_qty": "30.000", "bill_boxes": "7.500", "expected_boxes": "7.500", "scanned_boxes": "0", "pending_boxes": "7.500", "uom": "PCS", "batch_number": "", "warehouse_code": "DL-FG", "serial_required": false, "status": "PENDING"}]
  ```
- **scanned_units:**
  ```json
  [{"id": 26604, "line": 573, "scan_log": 6154, "barcode_value": "BOX-20260612-XX-1475", "entity_type": "BOX", "box": 52929, "pallet": 1144, "serial_number": "", "barcode_type": "BOX", "box_barcode": "BOX-20260612-XX-1475", "item_code": "FG0000227", "item_name": "RICE BRAN OIL 1 LTR 16 PCS", "material_code": "FG0000227", "batch_number": "L3  000051", "original_qty": "16.000", "available_qty": "16.000", "required_pending_qty": "24.000", "total_box_qty": "16.000", "dispatch_qty": "16.000", "remaining_qty": "0.000", "qty": "16.000", "uom": "PCS", "warehouse": "BH-PF", "scan_status": "ACTIVE", "status_after_scan": "Full Dispatch", "dispatch_doc_no": "706260388", "dispatch_date_time": null, "scanned_by_name": "Sonu", "customer_name": "R K WORLDINFOCOM PVT LTD", "created_at": "2026-06-20T18:44:10.536762+05:30", "scanned_at": "2026-06-20T18:44:10.536762+05:30"}, {"id": 26605, "line": 573, "scan_log": 6155, "barcode_value": "BOX-20260612-XX-1495", "entity_type": "BOX", "box": 52949, "pallet": 1144, "serial_number": "", "barcode_type": "BOX", "box_barcode": "BOX-20260612-XX-1495", "item_code": "FG0000227", "item_name": "RICE BRAN OIL 1 LTR 16 PCS", "material_code": "FG0000227", "batch_number": "L3  000051", "original_qty": "16.000", "available_qty": "16.000", "required_pending_qty": "8.000", "total_box_qty": "16.000", "dispatch_qty": "8.000", "remaining_qty": "8.000", "qty": "8.000", "uom": "PCS", "warehouse": "BH-PF", "scan_status": "ACTIVE", "status_after_scan": "Partial Dispatch", "dispatch_doc_no": "706260388", "dispatch_date_time": null, "scanned_by_name": "Sonu", "customer_name": "R K WORLDINFOCOM PVT LTD", "created_at": "2026-06-20T18:44:13.964252+05:30", "scanned_at": "2026-06-20T18:44:13.964252+05:30"}]
  ```
