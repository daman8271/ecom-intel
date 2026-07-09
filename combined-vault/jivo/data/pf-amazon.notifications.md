---
type: data
entity: pf-amazon
table: notifications
rows: 6
chunk: 1/1
source: app-notifications
tags:
  - type/data
  - table/notifications
  - source/app-notifications
---

# Raw `notifications` rows for [[pf-amazon]]

Up: [[pf-amazon]]
Canonical raw rows (6) for `notifications`, embedded once here (verbatim, full column set). Other dimensions are links on the parent.

```csv
active,brand,category,created_at,doh,drr_ltr,drr_units,first_seen_at,format,id,inventory_date,is_read,item,item_head,last_seen_at,link,ltr_sold,message,month_start,payload,platform_slug,read,resolved_at,sales_max_date,severity,sku_code,sku_name,soh_ltr,soh_units,sub_category,threshold,title,type,units_sold
true,JIVO,GIFT PACK,2026-07-08T06:21:31.073744+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.073498+00:00,AMAZON,2089,2026-07-06,false,GIFT BOX,OTHER,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2089,0.0,"AMAZON GIFT BOX has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""GIFT PACK"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""GIFT BOX"",""item_head"":""OTHER"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0FQCG3Z6X"",""sku_name"":""GIFT BOX"",""soh_ltr"":0.0,""soh_units"":0.0,""sub_category"":""DRY FRUITS"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0FQCG3Z6X,GIFT BOX,0.0,0.0,DRY FRUITS,5.0,AMAZON GIFT BOX DOH 0.00,INVENTORY_DOH_LOW,0.0
true,JIVO,TEA,2026-07-08T06:21:31.088117+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.087866+00:00,AMAZON,2092,2026-07-06,false,JIVO TEA 250 GMS,OTHER,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2092,0.0,"AMAZON JIVO TEA 250 GMS has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""TEA"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""JIVO TEA 250 GMS"",""item_head"":""OTHER"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0GQLH813C"",""sku_name"":""JIVO TEA 250 GMS"",""soh_ltr"":0.0,""soh_units"":0.0,""sub_category"":""TEA"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0GQLH813C,JIVO TEA 250 GMS,0.0,0.0,TEA,5.0,AMAZON JIVO TEA 250 GMS DOH 0.00,INVENTORY_DOH_LOW,0.0
true,JIVO,DRINKS,2026-07-08T06:21:31.097562+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.097271+00:00,AMAZON,2094,2026-07-06,false,JIVO WATER 500 MLS,OTHER,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2094,0.0,"AMAZON JIVO WATER 500 MLS has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""DRINKS"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""JIVO WATER 500 MLS"",""item_head"":""OTHER"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0GZB4ZQV3"",""sku_name"":""JIVO WATER 500 MLS"",""soh_ltr"":0.0,""soh_units"":0.0,""sub_category"":""MINERAL WATER"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0GZB4ZQV3,JIVO WATER 500 MLS,0.0,0.0,MINERAL WATER,5.0,AMAZON JIVO WATER 500 MLS DOH 0.00,INVENTORY_DOH_LOW,0.0
true,JIVO,GIFT PACK,2026-07-08T06:21:31.069213+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.068970+00:00,AMAZON,2088,2026-07-06,false,GIFT BOX,OTHER,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2088,0.0,"AMAZON GIFT BOX has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""GIFT PACK"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""GIFT BOX"",""item_head"":""OTHER"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0FQC831P8"",""sku_name"":""GIFT BOX"",""soh_ltr"":0.0,""soh_units"":18.0,""sub_category"":""DRY FRUITS"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0FQC831P8,GIFT BOX,0.0,18.0,DRY FRUITS,5.0,AMAZON GIFT BOX DOH 0.00,INVENTORY_DOH_LOW,0.0
true,JIVO,FIRST PRESSED,2026-07-08T06:21:31.101872+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.101623+00:00,AMAZON,2095,2026-07-06,false,FIRST PRESSED SUNFLOWER 1 LTR,PREMIUM,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2095,0.0,"AMAZON FIRST PRESSED SUNFLOWER 1 LTR has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""FIRST PRESSED"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""FIRST PRESSED SUNFLOWER 1 LTR"",""item_head"":""PREMIUM"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0H5KGC6P7"",""sku_name"":""FIRST PRESSED SUNFLOWER 1 LTR"",""soh_ltr"":0.0,""soh_units"":0.0,""sub_category"":""FIRST PRESSED SUNFLOWER"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0H5KGC6P7,FIRST PRESSED SUNFLOWER 1 LTR,0.0,0.0,FIRST PRESSED SUNFLOWER,5.0,AMAZON FIRST PRESSED SUNFLOWER 1 LTR DOH 0.00,INVENTORY_DOH_LOW,0.0
true,JIVO,DRINKS,2026-07-08T06:21:31.092639+00:00,0.0,0.0,0.0,2026-07-08T06:21:31.092384+00:00,AMAZON,2093,2026-07-06,false,JIVO PUNJABI SHIKANJI 160 MLS,OTHER,2026-07-08T13:57:53.721769+00:00,/notifications/inventory-doh/2093,0.0,"AMAZON JIVO PUNJABI SHIKANJI 160 MLS has DOH 0.00, below threshold 5.",2026-07-01,"{""alert_type"":""INVENTORY_DOH_LOW"",""brand"":""JIVO"",""category"":""DRINKS"",""doh"":0.0,""drr_ltr"":0.0,""drr_units"":0.0,""format"":""AMAZON"",""inventory_date"":""2026-07-06"",""item"":""JIVO PUNJABI SHIKANJI 160 MLS"",""item_head"":""OTHER"",""ltr_sold"":0.0,""month_start"":""2026-07-01"",""platform_slug"":""amazon"",""sales_max_date"":""2026-07-06"",""sku_code"":""B0GZ7PXVF8"",""sku_name"":""JIVO PUNJABI SHIKANJI 160 MLS"",""soh_ltr"":0.0,""soh_units"":0.0,""sub_category"":""SHIKANJI"",""threshold"":5.0,""units_sold"":0.0}",amazon,false,,2026-07-06,critical,B0GZ7PXVF8,JIVO PUNJABI SHIKANJI 160 MLS,0.0,0.0,SHIKANJI,5.0,AMAZON JIVO PUNJABI SHIKANJI 160 MLS DOH 0.00,INVENTORY_DOH_LOW,0.0
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - amazon]]
