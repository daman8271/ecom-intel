# ecom-intel — Jivo multi-platform price intelligence

Operator manual. Auto-loads when you run `claude` in this directory.

## What this is
Tracks Jivo SKU prices/stock across quick-commerce + marketplace platforms, across the top-20 Indian cities (~40 pincodes), and produces a clean Excel report per platform. Built for twice-daily cron runs. Pitched to Jivo's head of e-commerce.

## Architecture (the rule)
- **Scraping = deterministic Node + Playwright scripts. ZERO LLM in the scrape loop.** (LLM in the loop = 100–10000× the cost; never do it.)
- LLM is used only — later — for validation (cheap model) + narrative report (Sonnet).
- Each platform is self-contained under `platforms/<name>/`.
- `cron` triggers `./run.sh <platform>`.

## Layout
```
ecom-intel/
├── CLAUDE.md              # this file
├── run.sh                 # ./run.sh <platform>
├── platforms/
│   └── blinkit/           # PROVEN — works
│       ├── SKILL.md       # the scraping recipe + selectors + quirks
│       ├── scrape.js      # Playwright scraper -> result.json
│       ├── build_excel.py # result.json -> 6-sheet Excel
│       └── pincodes.json  # 40 pincodes, top-20 cities
├── output/                # generated Excel (gitignored)
└── logs/                  # per-run logs (gitignored)
```

## Run a platform
```bash
./run.sh blinkit            # scrape + build excel, ~100s
cat platforms/blinkit/result.json | python3 -m json.tool | head   # raw data
ls output/                  # the Excel
```

## Add a new platform (the workflow)
1. `cp -r platforms/blinkit platforms/<new>` and read `platforms/<new>/SKILL.md`
2. Adapt `scrape.js`: the site URL, the location-setting mechanism, the product-card selectors. Keep the same output JSON shape so `build_excel.py` works unchanged.
3. Test: `./run.sh <new>` — watch the log. **This is the "does it catch us" test** (datacenter VPS IP).
4. If it returns 0 rows / captcha / 403 → that platform blocks the datacenter IP → needs a residential proxy.
5. Commit + push.

## Block-risk map (datacenter VPS IP)
| Platform | Risk | Notes |
|---|---|---|
| blinkit | low (proven) | localStorage location override works |
| zepto | low–med | similar quick-comm |
| flipkart-minutes | med | newer quick-comm |
| amazon-now | med–high | Amazon infra |
| flipkart | high | marketplace bot detection |
| amazon | very high | ML bot detection, blocks datacenter IPs fast → proxy required |

## Cron (set per platform once tested)
```
0 9 * * *  cd /opt/ecom-intel && ./run.sh blinkit >> logs/cron.log 2>&1
0 19 * * * cd /opt/ecom-intel && ./run.sh blinkit >> logs/cron.log 2>&1
```

## Hard lessons
- This repo IS the backup. After any VPS wipe: `git clone` + `npm install` per platform + `npx playwright install chromium`. Never lose the code again.
- Never reinstall Hermes via Hostinger's catalog on this box — it triggers a full OS recreate (wipes the disk).
