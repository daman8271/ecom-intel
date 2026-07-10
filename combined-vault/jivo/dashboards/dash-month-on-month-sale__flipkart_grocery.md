---
type: app-dashboard
endpoint_key: month-on-month-sale__flipkart_grocery
source: app-dashboard
month: ""
platform: flipkart_grocery
tags:
  - type/app-dashboard
  - source/app-dashboard
  - platform/flipkart_grocery
---

# App dashboard — `month-on-month-sale__flipkart_grocery`

Up: [[dashboards-index]] · [[pf-flipkart_grocery]]

> **source: app-dashboard `month-on-month-sale__flipkart_grocery`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "comparison_months": [
  {
   "key": "current",
   "label": "JULY",
   "month": 7,
   "year": 2026
  },
  {
   "key": "previous_1",
   "label": "JUNE",
   "month": 6,
   "year": 2026
  },
  {
   "key": "previous_2",
   "label": "MAY",
   "month": 5,
   "year": 2026
  },
  {
   "key": "previous_3",
   "label": "APRIL",
   "month": 4,
   "year": 2026
  },
  {
   "key": "previous_4",
   "label": "MARCH",
   "month": 3,
   "year": 2026
  }
 ],
 "days_in_month": 31,
 "defaulted_to_latest": true,
 "elapsed_days": 7,
 "grand_total": {
  "current_done_ltr": 8235.0,
  "estimated_ltr": 36469.28571428572,
  "previous_1_ltr": 20596.0,
  "previous_2_ltr": 19876.0,
  "previous_3_ltr": 15186.0,
  "previous_4_ltr": 36442.0,
  "target": 54000.0
 },
 "groups": [
  {
   "rows": [
    {
     "current_done_ltr": 327.0,
     "estimated_ltr": 1448.142857142857,
     "item": "CANOLA 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 939.0,
     "previous_2_ltr": 1064.0,
     "previous_3_ltr": 599.0,
     "previous_4_ltr": 629.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    }
   ],
   "sub_category": "CANOLA",
   "total": {
    "current_done_ltr": 327.0,
    "estimated_ltr": 1448.142857142857,
    "previous_1_ltr": 939.0,
    "previous_2_ltr": 1064.0,
    "previous_3_ltr": 599.0,
    "previous_4_ltr": 629.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 8.0,
     "estimated_ltr": 35.42857142857142,
     "item": "EXTRA LIGHT 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 34.0,
     "previous_2_ltr": 32.0,
     "previous_3_ltr": 10.0,
     "previous_4_ltr": 40.0,
     "sub_category": "EXTRA LIGHT",
     "target": 200.0
    }
   ],
   "sub_category": "EXTRA LIGHT",
   "total": {
    "current_done_ltr": 8.0,
    "estimated_ltr": 35.42857142857142,
    "previous_1_ltr": 34.0,
    "previous_2_ltr": 32.0,
    "previous_3_ltr": 10.0,
    "previous_4_ltr": 40.0,
    "target": 200.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 5.0,
     "estimated_ltr": 22.142857142857142,
     "item": "GOLD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 5.0,
     "previous_2_ltr": 35.0,
     "previous_3_ltr": 0.0,
     "previous_4_ltr": 0.0,
     "sub_category": "GOLD",
     "target": 0.0
    }
   ],
   "sub_category": "GOLD",
   "total": {
    "current_done_ltr": 5.0,
    "estimated_ltr": 22.142857142857142,
    "previous_1_ltr": 5.0,
    "previous_2_ltr": 35.0,
    "previous_3_ltr": 0.0,
    "previous_4_ltr": 0.0,
    "target": 0.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 144.0,
     "estimated_ltr": 637.7142857142858,
     "item": "JIVO POMACE 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 303.0,
     "previous_2_ltr": 594.0,
     "previous_3_ltr": 264.0,
     "previous_4_ltr": 192.0,
     "sub_category": "JIVO POMACE",
     "target": 400.0
    },
    {
     "current_done_ltr": 25.0,
     "estimated_ltr": 110.71428571428572,
     "item": "JIVO POMACE 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 40.0,
     "previous_2_ltr": 85.0,
     "previous_3_ltr": 15.0,
     "previous_4_ltr": 190.0,
     "sub_category": "JIVO POMACE",
     "target": 400.0
    }
   ],
   "sub_category": "JIVO POMACE",
   "total": {
    "current_done_ltr": 169.0,
    "estimated_ltr": 748.4285714285716,
    "previous_1_ltr": 343.0,
    "previous_2_ltr": 679.0,
    "previous_3_ltr": 279.0,
    "previous_4_ltr": 382.0,
    "target": 800.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 7271.0,
     "estimated_ltr": 32200.14285714286,
     "item": "MUSTARD 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 17711.0,
     "previous_2_ltr": 15033.0,
     "previous_3_ltr": 11704.0,
     "previous_4_ltr": 31303.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 45000.0
    },
    {
     "current_done_ltr": 24.0,
     "estimated_ltr": 106.28571428571428,
     "item": "MUSTARD 4L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 248.0,
     "previous_2_ltr": 816.0,
     "previous_3_ltr": 760.0,
     "previous_4_ltr": 2516.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 4500.0
    },
    {
     "current_done_ltr": 335.0,
     "estimated_ltr": 1483.5714285714284,
     "item": "MUSTARD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 660.0,
     "previous_2_ltr": 855.0,
     "previous_3_ltr": 525.0,
     "previous_4_ltr": 730.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 1000.0
    }
   ],
   "sub_category": "MUSTARD KACHI GHANI",
   "total": {
    "current_done_ltr": 7630.0,
    "estimated_ltr": 33790.0,
    "previous_1_ltr": 18619.0,
    "previous_2_ltr": 16704.0,
    "previous_3_ltr": 12989.0,
    "previous_4_ltr": 34549.0,
    "target": 50500.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 4.0,
     "estimated_ltr": 17.71428571428571,
     "item": "SOYABEAN 1L POUCH",
     "item_head": "COMMODITY",
     "previous_1_ltr": 216.0,
     "previous_2_ltr": 1214.0,
     "previous_3_ltr": 1209.0,
     "previous_4_ltr": 810.0,
     "sub_category": "SOYABEAN",
     "target": 1000.0
    }
   ],
   "sub_category": "SOYABEAN",
   "total": {
    "current_done_ltr": 4.0,
    "estimated_ltr": 17.71428571428571,
    "previous_1_ltr": 216.0,
    "previous_2_ltr": 1214.0,
    "previous_3_ltr": 1209.0,
    "previous_4_ltr": 810.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 92.0,
     "estimated_ltr": 407.4285714285714,
     "item": "SUNFLOWER 4L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 440.0,
     "previous_2_ltr": 148.0,
     "previous_3_ltr": 100.0,
     "previous_4_ltr": 32.0,
     "sub_category": "SUNFLOWER",
     "target": 500.0
    }
   ],
   "sub_category": "SUNFLOWER",
   "total": {
    "current_done_ltr": 92.0,
    "estimated_ltr": 407.4285714285714,
    "previous_1_ltr": 440.0,
    "previous_2_ltr": 148.0,
    "previous_3_ltr": 100.0,
    "previous_4_ltr": 32.0,
    "target": 500.0
   }
  }
 ],
 "max_date": "2026-07-07",
 "month": 7,
 "source": "flipkart_grocery_master",
 "target_summary": [
  {
   "item_head": "PREMIUM",
   "target": 2000.0
  },
  {
   "item_head": "COMMODITY",
   "target": 52000.0
  },
  {
   "item_head": "TOTAL",
   "target": 54000.0
  }
 ],
 "year": 2026
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*


## Related
<!-- combined-backbone -->
[[Platform - flipkart]] · [[Platform - flipkart_grocery]]
