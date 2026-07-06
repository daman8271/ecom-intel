# Blinkit scraper hardening — fault-injection record

Wave-1 coverage pilot (2026-06-29). Hardening added to `platforms/blinkit/scrape.js`:
checkpoint/resume, block-detection + exponential backoff, and partial-run tolerance.
**No proxies, no WAF-evasion** — on a block we only wait and retry politely, then record
`0 rows` and flag the run `partial`. (Owner hard rule.)

## Code map (line numbers as of this commit)

| Concern | Location |
|---|---|
| Per-pincode worker | `scrapeOne(browser, rec)` — line 132 |
| HTTP navigations (fetch) | `page.goto(...)` — landing line 179, resolve-loop line 201, Jivo search line 220 |
| Block check on landing | `pageBlocked()` call after line 179 (returns early with `blocked` set) |
| Block check on nav error | `catch` in `scrapeOne` — sets `blocked='block-error'` if `BLOCK_RE` matches `e.message` |
| Concurrency loop | `pool(items, n, fn)` — line 324 (`while (i < items.length)` line 328) |
| Backoff-retry wrapper | `scrapeWithBackoff(browser, rec)` — line 346 |
| Per-pincode loop body (checkpoint) | `pool(PINCODES, ...)` callback — line 366 |

## What was added

1. **Checkpoint/resume** — `.progress.<UTC-date>.json` holds the full per-pincode result
   keyed by pincode, rewritten after every pincode (`saveProgress`). On start,
   `loadProgress()` reloads it and the loop body `if (done[rec.pincode]) return done[...]`
   skips finished pincodes, logging `[resume] N pincodes already done … resuming`.
   Result.json is therefore complete even across a kill/restart, with no duplicate work.
2. **Block-detection + exponential backoff** — `BLOCK_RE` matches `access denied / akamai /
   reference #N / too many requests / rate-limit / captcha / forbidden` in the page body,
   and HTTP `403/429/503` on the navigation response. A blocked attempt triggers
   `backoff(attempt)` (2s→4s→8s…, capped 60s, jittered) and retries up to
   `MAX_BLOCK_RETRIES` (env `BLINKIT_BLOCK_RETRIES`, default 4); if still blocked it
   records 0 rows and tags the pincode `partial_block`.
3. **Partial tolerance** — one pincode can never throw out of the loop (errors are caught
   in `scrapeOne`; the loop body never rethrows). The run always writes `result.json` with
   a top-level `partial` flag (and `summary.partial` / `summary.pincodes_blocked`).

SIM hooks for hermetic tests (inert in production — only active when the env var is set):
`BLINKIT_SIM=1` returns a synthetic resolved row with no browser; `BLINKIT_BLOCK_SIM=1`
makes every pincode report blocked.

## Fault-injection test 1 — kill & resume  ✅ PASS

Steps (hermetic, SIM mode; same logic exercised as a live kill):
```
# Phase A: full run over a 10-pincode config -> checkpoint has 10 entries
BLINKIT_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resA.json node scrape.js
# Simulate a kill after 4 pincodes: truncate .progress.<date>.json to its first 4 keys
# Phase B: re-run same config
BLINKIT_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resB.json node scrape.js
```
Observed (2026-06-28):
- Phase A wrote a checkpoint with **10** entries.
- Phase B logged `[resume] 4 pincodes already done … resuming` (skipped the 4 finished
  pincodes), then scraped the remaining 6.
- Final `resB.json` perPin = **10 pincodes, 10 distinct, 0 duplicates**, all 10 present.

Conclusion: resume skips already-done pincodes and finishes the run with no duplicate work.

## Fault-injection test 2 — block tolerance  ✅ PASS

Steps (simulate every pincode being blocked):
```
BLINKIT_BLOCK_SIM=1 BLINKIT_BLOCK_RETRIES=1 PINCODES_FILE=test3.json \
  OUT_FILE=resBlk.json node scrape.js ; echo "exit=$?"
```
Observed (2026-06-28):
- `[backoff] attempt 0 -> sleeping ~2.x s` for each pincode, then
  `[blocked] … still blocked after 1 retry (sim-block); recording 0 rows, run is partial`.
- **Process exit code = 0** (the batch wrapper does NOT crash).
- `result.json`: `partial: true`, `summary.pincodes_blocked: 3`, `total_rows: 0`, and every
  `perPin` entry tagged `partial_block: true`.

Conclusion: blocks back off, then degrade honestly to 0 rows + `partial=true` and exit 0;
the run is never killed and no fabricated rows are recorded.

## Known caveat
The checkpoint filename uses the **UTC** date (`new Date().toISOString()`), while
`run.sh`'s ledger `date_ist` uses the local (IST) date. They differ only for a run that
spans UTC midnight (~05:30 IST); such a run would start a fresh checkpoint file mid-way
(re-scraping, never corrupting). Acceptable for the daily pilot; revisit if runs straddle
05:30 IST.
