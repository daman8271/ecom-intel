---
type: analysis-moc
title: Analysis — your workspace
tags:
  - moc
  - analysis
created: 2026-05-30
---

# Analysis — your hand-written workspace

Up: [[index]]

This folder (`vault/analysis/`) is **yours**. The vault generator
(`tools/vault_build.py`) never writes here, so anything you put in this folder
**survives every cron rebuild** and syncs both ways through git. Everything *outside*
this folder (`skus/`, `runs/`, `locations/`, `platforms/`, `daily|weekly|monthly/`,
`index.md`) is machine-generated and will be **overwritten** — read it, don't edit it.

> **Naming rule:** every note in the vault must have a globally-unique filename
> (Obsidian resolves `[[links]]` by basename). Prefix your notes, e.g.
> `analysis-canola-pricing-thesis.md`, so they never collide with a generated SKU slug.

## Start here
- [[price-intel-dashboard]] — live Dataview tables: cheapest now, at-cheapest-ever,
  biggest swings, possible stockouts, per-platform boards. (Needs the Dataview plugin.)

## The three layers of the "price intelligence model"
1. **Data** — `data/<platform>/history.csv`: one row per `run × SKU × location`,
   append-only. The ground truth.
2. **Model** — `tools/predict.py`: deterministic, no-LLM forecasting appended to each
   Excel workbook as a *Predictions* sheet — stock-out risk, price/discount moves,
   coverage trend. Runs every sweep via `run_all.sh`.
3. **View (here)** — this Obsidian vault: the same data as a linked graph, with the
   Dataview dashboards above, plus the notes you write below.

## Your notes
_Create them in this folder. Some starter ideas:_
- `analysis-<sku>-thesis.md` — your read on a specific SKU's pricing behaviour, linking
  the generated hub, e.g. `[[jivo-canola-cold-press-edible-oil-1l]]`.
- `analysis-platform-strategy.md` — how Jivo's pricing differs across
  [[blinkit]] / [[]] / [[amazon]] / [[flipkart]] / [[flipkart-minutes]].
- `analysis-weekly-readout.md` — your weekly takeaways, linking that week's rollup.

Because you link *into* the generated graph (`[[sku-slug]]`, `[[platform]]`, `[[date]]`),
your analysis shows up connected in Obsidian's graph view without ever editing a
generated file.
