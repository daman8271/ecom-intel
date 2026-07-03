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
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
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
     "actual": 403.5,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 12508.5,
     "source": "amazon_mp_master",
     "units": 113.0,
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
     "value": 20026588.0
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
     "value": 39220284.0
    },
    "2026": {
     "actual": 3852.0,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": -93.69,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 119412.0,
     "source": "SecMaster",
     "units": 3063.0,
     "value": 2197510.0
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
     "actual": 10023.0,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 310713.0,
     "source": "SecMaster",
     "units": 7985.0,
     "value": 4172870.0
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
     "actual": 3934.6000052392483,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 121972.6,
     "source": "SecMaster",
     "units": 5092.0,
     "value": 2398770.0
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
     "value": 3164789.0
    },
    "2026": {
     "actual": 773.0,
     "days_in_month": 31,
     "elapsed_day": 1,
     "growth_pct": -92.97,
     "has_data": true,
     "max_date": "2026-07-01",
     "projection": 23963.0,
     "source": "SecMaster",
     "units": 555.0,
     "value": 166835.38
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
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
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
     "actual": null,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": false,
     "max_date": null,
     "projection": null,
     "units": null,
     "value": null
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
   "actual": 18986.10000523925,
   "growth_pct": -94.38,
   "has_data": true,
   "projection": 588569.1
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
