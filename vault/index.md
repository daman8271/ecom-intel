---
title: Jivo Price Intelligence — Index
aliases:
  - index
  - Home
  - Jivo Price Intelligence — Index
type: home-moc
tags:
  - moc
  - home
---

# Jivo Price Intelligence — Memory Vault

**Home MOC** (the entry point to the whole vault). This vault is the linked,
permanent memory of the ecom-intel price scraper: every cron run leaves a note
here, threaded into a knowledge graph, with a parallel machine-readable history
in `data/<platform>/history.csv` for a future price-intelligence ML model.

New here? Read **[[VAULT-SPEC]]** for how the vault is designed and which
Obsidian conventions we follow.

## Platform hubs (Maps of Content)

Each hub lists every run for that platform and describes how it is scraped.

- [[blinkit (platform hub)]] — quick-commerce · per-pincode (top-20 cities)
- [[flipkart-minutes (platform hub)]] — quick-commerce · per-pincode (HYPERLOCAL)
- [[flipkart (platform hub)]] — marketplace · national catalog
- [[amazon (platform hub)]] — marketplace · national catalog (richest catalog)

> Blocked / gated platforms (no runs yet): zepto (CloudFront 403, needs residential
> proxy), amazon-now (location/login-gated). They get hubs automatically once they
> produce a `result.json`.

## Time spine

- Latest daily: [[2026-05-21 (daily)]]
- This week: [[2026-W21 (weekly)]]
- This month: [[2026-05 (monthly)]]

Navigate trends: **run → [[2026-05-21 (daily)|daily]] → [[2026-W21 (weekly)|weekly]] → [[2026-05 (monthly)|monthly]]**.

## How it fits the pipeline

`run.sh` order: scrape → build_excel → review.py → self-heal → **vault_note.py** →
Telegram → git push. `vault_note.py` writes the run note + upserts the hub & daily;
`vault_rollup.py` (re)builds the daily/weekly/monthly trend notes.

---
*Maintained alongside `tools/vault_note.py` & `tools/vault_rollup.py`. See [[VAULT-SPEC]].*
