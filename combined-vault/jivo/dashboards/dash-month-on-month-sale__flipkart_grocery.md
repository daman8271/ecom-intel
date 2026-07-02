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
 "days_in_month": 30,
 "defaulted_to_latest": true,
 "elapsed_days": 29,
 "grand_total": {
  "current_done_ltr": 19680.0,
  "estimated_ltr": 20358.620689655167,
  "previous_1_ltr": 22699.0,
  "previous_2_ltr": 15186.0,
  "previous_3_ltr": 36442.0,
  "previous_4_ltr": 36519.0,
  "target": 54000.0
 },
 "groups": [
  {
   "rows": [
    {
     "current_done_ltr": 907.0,
     "estimated_ltr": 938.2758620689655,
     "item": "CANOLA 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 1224.0,
     "previous_2_ltr": 599.0,
     "previous_3_ltr": 629.0,
     "previous_4_ltr": 776.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    }
   ],
   "sub_category": "CANOLA",
   "total": {
    "current_done_ltr": 907.0,
    "estimated_ltr": 938.2758620689655,
    "previous_1_ltr": 1224.0,
    "previous_2_ltr": 599.0,
    "previous_3_ltr": 629.0,
    "previous_4_ltr": 776.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 32.0,
     "estimated_ltr": 33.10344827586207,
     "item": "EXTRA LIGHT 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 38.0,
     "previous_2_ltr": 10.0,
     "previous_3_ltr": 40.0,
     "previous_4_ltr": 228.0,
     "sub_category": "EXTRA LIGHT",
     "target": 200.0
    }
   ],
   "sub_category": "EXTRA LIGHT",
   "total": {
    "current_done_ltr": 32.0,
    "estimated_ltr": 33.10344827586207,
    "previous_1_ltr": 38.0,
    "previous_2_ltr": 10.0,
    "previous_3_ltr": 40.0,
    "previous_4_ltr": 228.0,
    "target": 200.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 5.0,
     "estimated_ltr": 5.172413793103448,
     "item": "GOLD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 45.0,
     "previous_2_ltr": 0.0,
     "previous_3_ltr": 0.0,
     "previous_4_ltr": 55.0,
     "sub_category": "GOLD",
     "target": 0.0
    }
   ],
   "sub_category": "GOLD",
   "total": {
    "current_done_ltr": 5.0,
    "estimated_ltr": 5.172413793103448,
    "previous_1_ltr": 45.0,
    "previous_2_ltr": 0.0,
    "previous_3_ltr": 0.0,
    "previous_4_ltr": 55.0,
    "target": 0.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 296.0,
     "estimated_ltr": 306.2068965517242,
     "item": "JIVO POMACE 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 680.0,
     "previous_2_ltr": 264.0,
     "previous_3_ltr": 192.0,
     "previous_4_ltr": 168.0,
     "sub_category": "JIVO POMACE",
     "target": 400.0
    },
    {
     "current_done_ltr": 40.0,
     "estimated_ltr": 41.37931034482759,
     "item": "JIVO POMACE 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 90.0,
     "previous_2_ltr": 15.0,
     "previous_3_ltr": 190.0,
     "previous_4_ltr": 30.0,
     "sub_category": "JIVO POMACE",
     "target": 400.0
    }
   ],
   "sub_category": "JIVO POMACE",
   "total": {
    "current_done_ltr": 336.0,
    "estimated_ltr": 347.58620689655174,
    "previous_1_ltr": 770.0,
    "previous_2_ltr": 279.0,
    "previous_3_ltr": 382.0,
    "previous_4_ltr": 198.0,
    "target": 800.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 16900.0,
     "estimated_ltr": 17482.758620689652,
     "item": "MUSTARD 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 17080.0,
     "previous_2_ltr": 11704.0,
     "previous_3_ltr": 31303.0,
     "previous_4_ltr": 29071.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 45000.0
    },
    {
     "current_done_ltr": 244.0,
     "estimated_ltr": 252.41379310344828,
     "item": "MUSTARD 4L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 976.0,
     "previous_2_ltr": 760.0,
     "previous_3_ltr": 2516.0,
     "previous_4_ltr": 5352.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 4500.0
    },
    {
     "current_done_ltr": 605.0,
     "estimated_ltr": 625.8620689655172,
     "item": "MUSTARD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 975.0,
     "previous_2_ltr": 525.0,
     "previous_3_ltr": 730.0,
     "previous_4_ltr": 140.0,
     "sub_category": "MUSTARD KACHI GHANI",
     "target": 1000.0
    }
   ],
   "sub_category": "MUSTARD KACHI GHANI",
   "total": {
    "current_done_ltr": 17749.0,
    "estimated_ltr": 18361.034482758616,
    "previous_1_ltr": 19031.0,
    "previous_2_ltr": 12989.0,
    "previous_3_ltr": 34549.0,
    "previous_4_ltr": 34563.0,
    "target": 50500.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 215.0,
     "estimated_ltr": 222.41379310344828,
     "item": "SOYABEAN 1L POUCH",
     "item_head": "COMMODITY",
     "previous_1_ltr": 1423.0,
     "previous_2_ltr": 1209.0,
     "previous_3_ltr": 810.0,
     "previous_4_ltr": 555.0,
     "sub_category": "SOYABEAN",
     "target": 1000.0
    }
   ],
   "sub_category": "SOYABEAN",
   "total": {
    "current_done_ltr": 215.0,
    "estimated_ltr": 222.41379310344828,
    "previous_1_ltr": 1423.0,
    "previous_2_ltr": 1209.0,
    "previous_3_ltr": 810.0,
    "previous_4_ltr": 555.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 436.0,
     "estimated_ltr": 451.0344827586207,
     "item": "SUNFLOWER 4L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 168.0,
     "previous_2_ltr": 100.0,
     "previous_3_ltr": 32.0,
     "previous_4_ltr": 144.0,
     "sub_category": "SUNFLOWER",
     "target": 500.0
    }
   ],
   "sub_category": "SUNFLOWER",
   "total": {
    "current_done_ltr": 436.0,
    "estimated_ltr": 451.0344827586207,
    "previous_1_ltr": 168.0,
    "previous_2_ltr": 100.0,
    "previous_3_ltr": 32.0,
    "previous_4_ltr": 144.0,
    "target": 500.0
   }
  }
 ],
 "max_date": "2026-06-29",
 "month": 6,
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
