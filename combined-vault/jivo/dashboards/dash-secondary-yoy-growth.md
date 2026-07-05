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
     "actual": 28619.1,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": -87.98,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 443596.05,
     "source": "amazon_sec_range_master_view",
     "units": 16360.0,
     "value": 5903171.155097826
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
     "actual": 855.3,
     "days_in_month": 31,
     "elapsed_day": 3,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-03",
     "projection": 8838.1,
     "source": "amazon_mp_master",
     "units": 257.0,
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
     "actual": 13123.0,
     "days_in_month": 31,
     "elapsed_day": 3,
     "growth_pct": -78.52,
     "has_data": true,
     "max_date": "2026-07-03",
     "projection": 135604.33,
     "source": "SecMaster",
     "units": 10650.0,
     "value": 6845867.0
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
     "actual": 31304.5,
     "days_in_month": 31,
     "elapsed_day": 3,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-03",
     "projection": 323479.83,
     "source": "SecMaster",
     "units": 24671.0,
     "value": 13029878.0
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
     "actual": 12059.400012493134,
     "days_in_month": 31,
     "elapsed_day": 3,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-07-03",
     "projection": 124613.8,
     "source": "SecMaster",
     "units": 14398.0,
     "value": 7449686.0
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
     "actual": 2382.0,
     "days_in_month": 31,
     "elapsed_day": 3,
     "growth_pct": -78.34,
     "has_data": true,
     "max_date": "2026-07-03",
     "projection": 24614.0,
     "source": "SecMaster",
     "units": 1679.0,
     "value": 506625.1
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
     "actual": 2602.9,
     "days_in_month": 31,
     "elapsed_day": 2,
     "growth_pct": -90.65,
     "has_data": true,
     "max_date": "2026-07-02",
     "projection": 40344.95,
     "source": "flipkart_secondary_all",
     "units": 721.0,
     "value": 790616.0
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
   "actual": 92246.20001249312,
   "growth_pct": -72.71,
   "has_data": true,
   "projection": 1141391.06
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
