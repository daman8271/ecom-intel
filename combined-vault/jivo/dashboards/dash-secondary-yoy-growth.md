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
     "actual": 241510.9,
     "days_in_month": 30,
     "elapsed_day": 29,
     "growth_pct": 23.85,
     "has_data": true,
     "max_date": "2026-06-29",
     "projection": 249838.86,
     "source": "amazon_sec_range_master_view",
     "units": 141778.0,
     "value": 55274970.11958223
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
     "actual": 5422.3,
     "days_in_month": 30,
     "elapsed_day": 30,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-30",
     "projection": 5422.3,
     "source": "amazon_mp_master",
     "units": 1895.0,
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
     "actual": 84585.0,
     "days_in_month": 30,
     "elapsed_day": 30,
     "growth_pct": 30.8,
     "has_data": true,
     "max_date": "2026-06-30",
     "projection": 84585.0,
     "source": "SecMaster",
     "units": 66064.0,
     "value": 20244886.0
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
     "actual": 190394.5,
     "days_in_month": 30,
     "elapsed_day": 30,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-30",
     "projection": 190394.5,
     "source": "SecMaster",
     "units": 157325.0,
     "value": 35320804.0
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
     "actual": 81144.80014587939,
     "days_in_month": 30,
     "elapsed_day": 30,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-30",
     "projection": 81144.8,
     "source": "SecMaster",
     "units": 115428.0,
     "value": 18600466.0
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
     "actual": 12140.0,
     "days_in_month": 30,
     "elapsed_day": 30,
     "growth_pct": 30.61,
     "has_data": true,
     "max_date": "2026-06-30",
     "projection": 12140.0,
     "source": "SecMaster",
     "units": 9122.0,
     "value": 2144002.2
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
     "actual": 24047.4,
     "days_in_month": 30,
     "elapsed_day": 29,
     "growth_pct": -10.86,
     "has_data": true,
     "max_date": "2026-06-29",
     "projection": 24876.62,
     "source": "flipkart_secondary_all",
     "units": 6687.0,
     "value": 7179227.0
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
     "actual": 19684.0,
     "days_in_month": 30,
     "elapsed_day": 29,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-29",
     "projection": 20362.76,
     "source": "flipkart_grocery_master",
     "units": 18777.0,
     "value": 3123518.095238095
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
   "actual": 658928.9001458794,
   "growth_pct": 122.66,
   "has_data": true,
   "projection": 668764.84
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
