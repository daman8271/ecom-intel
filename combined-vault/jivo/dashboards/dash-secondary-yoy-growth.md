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
     "actual": 181923.7,
     "days_in_month": 31,
     "elapsed_day": 9,
     "growth_pct": -23.59,
     "has_data": true,
     "max_date": "2026-07-09",
     "projection": 626626.08,
     "source": "amazon_sec_range_master_view",
     "units": 90596.0,
     "value": 36714033.851129964
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
     "actual": 1682.4,
     "days_in_month": 31,
     "elapsed_day": 10,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-10",
     "projection": 5215.44,
     "source": "amazon_mp_master",
     "units": 630.0,
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
     "actual": 36835.0,
     "days_in_month": 31,
     "elapsed_day": 10,
     "growth_pct": -39.69,
     "has_data": true,
     "max_date": "2026-07-10",
     "projection": 114188.5,
     "source": "SecMaster",
     "units": 29200.0,
     "value": 8588555.0
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
     "actual": 102868.5,
     "days_in_month": 31,
     "elapsed_day": 10,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-10",
     "projection": 318892.35,
     "source": "SecMaster",
     "units": 82517.0,
     "value": 18551612.0
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
     "actual": 38480.20003890991,
     "days_in_month": 31,
     "elapsed_day": 10,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-10",
     "projection": 119288.62,
     "source": "SecMaster",
     "units": 45493.0,
     "value": 8878531.0
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
     "value": 3164788.5
    },
    "2026": {
     "actual": 6767.0,
     "days_in_month": 31,
     "elapsed_day": 10,
     "growth_pct": -38.47,
     "has_data": true,
     "max_date": "2026-07-10",
     "projection": 20977.7,
     "source": "SecMaster",
     "units": 4983.0,
     "value": 1218404.9
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
     "actual": 23065.4,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": -17.15,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 89378.43,
     "source": "flipkart_secondary_all",
     "units": 5820.0,
     "value": 6150273.0
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
     "actual": 10972.0,
     "days_in_month": 31,
     "elapsed_day": 9,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-09",
     "projection": 37792.44,
     "source": "flipkart_grocery_master",
     "units": 10409.0,
     "value": 1742108.5714285714
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
   "actual": 402594.2000389099,
   "growth_pct": 19.11,
   "has_data": true,
   "projection": 1332359.5599999996
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
