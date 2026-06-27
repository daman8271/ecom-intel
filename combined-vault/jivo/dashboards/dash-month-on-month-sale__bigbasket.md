---
type: app-dashboard
endpoint_key: month-on-month-sale__bigbasket
source: app-dashboard
month: ""
platform: bigbasket
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/bigbasket
---

# App dashboard — `month-on-month-sale__bigbasket`

Up: [[dashboards-index]] · [[pf-bigbasket]]

> **source: app-dashboard `month-on-month-sale__bigbasket`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "comparison_months": [
  {
   "key": "current",
   "label": "JUNE",
   "month": 6,
   "year": 2026
  },
  {
   "key": "previous_1",
   "label": "MAY",
   "month": 5,
   "year": 2026
  },
  {
   "key": "previous_2",
   "label": "APRIL",
   "month": 4,
   "year": 2026
  },
  {
   "key": "previous_3",
   "label": "MARCH",
   "month": 3,
   "year": 2026
  },
  {
   "key": "previous_4",
   "label": "FEBRUARY",
   "month": 2,
   "year": 2026
  }
 ],
 "dashboard_title": "Big Basket Month On Month Analysis",
 "days_in_month": 30,
 "defaulted_to_latest": true,
 "elapsed_days": 25,
 "estimation_note": "Estimated LTR uses Excel formula: Done LTR / day(max date) * 30.",
 "format": "BIG BASKET",
 "grand_total": {
  "current_done_ltr": 9294.0,
  "estimated_ltr": 11152.8,
  "previous_1_ltr": 14792.0,
  "previous_2_ltr": 12466.0,
  "previous_3_ltr": 14434.0,
  "previous_4_ltr": 16921.0,
  "target": 17000.0
 },
 "groups": [
  {
   "rows": [
    {
     "current_done_ltr": 714.0,
     "estimated_ltr": 856.8,
     "item": "CANOLA 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 894.0,
     "previous_2_ltr": 911.0,
     "previous_3_ltr": 906.0,
     "previous_4_ltr": 1212.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    },
    {
     "current_done_ltr": 52.0,
     "estimated_ltr": 62.400000000000006,
     "item": "CANOLA 1L POUCH",
     "item_head": "PREMIUM",
     "previous_1_ltr": 120.0,
     "previous_2_ltr": 174.0,
     "previous_3_ltr": 235.0,
     "previous_4_ltr": 207.0,
     "sub_category": "CANOLA",
     "target": 500.0
    },
    {
     "current_done_ltr": 525.0,
     "estimated_ltr": 630.0,
     "item": "CANOLA 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 810.0,
     "previous_2_ltr": 590.0,
     "previous_3_ltr": 950.0,
     "previous_4_ltr": 1015.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    }
   ],
   "sub_category": "CANOLA",
   "total": {
    "current_done_ltr": 1291.0,
    "estimated_ltr": 1549.2,
    "previous_1_ltr": 1824.0,
    "previous_2_ltr": 1675.0,
    "previous_3_ltr": 2091.0,
    "previous_4_ltr": 2434.0,
    "target": 2500.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 242.0,
     "estimated_ltr": 290.4,
     "item": "EXTRA LIGHT 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 362.0,
     "previous_2_ltr": 366.0,
     "previous_3_ltr": 353.0,
     "previous_4_ltr": 452.0,
     "sub_category": "EXTRA LIGHT",
     "target": 800.0
    },
    {
     "current_done_ltr": 134.0,
     "estimated_ltr": 160.8,
     "item": "EXTRA LIGHT 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 228.0,
     "previous_2_ltr": 196.0,
     "previous_3_ltr": 220.0,
     "previous_4_ltr": 364.0,
     "sub_category": "EXTRA LIGHT",
     "target": 500.0
    },
    {
     "current_done_ltr": 10.0,
     "estimated_ltr": 12.0,
     "item": "EXTRA LIGHT 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 20.0,
     "previous_2_ltr": 30.0,
     "previous_3_ltr": 20.0,
     "previous_4_ltr": 10.0,
     "sub_category": "EXTRA LIGHT",
     "target": 100.0
    }
   ],
   "sub_category": "EXTRA LIGHT",
   "total": {
    "current_done_ltr": 386.0,
    "estimated_ltr": 463.2,
    "previous_1_ltr": 610.0,
    "previous_2_ltr": 592.0,
    "previous_3_ltr": 593.0,
    "previous_4_ltr": 826.0,
    "target": 1400.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 15.0,
     "estimated_ltr": 18.0,
     "item": "EXTRA VIRGIN 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 19.0,
     "previous_2_ltr": 22.0,
     "previous_3_ltr": 29.0,
     "previous_4_ltr": 32.0,
     "sub_category": "EXTRA VIRGIN",
     "target": 100.0
    },
    {
     "current_done_ltr": 0.0,
     "estimated_ltr": 0.0,
     "item": "EXTRA VIRGIN 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 0.0,
     "previous_2_ltr": 0.0,
     "previous_3_ltr": 0.0,
     "previous_4_ltr": 5.0,
     "sub_category": "EXTRA VIRGIN",
     "target": 0.0
    }
   ],
   "sub_category": "EXTRA VIRGIN",
   "total": {
    "current_done_ltr": 15.0,
    "estimated_ltr": 18.0,
    "previous_1_ltr": 19.0,
    "previous_2_ltr": 22.0,
    "previous_3_ltr": 29.0,
    "previous_4_ltr": 37.0,
    "target": 100.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 296.0,
     "estimated_ltr": 355.2,
     "item": "JIVO POMACE 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 440.0,
     "previous_2_ltr": 428.0,
     "previous_3_ltr": 430.0,
     "previous_4_ltr": 590.0,
     "sub_category": "JIVO POMACE",
     "target": 800.0
    },
    {
     "current_done_ltr": 34.0,
     "estimated_ltr": 40.800000000000004,
     "item": "JIVO POMACE 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 42.0,
     "previous_2_ltr": 40.0,
     "previous_3_ltr": 46.0,
     "previous_4_ltr": 34.0,
     "sub_category": "JIVO POMACE",
     "target": 100.0
    },
    {
     "current_done_ltr": 45.0,
     "estimated_ltr": 54.0,
     "item": "JIVO POMACE 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 25.0,
     "previous_2_ltr": 25.0,
     "previous_3_ltr": 55.0,
     "previous_4_ltr": 75.0,
     "sub_category": "JIVO POMACE",
     "target": 100.0
    }
   ],
   "sub_category": "JIVO POMACE",
   "total": {
    "current_done_ltr": 375.0,
    "estimated_ltr": 450.0,
    "previous_1_ltr": 507.0,
    "previous_2_ltr": 493.0,
    "previous_3_ltr": 531.0,
    "previous_4_ltr": 699.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 568.0,
     "estimated_ltr": 681.5999999999999,
     "item": "MUSTARD 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 878.0,
     "previous_2_ltr": 452.0,
     "previous_3_ltr": 493.0,
     "previous_4_ltr": 685.0,
     "sub_category": "MUSTARD KACCHI GHANI",
     "target": 1000.0
    },
    {
     "current_done_ltr": 930.0,
     "estimated_ltr": 1116.0,
     "item": "MUSTARD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 1095.0,
     "previous_2_ltr": 860.0,
     "previous_3_ltr": 1055.0,
     "previous_4_ltr": 1405.0,
     "sub_category": "MUSTARD KACCHI GHANI",
     "target": 1500.0
    }
   ],
   "sub_category": "MUSTARD KACCHI GHANI",
   "total": {
    "current_done_ltr": 1498.0,
    "estimated_ltr": 1797.6,
    "previous_1_ltr": 1973.0,
    "previous_2_ltr": 1312.0,
    "previous_3_ltr": 1548.0,
    "previous_4_ltr": 2090.0,
    "target": 2500.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 0.0,
     "estimated_ltr": 0.0,
     "item": "SOYABEAN 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 0.0,
     "previous_2_ltr": 0.0,
     "previous_3_ltr": 0.0,
     "previous_4_ltr": 0.0,
     "sub_category": "SOYABEAN",
     "target": 0.0
    },
    {
     "current_done_ltr": 0.0,
     "estimated_ltr": 0.0,
     "item": "SOYABEAN 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 0.0,
     "previous_2_ltr": 0.0,
     "previous_3_ltr": 0.0,
     "previous_4_ltr": 0.0,
     "sub_category": "SOYABEAN",
     "target": 0.0
    }
   ],
   "sub_category": "SOYABEAN",
   "total": {
    "current_done_ltr": 0.0,
    "estimated_ltr": 0.0,
    "previous_1_ltr": 0.0,
    "previous_2_ltr": 0.0,
    "previous_3_ltr": 0.0,
    "previous_4_ltr": 0.0,
    "target": 0.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 4084.0,
     "estimated_ltr": 4900.8,
     "item": "SUNFLOWER 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 7734.0,
     "previous_2_ltr": 6142.0,
     "previous_3_ltr": 6382.0,
     "previous_4_ltr": 7520.0,
     "sub_category": "SUNFLOWER",
     "target": 6500.0
    },
    {
     "current_done_ltr": 1645.0,
     "estimated_ltr": 1974.0,
     "item": "SUNFLOWER 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 2125.0,
     "previous_2_ltr": 2230.0,
     "previous_3_ltr": 3260.0,
     "previous_4_ltr": 3315.0,
     "sub_category": "SUNFLOWER",
     "target": 3000.0
    }
   ],
   "sub_category": "SUNFLOWER",
   "total": {
    "current_done_ltr": 5729.0,
    "estimated_ltr": 6874.8,
    "previous_1_ltr": 9859.0,
    "previous_2_ltr": 8372.0,
    "previous_3_ltr": 9642.0,
    "previous_4_ltr": 10835.0,
    "target": 9500.0
   }
  }
 ],
 "max_date": "2026-06-25",
 "month": 6,
 "projection_days": 30,
 "source": "SecMaster",
 "target_summary": [
  {
   "item_head": "PREMIUM",
   "target": 5000.0
  },
  {
   "item_head": "COMMODITY",
   "target": 12000.0
  },
  {
   "item_head": "TOTAL",
   "target": 17000.0
  }
 ],
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - bigbasket]]
