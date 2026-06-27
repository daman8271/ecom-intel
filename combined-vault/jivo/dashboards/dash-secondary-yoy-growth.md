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
     "actual": 195294.2,
     "days_in_month": 30,
     "elapsed_day": 24,
     "growth_pct": 0.15,
     "has_data": true,
     "max_date": "2026-06-24",
     "projection": 244117.75,
     "source": "amazon_sec_range_master_view",
     "units": 114720.0,
     "value": 44937655.844602235
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
     "actual": 4820.05,
     "days_in_month": 30,
     "elapsed_day": 25,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-25",
     "projection": 5784.06,
     "source": "amazon_mp_master",
     "units": 1653.0,
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
     "actual": 69794.0,
     "days_in_month": 30,
     "elapsed_day": 25,
     "growth_pct": 7.93,
     "has_data": true,
     "max_date": "2026-06-25",
     "projection": 83752.8,
     "source": "SecMaster",
     "units": 54334.0,
     "value": 16746484.0
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
     "actual": 146668.5,
     "days_in_month": 30,
     "elapsed_day": 25,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-25",
     "projection": 176002.2,
     "source": "SecMaster",
     "units": 122457.0,
     "value": 27531312.0
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
     "actual": 64852.40011473,
     "days_in_month": 30,
     "elapsed_day": 25,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-25",
     "projection": 77822.88,
     "source": "SecMaster",
     "units": 91653.0,
     "value": 14836172.0
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
     "value": 2816542.2
    },
    "2026": {
     "actual": 9294.0,
     "days_in_month": 30,
     "elapsed_day": 25,
     "growth_pct": -0.01,
     "has_data": true,
     "max_date": "2026-06-25",
     "projection": 11152.8,
     "source": "SecMaster",
     "units": 6977.0,
     "value": 1654469.1
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
     "actual": 19286.0,
     "days_in_month": 30,
     "elapsed_day": 24,
     "growth_pct": -28.51,
     "has_data": true,
     "max_date": "2026-06-24",
     "projection": 24107.5,
     "source": "flipkart_secondary_all",
     "units": 5398.0,
     "value": 5802470.0
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
     "actual": 16129.0,
     "days_in_month": 30,
     "elapsed_day": 24,
     "growth_pct": null,
     "has_data": true,
     "max_date": "2026-06-24",
     "projection": 20161.25,
     "source": "flipkart_grocery_master",
     "units": 15322.0,
     "value": 2551462.8571428573
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
   "actual": 526138.15011473,
   "growth_pct": 77.79,
   "has_data": true,
   "projection": 642901.24
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
