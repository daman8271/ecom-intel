# Flipkart-minutes scraper hardening — fault-injection record

Wave-1 coverage pilot (2026-06-29). Hardening added to `platforms/flipkart-minutes/scrape.js`:
checkpoint/resume, block-detection + exponential backoff, and partial-run tolerance —
mirroring the proven blinkit pilot (commit `c4ab885d5`), adapted to this scraper's
**direct-API / round-robin-bucket** architecture (not blinkit's `pool()` worker).
**No proxies, no WAF-evasion** — on a block we only wait and retry politely, then record
`0 rows` and flag the run `partial`. (Owner hard rule.)

## Code map (line numbers as of this commit)

| Concern | Location |
|---|---|
| Per-pincode worker | `scrapePincode(page, rec)` — line 242 |
| BFF calls (fetch) | `api(page, url, body)` — `location/update` + `page/fetch` inside `scrapePincode` |
| Block classify | `respBlocked(resp)` — line 99 (HTTP 403/429/503, or `BLOCK_RE` on a non-JSON body) |
| Backoff sleep | `backoff(attempt)` — line 89 (2s→4s→8s…, capped 60s, jittered) |
| Backoff-retry wrapper | `scrapeWithBackoff(page, rec)` — line 294 |
| Checkpoint load/save | `loadProgress()` / `saveProgress()` — line 108 |
| Per-pincode loop body (checkpoint) | bucket loop in the main IIFE — `if (done[rec.pincode])` line 363 |

## What was added

1. **Checkpoint/resume** — `.progress.<UTC-date>.json` holds the full per-pincode result
   keyed by pincode, rewritten after every pincode (`saveProgress`). On start,
   `loadProgress()` reloads it and the bucket-loop body `if (done[rec.pincode]) { … continue; }`
   skips finished pincodes, logging `[resume] N pincodes already done … resuming`.
   `result.json` is therefore complete even across a kill/restart, with no duplicate work.
   (The buckets run concurrently via `Promise.all`, but Node is single-threaded so each
   `saveProgress` write is atomic; the shared `done` map is only mutated at `await`
   boundaries.)
2. **Block-detection + exponential backoff** — `respBlocked()` flags HTTP `403/429/503` on
   either BFF call (`location/update`, `page/fetch`), or an Akamai/`access denied`/`captcha`/
   `forbidden` signature (`BLOCK_RE`) in a non-JSON body (Akamai serves an HTML wall instead
   of JSON when it blocks the IP). A blocked attempt triggers `backoff(attempt)` and retries
   up to `MAX_BLOCK_RETRIES` (env `FKM_BLOCK_RETRIES`, default 4); if still blocked it records
   0 rows and tags the pincode `partial_block`. A plain non-200 such as the existing `302`
   redirect (location not yet applied) is **not** a block — it stays on the normal
   serviceability path.
3. **Partial tolerance** — one pincode can never throw out of the bucket loop (the call to
   `scrapeWithBackoff` is wrapped in `try/catch`; a failure degrades to a 0-row record and
   the loop continues). The run always writes `result.json` with a top-level `partial` flag
   (and `summary.partial` / `summary.pincodes_blocked`).

SIM hooks for hermetic tests (inert in production — only active when the env var is set):
`FKM_SIM=1` returns a synthetic serviceable row with no browser; `FKM_BLOCK_SIM=1` makes
every pincode report blocked. Both short-circuit before any network call, so they also skip
the live session/health-check and the browser fallback.

## Fault-injection test 1 — kill & resume  ✅ PASS

Steps (hermetic, SIM mode; same logic exercised as a live kill):
```
# Phase A: full run over a 10-pincode config -> checkpoint has 10 entries
FKM_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resA.json node scrape.js
# Simulate a kill after 4 pincodes: truncate .progress.<date>.json to its first 4 keys
# Phase B: re-run same config
FKM_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resB.json node scrape.js
```
Observed (2026-06-29):
- Phase A wrote a checkpoint with **10** entries.
- Phase B logged `[resume] 4 pincodes already done … resuming` (skipped the 4 finished
  pincodes), then processed the remaining 6.
- Final `resB.json` perPin = **10 pincodes, 10 distinct, 0 duplicates**, all 10 present;
  `partial: false`, `total_rows: 10`.

Conclusion: resume skips already-done pincodes and finishes the run with no duplicate work.

## Fault-injection test 2 — block tolerance  ✅ PASS

Steps (simulate every pincode being blocked):
```
FKM_BLOCK_SIM=1 FKM_BLOCK_RETRIES=1 FKM_CONCURRENCY=1 PINCODES_FILE=test3.json \
  OUT_FILE=resBlk.json node scrape.js ; echo "exit=$?"
```
Observed (2026-06-29):
- `[backoff] attempt 0 -> sleeping ~2–3 s` for each pincode, then
  `[blocked] … still blocked after 1 retry (sim-block); recording 0 rows, run is partial`.
- **Process exit code = 0** (the batch wrapper does NOT crash).
- `result.json`: `partial: true`, `summary.pincodes_blocked: 3`, `total_rows: 0`, and every
  `perPin` entry tagged `partial_block: true`.

Conclusion: blocks back off, then degrade honestly to 0 rows + `partial=true` and exit 0;
the run is never killed and no fabricated rows are recorded.

## One-pincode live smoke  ✅ reachable / exit 0 (session expired → fell back)
```
COVERAGE_FULL=1 PINCODES_FILE=<1-pincode from pincodes.full25.json (Mumbai 400001)> \
  FKM_CONCURRENCY=1 node scrape.js
```
Observed (2026-06-29): the box **reaches Flipkart** and the run exits **0**. The API
health-check (`Noida 201304`) returned no Jivo, so the scraper correctly took its existing
`scrape.browser.js` fallback (the logged-in `storageState` cookies are expired — a
pre-existing environment condition, NOT caused by this change, and out of scope: re-export
via `import_cookies.js` is the owner's step; secrets are untouched here). The fallback
scraped Mumbai 400001 (serviceable, 0 Jivo SKUs) and exited 0. `respBlocked()` correctly did
**not** classify the empty/expired-session response as a block (it is not 403/429/503), so no
spurious backoff fired. The hardened API path itself is proven by the two SIM tests above and
by `node --check` + the offline `require()` export check (no browser launched on import).

## Known caveat (same as blinkit)
The checkpoint filename uses the **UTC** date (`new Date().toISOString()`), while
`run.sh`'s ledger `date_ist` uses the local (IST) date. They differ only for a run that
spans UTC midnight (~05:30 IST); such a run would start a fresh checkpoint file mid-way
(re-scraping, never corrupting). Acceptable for the daily pilot; revisit if runs straddle
05:30 IST.
