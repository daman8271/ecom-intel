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
 "dashboard_title": "Big Basket Month On Month Analysis",
 "days_in_month": 31,
 "defaulted_to_latest": true,
 "elapsed_days": 4,
 "estimation_note": "Estimated LTR uses Excel formula: Done LTR / day(max date) * 30.",
 "format": "BIG BASKET",
 "grand_total": {
  "current_done_ltr": 3013.0,
  "estimated_ltr": 22597.5,
  "previous_1_ltr": 12156.0,
  "previous_2_ltr": 14792.0,
  "previous_3_ltr": 12466.0,
  "previous_4_ltr": 14434.0,
  "target": 17000.0
 },
 "groups": [
  {
   "rows": [
    {
     "current_done_ltr": 179.0,
     "estimated_ltr": 1342.5,
     "item": "CANOLA 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 871.0,
     "previous_2_ltr": 894.0,
     "previous_3_ltr": 911.0,
     "previous_4_ltr": 906.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    },
    {
     "current_done_ltr": 4.0,
     "estimated_ltr": 30.0,
     "item": "CANOLA 1L POUCH",
     "item_head": "PREMIUM",
     "previous_1_ltr": 61.0,
     "previous_2_ltr": 120.0,
     "previous_3_ltr": 174.0,
     "previous_4_ltr": 235.0,
     "sub_category": "CANOLA",
     "target": 500.0
    },
    {
     "current_done_ltr": 95.0,
     "estimated_ltr": 712.5,
     "item": "CANOLA 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 615.0,
     "previous_2_ltr": 810.0,
     "previous_3_ltr": 590.0,
     "previous_4_ltr": 950.0,
     "sub_category": "CANOLA",
     "target": 1000.0
    }
   ],
   "sub_category": "CANOLA",
   "total": {
    "current_done_ltr": 278.0,
    "estimated_ltr": 2085.0,
    "previous_1_ltr": 1547.0,
    "previous_2_ltr": 1824.0,
    "previous_3_ltr": 1675.0,
    "previous_4_ltr": 2091.0,
    "target": 2500.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 68.0,
     "estimated_ltr": 510.0,
     "item": "EXTRA LIGHT 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 297.0,
     "previous_2_ltr": 362.0,
     "previous_3_ltr": 366.0,
     "previous_4_ltr": 353.0,
     "sub_category": "EXTRA LIGHT",
     "target": 800.0
    },
    {
     "current_done_ltr": 36.0,
     "estimated_ltr": 270.0,
     "item": "EXTRA LIGHT 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 174.0,
     "previous_2_ltr": 228.0,
     "previous_3_ltr": 196.0,
     "previous_4_ltr": 220.0,
     "sub_category": "EXTRA LIGHT",
     "target": 500.0
    },
    {
     "current_done_ltr": 0.0,
     "estimated_ltr": 0.0,
     "item": "EXTRA LIGHT 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 10.0,
     "previous_2_ltr": 20.0,
     "previous_3_ltr": 30.0,
     "previous_4_ltr": 20.0,
     "sub_category": "EXTRA LIGHT",
     "target": 100.0
    }
   ],
   "sub_category": "EXTRA LIGHT",
   "total": {
    "current_done_ltr": 104.0,
    "estimated_ltr": 780.0,
    "previous_1_ltr": 481.0,
    "previous_2_ltr": 610.0,
    "previous_3_ltr": 592.0,
    "previous_4_ltr": 593.0,
    "target": 1400.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 2.0,
     "estimated_ltr": 15.0,
     "item": "EXTRA VIRGIN 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 19.0,
     "previous_2_ltr": 19.0,
     "previous_3_ltr": 22.0,
     "previous_4_ltr": 29.0,
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
     "previous_4_ltr": 0.0,
     "sub_category": "EXTRA VIRGIN",
     "target": 0.0
    }
   ],
   "sub_category": "EXTRA VIRGIN",
   "total": {
    "current_done_ltr": 2.0,
    "estimated_ltr": 15.0,
    "previous_1_ltr": 19.0,
    "previous_2_ltr": 19.0,
    "previous_3_ltr": 22.0,
    "previous_4_ltr": 29.0,
    "target": 100.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 101.0,
     "estimated_ltr": 757.5,
     "item": "JIVO POMACE 1L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 346.0,
     "previous_2_ltr": 440.0,
     "previous_3_ltr": 428.0,
     "previous_4_ltr": 430.0,
     "sub_category": "JIVO POMACE",
     "target": 800.0
    },
    {
     "current_done_ltr": 6.0,
     "estimated_ltr": 45.0,
     "item": "JIVO POMACE 2L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 44.0,
     "previous_2_ltr": 42.0,
     "previous_3_ltr": 40.0,
     "previous_4_ltr": 46.0,
     "sub_category": "JIVO POMACE",
     "target": 100.0
    },
    {
     "current_done_ltr": 0.0,
     "estimated_ltr": 0.0,
     "item": "JIVO POMACE 5L",
     "item_head": "PREMIUM",
     "previous_1_ltr": 50.0,
     "previous_2_ltr": 25.0,
     "previous_3_ltr": 25.0,
     "previous_4_ltr": 55.0,
     "sub_category": "JIVO POMACE",
     "target": 100.0
    }
   ],
   "sub_category": "JIVO POMACE",
   "total": {
    "current_done_ltr": 107.0,
    "estimated_ltr": 802.5,
    "previous_1_ltr": 440.0,
    "previous_2_ltr": 507.0,
    "previous_3_ltr": 493.0,
    "previous_4_ltr": 531.0,
    "target": 1000.0
   }
  },
  {
   "rows": [
    {
     "current_done_ltr": 324.0,
     "estimated_ltr": 2430.0,
     "item": "MUSTARD 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 870.0,
     "previous_2_ltr": 878.0,
     "previous_3_ltr": 452.0,
     "previous_4_ltr": 493.0,
     "sub_category": "MUSTARD KACCHI GHANI",
     "target": 1000.0
    },
    {
     "current_done_ltr": 245.0,
     "estimated_ltr": 1837.5,
     "item": "MUSTARD 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 1205.0,
     "previous_2_ltr": 1095.0,
     "previous_3_ltr": 860.0,
     "previous_4_ltr": 1055.0,
     "sub_category": "MUSTARD KACCHI GHANI",
     "target": 1500.0
    }
   ],
   "sub_category": "MUSTARD KACCHI GHANI",
   "total": {
    "current_done_ltr": 569.0,
    "estimated_ltr": 4267.5,
    "previous_1_ltr": 2075.0,
    "previous_2_ltr": 1973.0,
    "previous_3_ltr": 1312.0,
    "previous_4_ltr": 1548.0,
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
     "current_done_ltr": 1068.0,
     "estimated_ltr": 8010.0,
     "item": "SUNFLOWER 1L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 5424.0,
     "previous_2_ltr": 7734.0,
     "previous_3_ltr": 6142.0,
     "previous_4_ltr": 6382.0,
     "sub_category": "SUNFLOWER",
     "target": 6500.0
    },
    {
     "current_done_ltr": 885.0,
     "estimated_ltr": 6637.5,
     "item": "SUNFLOWER 5L",
     "item_head": "COMMODITY",
     "previous_1_ltr": 2170.0,
     "previous_2_ltr": 2125.0,
     "previous_3_ltr": 2230.0,
     "previous_4_ltr": 3260.0,
     "sub_category": "SUNFLOWER",
     "target": 3000.0
    }
   ],
   "sub_category": "SUNFLOWER",
   "total": {
    "current_done_ltr": 1953.0,
    "estimated_ltr": 14647.5,
    "previous_1_ltr": 7594.0,
    "previous_2_ltr": 9859.0,
    "previous_3_ltr": 8372.0,
    "previous_4_ltr": 9642.0,
    "target": 9500.0
   }
  }
 ],
 "max_date": "2026-07-04",
 "month": 7,
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
