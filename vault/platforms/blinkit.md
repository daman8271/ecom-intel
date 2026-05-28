---
title: blinkit
aliases:
  - blinkit (platform hub)
type: platform-hub
platform: blinkit
risk: low
shape: per-pincode
tags:
  - moc
  - platform-hub
  - platform/blinkit
---

# blinkit — platform hub

Up: [[index]]

Hub / Map of Content for the **Blinkit** quick-commerce platform. This is the
**proven** scraper and the template every other platform was forked from.

## How it is scraped
- **Type:** quick-commerce (10–20 min delivery), so pricing is **per-pincode** —
  we loop the top-20 Indian cities (~40 pincodes) and record each store's prices.
- **Location mechanism:** localStorage location override (no GPS, no login).
- **Block risk:** low — the datacenter VPS IP is not blocked.
- **Typical yield:** ~8 unique Jivo SKUs, ~125 rows, ~27/40 pincodes carry Jivo,
  ~100s wall time.
- Result shape: per-pincode (`perPin` has 40 city/pincode entries, each with `rows`).

## What to watch
- Coverage swings (pincodes_with_jivo) — a sudden drop usually means a store-id /
  location regression, not a real delisting.
- Per-litre price is the cleaner cross-pack comparison than headline price.

## Runs

Newest first; auto-maintained by `tools/vault_note.py`.

<!-- runs:start -->
- [[blinkit-2026-05-28-0900]] — 2026-05-28 · verdict OK <!-- run -->
- [[blinkit-2026-05-27-1600]] — 2026-05-27 · verdict OK <!-- run -->
- [[blinkit-2026-05-27-1200]] — 2026-05-27 · verdict OK <!-- run -->
- [[blinkit-2026-05-27-0900]] — 2026-05-27 · verdict OK <!-- run -->
- [[blinkit-2026-05-26-1600]] — 2026-05-26 · verdict OK <!-- run -->
- [[blinkit-2026-05-26-1200]] — 2026-05-26 · verdict OK <!-- run -->
- [[blinkit-2026-05-26-0900]] — 2026-05-26 · verdict OK <!-- run -->
- [[blinkit-2026-05-25-1600]] — 2026-05-25 · verdict OK <!-- run -->
- [[blinkit-2026-05-25-1200]] — 2026-05-25 · verdict OK <!-- run -->
- [[blinkit-2026-05-25-0900]] — 2026-05-25 · verdict OK <!-- run -->
- [[blinkit-2026-05-24-1600]] — 2026-05-24 · verdict OK <!-- run -->
- [[blinkit-2026-05-24-1200]] — 2026-05-24 · verdict OK <!-- run -->
- [[blinkit-2026-05-24-0900]] — 2026-05-24 · verdict OK <!-- run -->
- [[blinkit-2026-05-23-1600]] — 2026-05-23 · verdict OK <!-- run -->
- [[blinkit-2026-05-23-1200]] — 2026-05-23 · verdict OK <!-- run -->
- [[blinkit-2026-05-23-0900]] — 2026-05-23 · verdict OK <!-- run -->
- [[blinkit-2026-05-22-1600]] — 2026-05-22 · verdict OK <!-- run -->
- [[blinkit-2026-05-22-1200]] — 2026-05-22 · verdict OK <!-- run -->
- [[blinkit-2026-05-22-0900]] — 2026-05-22 · verdict OK <!-- run -->
- [[blinkit-2026-05-21-1736]] — 2026-05-21 · verdict OK <!-- run -->
- [[blinkit-2026-05-21-1703]] — 2026-05-21 · verdict SUSPECT <!-- run -->
- [[blinkit-2026-05-21-1417]] — 2026-05-21 · verdict OK <!-- run -->
<!-- runs:end -->

---
*Hub auto-maintained by `tools/vault_note.py` — see [[VAULT-SPEC]].*
