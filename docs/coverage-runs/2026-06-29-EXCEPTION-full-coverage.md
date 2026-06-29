# 2026-06-29 — EXCEPTION: one-time full per-pincode coverage run (QC platforms)

> **This was an EXCEPTION, not the daily norm.** On 2026-06-29, *in addition to* the
> normal deadline-aligned cron (which ran its usual anchor-based scrape for the noon
> batch), we performed a **one-time manual FULL per-pincode coverage run** for the three
> genuinely pincode-wise quick-commerce platforms. The daily cron continues unchanged on
> the anchor model; this deep pass was run manually via `COVERAGE_FULL=1`.

## What was done
Each of **Blinkit, Zepto, Flipkart-minutes** was pointed at **every one of the 1,885
distinct pincodes** in the 25 target cities (vs the usual ~135–467 anchors), and each
pincode was classified honestly into the coverage ledger
(`data/coverage/ledger.csv`): `price_captured | serviceable_no_jivo | not_serviceable | error`.

These runs were committed as their own run-ids (separate from the cron's anchor runs of
the same date):

| Platform | Run ID | Delivers to (serviceable) | Jivo on sale | SKUs | Price rows |
|---|---|--:|--:|--:|--:|
| **Zepto** | `2026-06-29-1319` | 693 | 693 | 23 | 14,835 |
| **Blinkit** | `2026-06-29-1203` | 902 | 486 | 9 | 1,898 |
| **Flipkart Minutes** | `2026-06-29-1605` | 340 | 340 | 16 | 568 |


## Result (physically scraped, not extrapolated)
- **Reachable by ≥1 platform: 935 / 1,885 (50%)** — up from the anchor-system's 234 (12%) the same morning.
- **Jivo on sale: 806 / 1,885 (43%)**.
- **Headline finding:** Blinkit delivers to **902** pincodes but stocks Jivo in only **486** → **416 pincodes where Blinkit delivers but carries no Jivo** (a distribution gap, not a data gap).

## Why this is flagged as an exception
- It is **not** what the daily cron does — the cron stays on the fast anchor model so the noon deadline holds.
- The full per-pincode runs trip the review's `SUSPECT` flag (row counts ~12× the anchor baseline); that is expected for a coverage pass and is **not** an accuracy problem. Baselines were not rescaled.
- Amazon Fresh + Amazon Now (separate accounts 259 / 520, never merged) are getting the same full pass under Wave 2, guarded so they never collide with the daily cron's Amazon runs.

## Provenance
Source of truth: `data/coverage/ledger.csv` · universe: `docs/pincodes/india-pincode-universe.md` (1,885 pincodes / 25 cities) · design: `docs/superpowers/specs/2026-06-29-coverage-expansion-design.md`.
