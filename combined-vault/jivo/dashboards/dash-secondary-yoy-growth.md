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
 "anchor_month": 6,
 "anchor_month_label": "June",
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
     "actual": 115716.5,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2024-06-30",
     "projection": null,
     "source": "amazon_sec_range_master_view",
     "units": 40414.0,
     "value": 28433382.56191089
    },
    "2025": {
     "actual": 194997.6,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": 68.51,
     "has_data": true,
     "max_date": "2025-06-30",
     "projection": null,
     "source": "amazon_sec_range_master_view",
     "units": 77862.0,
     "value": 43625083.39647204
    },
    "2026": {
     "actual": 223081.9,
     "days_in_month": 30,
     "elapsed_day": 27,
     "growth_pct": 14.4,
     "has_data": true,
     "max_date": "2026-06-27",
     "projection": 247868.78,
     "source": "amazon_sec_range_master_view",
     "units": 131586.0,
     "value": 51014261.79675856
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
     "actual": 5073.5,
     "days_in_month": 30,
     "elapsed_day": 28,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-28",
     "projection": 5435.89,
     "source": "amazon_mp_master",
     "units": 1767.0,
     "value": null
    }
   }
  },
  {
   "name": "Blinkit",
   "slug": "blinkit",
   "values": {
    "2024": {
     "actual": 22789.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2024-06-30",
     "projection": null,
     "source": "SecMaster",
     "units": 15810.0,
     "value": 17385894.0
    },
    "2025": {
     "actual": 64666.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": 183.76,
     "has_data": true,
     "max_date": "2025-06-30",
     "projection": null,
     "source": "SecMaster",
     "units": 48662.0,
     "value": 38947064.0
    },
    "2026": {
     "actual": 78698.0,
     "days_in_month": 30,
     "elapsed_day": 28,
     "growth_pct": 21.7,
     "has_data": true,
     "max_date": "2026-06-28",
     "projection": 84319.29,
     "source": "SecMaster",
     "units": 61414.0,
     "value": 18855840.0
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
     "actual": 174375.75,
     "days_in_month": 30,
     "elapsed_day": 28,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-28",
     "projection": 186831.16,
     "source": "SecMaster",
     "units": 144681.0,
     "value": 32441186.0
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
     "actual": 75323.00013545156,
     "days_in_month": 30,
     "elapsed_day": 28,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-28",
     "projection": 80703.21,
     "source": "SecMaster",
     "units": 107168.0,
     "value": 17263616.0
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
     "actual": 9295.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2025-06-30",
     "projection": null,
     "source": "SecMaster",
     "units": 8185.0,
     "value": 2816542.0
    },
    "2026": {
     "actual": 11151.0,
     "days_in_month": 30,
     "elapsed_day": 28,
     "growth_pct": 19.97,
     "has_data": true,
     "max_date": "2026-06-28",
     "projection": 11947.5,
     "source": "SecMaster",
     "units": 8442.0,
     "value": 1972716.6
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
     "actual": 26978.0,
     "days_in_month": null,
     "elapsed_day": null,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2025-06-30",
     "projection": null,
     "source": "flipkart_secondary_all",
     "units": 8554.0,
     "value": 6205145.0
    },
    "2026": {
     "actual": 21875.6,
     "days_in_month": 30,
     "elapsed_day": 27,
     "growth_pct": -18.91,
     "has_data": true,
     "max_date": "2026-06-27",
     "projection": 24306.22,
     "source": "flipkart_secondary_all",
     "units": 6110.0,
     "value": 6551669.0
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
     "actual": 17986.0,
     "days_in_month": 30,
     "elapsed_day": 27,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-27",
     "projection": 19984.44,
     "source": "flipkart_grocery_master",
     "units": 17128.0,
     "value": 2851936.1904761903
    }
   }
  }
 ],
 "source": "secondary",
 "totals": {
  "2024": {
   "actual": 138505.5,
   "growth_pct": null,
   "has_data": true,
   "projection": null
  },
  "2025": {
   "actual": 295936.6,
   "growth_pct": 113.66,
   "has_data": true,
   "projection": null
  },
  "2026": {
   "actual": 607564.7501354516,
   "growth_pct": 105.3,
   "has_data": true,
   "projection": 661396.4899999999
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
