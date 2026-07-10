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
     "actual": 144561.9,
     "days_in_month": 31,
     "elapsed_day": 7,
     "growth_pct": -39.28,
     "has_data": true,
     "max_date": "2026-07-07",
     "projection": 640202.7,
     "source": "amazon_sec_range_master_view",
     "units": 72803.0,
     "value": 29146210.66509353
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
     "actual": 1485.0,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 5754.38,
     "source": "amazon_mp_master",
     "units": 528.0,
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
     "actual": 30978.0,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": -49.28,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 120039.75,
     "source": "SecMaster",
     "units": 24577.0,
     "value": 17210992.0
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
     "actual": 82497.0,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 319675.88,
     "source": "SecMaster",
     "units": 65832.0,
     "value": 34303812.0
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
     "actual": 31309.400031536818,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 121323.93,
     "source": "SecMaster",
     "units": 36951.0,
     "value": 19560666.0
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
     "actual": 5158.0,
     "days_in_month": 31,
     "elapsed_day": 8,
     "growth_pct": -53.1,
     "has_data": true,
     "max_date": "2026-07-08",
     "projection": 19987.25,
     "source": "SecMaster",
     "units": 3628.0,
     "value": 1135937.5
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
     "actual": 20446.8,
     "days_in_month": 31,
     "elapsed_day": 7,
     "growth_pct": -26.56,
     "has_data": true,
     "max_date": "2026-07-07",
     "projection": 90550.11,
     "source": "flipkart_secondary_all",
     "units": 5192.0,
     "value": 5505178.0
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
     "actual": 8250.0,
     "days_in_month": 31,
     "elapsed_day": 7,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-07",
     "projection": 36535.71,
     "source": "flipkart_grocery_master",
     "units": 7870.0,
     "value": 1311460.9523809524
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
   "actual": 324686.10003153683,
   "growth_pct": -3.94,
   "has_data": true,
   "projection": 1354069.71
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
