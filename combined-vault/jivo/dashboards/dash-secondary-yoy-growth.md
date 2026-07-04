---
type: app-dashboard
endpoint_key: secondary-yoy-growth
source: app-dashboard
month: ""
platform: ""
tags:
  - type/app-dashboard
  - source/app-dashboard
---

# App dashboard — `secondary-yoy-growth`

Up: [[dashboards-index]]

> **source: app-dashboard `secondary-yoy-growth`** — the app's OWN computed aggregate, captured verbatim (NOT a summary we invented; NOT raw rows).

```json
{
 "anchor_month": 7,
 "anchor_month_label": "July",
 "anchor_year": 2026,
 "defaulted_to_latest": true,
 "errors": [],
 "metric": "ltrs",
 "rows": [
  {
   "name": "Amazon",
   "slug": "amazon",
   "values": {
    "2024": {
     "actual": 142216.85,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2024-07-31",
     "projection": null,
     "source": "amazon_sec_range_master_view",
     "units": 49965.0,
     "value": 34740528.23899925
    },
    "2025": {
     "actual": 238090.45,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": 67.41,
     "has_data": true,
     "max_date": "2025-07-31",
     "projection": null,
     "source": "amazon_sec_range_master_view",
     "units": 89270.0,
     "value": 54160941.06669587
    },
    "2026": {
     "actual": 11139.1,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": -95.32,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 345312.1,
     "source": "amazon_sec_range_master_view",
     "units": 6671.0,
     "value": 2421359.5537327155
    }
   }
  },
  {
   "name": "Amazon MP",
   "slug": "amazon_mp",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2026": {
     "actual": 715.4,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 11088.7,
     "source": "amazon_mp_master",
     "units": 206.0,
     "value": null
    }
   }
  },
  {
   "name": "Blinkit",
   "slug": "blinkit",
   "values": {
    "2024": {
     "actual": 25917.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2024-07-31",
     "projection": null,
     "source": "SecMaster",
     "units": 17880.0,
     "value": 20026544.0
    },
    "2025": {
     "actual": 61081.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": 135.68,
     "has_data": true,
     "max_date": "2025-07-31",
     "projection": null,
     "source": "SecMaster",
     "units": 45004.0,
     "value": 39220036.0
    },
    "2026": {
     "actual": 7568.0,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": -87.61,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 117304.0,
     "source": "SecMaster",
     "units": 5932.0,
     "value": 4331111.0
    }
   }
  },
  {
   "name": "Swiggy",
   "slug": "swiggy",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2026": {
     "actual": 20780.5,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 322097.75,
     "source": "SecMaster",
     "units": 16522.0,
     "value": 8634952.0
    }
   }
  },
  {
   "name": "Zepto",
   "slug": "zepto",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2026": {
     "actual": 7972.400008767843,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 123572.2,
     "source": "SecMaster",
     "units": 9754.0,
     "value": 4901899.0
    }
   }
  },
  {
   "name": "BigBasket",
   "slug": "bigbasket",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": 10997.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2025-07-31",
     "projection": null,
     "source": "SecMaster",
     "units": 8763.0,
     "value": 3164788.2
    },
    "2026": {
     "actual": 1609.0,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": -85.37,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 24939.5,
     "source": "SecMaster",
     "units": 1150.0,
     "value": 340911.12
    }
   }
  },
  {
   "name": "Flipkart",
   "slug": "flipkart",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": 27841.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2025-07-31",
     "projection": null,
     "source": "flipkart_secondary_all",
     "units": 8959.0,
     "value": 7364896.0
    },
    "2026": {
     "actual": 1282.0,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": -95.4,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 39742.0,
     "source": "flipkart_secondary_all",
     "units": 350.0,
     "value": 390269.0
    }
   }
  },
  {
   "name": "Flipkart Grocery",
   "slug": "flipkart_grocery",
   "values": {
    "2024": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2025": {
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
    },
    "2026": {
     "actual": 1300.0,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 40300.0,
     "source": "flipkart_grocery_master",
     "units": 1247.0,
     "value": 206631.42857142858
    }
   }
  }
 ],
 "source": "secondary",
 "totals": {
  "2024": {
   "actual": 168133.85,
   "growth_pct": null,
   "has_data": true,
   "projection": null
  },
  "2025": {
   "actual": 338009.45,
   "growth_pct": 101.04,
   "has_data": true,
   "projection": null
  },
  "2026": {
   "actual": 52366.40000876784,
   "growth_pct": -84.51,
   "has_data": true,
   "projection": 1024356.25
  }
 },
 "years": [
  2024,
  2025,
  2026
 ]
}
```

---
*Auto-generated by `bin/vault_build.py` from `store/versioned/*` — deterministic rebuild.*
