---
type: moc
title: JIVO Factory (Jivo Mart) — Home
tags:
  - moc
  - source/factory
---

# JIVO Factory — Jivo Mart (JIVO_MART)

Lossless capture of the ji.jivo.in factory app for **JIVO_MART** — one note per record, linked by foreign keys. Bridges to product nodes via SAP item code (FG####).


- **Notes:** 49371  ·  **Entity types:** 46  ·  **SAP-bridged item codes:** 421


## Entity hubs by domain


### accounts
- [[_moc-accounts__users|Users]] (62)

### barcode
- [[_moc-barcode__boxes-001|Barcode Box]] (27206)
- [[_moc-barcode__dispatch__reports|Reports]] (57)
- [[_moc-barcode__dispatch__reports__boxes|Boxes]] (1000)
- [[_moc-barcode__dispatch__reports__pallets|Pallets]] (583)
- [[_moc-barcode__dispatch__reports__rejected-scans|Rejected Scans]] (962)
- [[_moc-barcode__dispatch__sessions__active|Active]] (55)
- [[_moc-barcode__dispatch__sessions__completed|Completed]] (2)
- [[_moc-barcode__items__oitm|SAP Item (OITM)]] (420)
- [[_moc-barcode__loose|Loose]] (7)
- [[_moc-barcode__pallets|Pallet]] (583)
- [[_moc-barcode__print__history|History]] (16)
- [[_moc-barcode__scan__history-001|History]] (15031)

### company
- [[_moc-company__companies|Company]] (3)

### daily-needs-gatein
- [[_moc-daily-needs-gatein__gate-entries__daily-need__categories|Categories]] (1)

### dispatch
- [[_moc-dispatch__bilty-grpo__pending|Pending]] (6)

### docking-admin
- [[_moc-docking-admin__partial-scan-requests|Partial Scan Requests]] (21)
- [[_moc-docking-admin__scan-skip-requests|Scan Skip Requests]] (12)

### driver-management
- [[_moc-driver-management__drivers|Driver]] (296)

### gate-core
- [[_moc-gate-core__arrivals|Gate Arrival]] (117)
- [[_moc-gate-core__bst-outs__sap-transfers|Sap Transfers]] (50)
- [[_moc-gate-core__empty-vehicle-ins|Empty Vehicle Ins]] (36)
- [[_moc-gate-core__empty-vehicle-ins__reasons|Reasons]] (5)
- [[_moc-gate-core__empty-vehicle-outs|Empty Vehicle Outs]] (1)
- [[_moc-gate-core__empty-vehicle-outs__eligible-entries|Eligible Entries]] (43)
- [[_moc-gate-core__sales-dispatch|Sales Dispatch]] (38)
- [[_moc-gate-core__sales-dispatch__documents-001|Documents]] (1130)

### grpo
- [[_moc-grpo__all-entries|All Entries]] (5)
- [[_moc-grpo__service__pending|Pending]] (6)

### notifications
- [[_moc-notifications|Notifications]] (135)
- [[_moc-notifications__preferences|Preferences]] (39)

### person-gatein
- [[_moc-person-gatein__contractors|Contractors]] (2)
- [[_moc-person-gatein__entries|Entries]] (206)
- [[_moc-person-gatein__gates|Gate]] (1)
- [[_moc-person-gatein__labours|Labours]] (3)
- [[_moc-person-gatein__person-types|Person Type]] (2)
- [[_moc-person-gatein__visitors|Visitor]] (149)

### po
- [[_moc-po__vendors|Vendor]] (212)
- [[_moc-po__warehouses|Warehouse]] (31)

### production-execution
- [[_moc-production-execution__sap__items|Items]] (193)

### quality-control
- [[_moc-quality-control__arrival-slips|Arrival Slips]] (8)
- [[_moc-quality-control__inspections|Inspections]] (8)
- [[_moc-quality-control__sap-items|Sap Items]] (193)

### vehicle-management
- [[_moc-vehicle-management__transporters|Transporter]] (88)
- [[_moc-vehicle-management__vehicle-types|Vehicle Type]] (7)
- [[_moc-vehicle-management__vehicles|Vehicle]] (340)

## Empty for Jivo Mart (not configured on the retail arm)

These modules exist in the app but have no JIVO_MART data (live on Jivo Oil / Beverages):

- `/barcode/dispatch/sessions/closed/`
- `/dispatch/bilty-grpo/history/`
- `/dispatch/open-bilties/`
- `/dispatch/transporter-invoices/history/`
- `/gate-core/bst-ins/`
- `/gate-core/bst-ins/eligible-outs/`
- `/gate-core/bst-outs/`
- `/gate-core/bst-returns/`
- `/gate-core/bst-returns/eligible-outs/`
- `/gate-core/empty-vehicle-ins/eligible/`
- `/gate-core/job-work/`
- `/gate-core/job-work/sap-grpos/`
- `/gate-core/job-work/sap-production-orders/`
- `/gate-core/rejected-qc-returns/`
- `/gate-core/sales-dispatch/pending-bookings/`
- `/grpo/history/`
- `/grpo/pending/`
- `/grpo/service/history/`
- `/maintenance/asset-categories/`
- `/maintenance/asset-departments/`
- `/maintenance/asset-documents/`
- `/maintenance/asset-locations/`
- `/maintenance/asset-photos/`
- `/maintenance/assets/`
- `/maintenance/pm-checklist-items/`
- `/maintenance/pm-executions/`
- `/maintenance/pm-plans/`
- `/maintenance/spare-categories/`
- `/maintenance/spare-movements/`
- `/maintenance/spare-requests/`
- `/maintenance/spares/`
- `/maintenance/spares/low-stock/`
- `/maintenance/vendor-visits/`
- `/maintenance/work-order-photos/`
- `/maintenance/work-orders/`
- `/production-execution/breakdown-categories/`
- `/production-execution/checklist-templates/`
- `/production-execution/costs/analytics/`
- `/production-execution/line-clearance/`
- `/production-execution/line-configs/`
- `/production-execution/lines/`
- `/production-execution/machine-checklists/`
- `/production-execution/machines/`
- `/production-execution/reports/line-clearance/`
- `/production-execution/runs/`
- `/production-execution/sap/orders/`
- `/production-execution/waste/`
- `/quality-control/inspections/awaiting-chemist/`
- `/quality-control/inspections/awaiting-qam/`
- `/quality-control/inspections/completed/`
- `/quality-control/inspections/draft/`
- `/quality-control/inspections/rejected/`
- `/quality-control/inspections/return-to-vendor/`
- `/quality-control/material-types/`
- `/quality-control/print-documents/`
- `/quality-control/production-qc/`
- `/quality-control/production-qc/pending/`
- `/warehouse/bom-requests/`
- `/warehouse/fg-receipts/`

## SAP product bridge

421 distinct SAP item codes (FG####) are referenced by factory records and link to jivo-data-bank product nodes. See `_bridge.json`.

