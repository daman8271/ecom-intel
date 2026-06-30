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
 "elapsed_days": 28,
 "estimation_note": "Estimated LTR uses Excel formula: Done LTR / day(max date) * 30.",
 "format": "BIG BASKET",
 "grand_total": {
  "current_done_ltr": 11151.0,
  "estimated_ltr": 11947.5,
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
     "current_done_ltr": 809.0,
     "estimated_ltr": 866.7857142857142,
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
     "current_done_ltr": 56.0,
     "estimated_ltr": 60.0,
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
     "current_done_ltr": 565.0,
     "estimated_ltr": 605.3571428571428,
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
    "current_done_ltr": 1430.0,
    "estimated_ltr": 1532.1428571428569,
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
     "current_done_ltr": 275.0,
     "estimated_ltr": 294.6428571428571,
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
     "current_done_ltr": 154.0,
     "estimated_ltr": 165.0,
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
     "estimated_ltr": 10.714285714285715,
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
    "current_done_ltr": 439.0,
    "estimated_ltr": 470.35714285714283,
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
     "current_done_ltr": 17.0,
     "estimated_ltr": 18.21428571428571,
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
    "current_done_ltr": 17.0,
    "estimated_ltr": 18.21428571428571,
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
     "current_done_ltr": 326.0,
     "estimated_ltr": 349.2857142857143,
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
     "current_done_ltr": 40.0,
     "estimated_ltr": 42.85714285714286,
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
     "estimated_ltr": 48.214285714285715,
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
    "current_done_ltr": 411.0,
    "estimated_ltr": 440.35714285714283,
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
     "current_done_ltr": 755.0,
     "estimated_ltr": 808.9285714285714,
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
     "current_done_ltr": 1075.0,
     "estimated_ltr": 1151.7857142857144,
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
    "current_done_ltr": 1830.0,
    "estimated_ltr": 1960.7142857142858,
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
     "current_done_ltr": 5054.0,
     "estimated_ltr": 5415.0,
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
     "current_done_ltr": 1970.0,
     "estimated_ltr": 2110.714285714286,
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
    "current_done_ltr": 7024.0,
    "estimated_ltr": 7525.714285714286,
    "previous_1_ltr": 9859.0,
    "previous_2_ltr": 8372.0,
    "previous_3_ltr": 9642.0,
    "previous_4_ltr": 10835.0,
    "target": 9500.0
   }
  }
 ],
 "max_date": "2026-06-28",
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
