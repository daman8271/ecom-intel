# Zepto scraper hardening — fault-injection record

Wave-1 coverage pilot (2026-06-29), Task 8. Hardening added to `platforms/zepto/scrape.js`:
checkpoint/resume, block-detection + exponential backoff, and partial-run tolerance.
Mirrors the proven Blinkit pilot (commit `c4ab885d5`), adapted to Zepto's **curl / BFF-API**
structure (no browser — a block shows up as an HTTP status `403/429/503` or a block-signature
in the response body, not a rendered page). **No proxies, no WAF-evasion** — on a block we only
wait and retry politely, then record `0 rows` and flag the run `partial`. (Owner hard rule.)

## Code map (line numbers as of this commit)

| Concern | Location |
|---|---|
| Per-pincode worker | `scrapeOne(rec)` — line 452 |
| HTTP entry call (store resolution) | `resolveStore(lat, lon)` — line 236 (curl → `{status, body}`) |
| HTTP search call | `searchPage(...)` — line 277 (already had 429-retry; now also returns `blocked`) |
| HTTP PDP call | `fetchPdp(...)` — 429-retry path, unchanged |
| Block classifier | `classifyBlock(status, body)` — line 114 (`BLOCK_RE` line 109, `isBlockStatus`) |
| Block check on store-resolution | `resolveStore` returns `blocked`; `scrapeOne` early-returns with it set |
| Block check on primary search | `collectQuery` returns `{markers, blocked}`; `scrapeOne` early-returns on a page-0 block |
| Block check on thrown error | `catch` in `scrapeOne` — sets `blocked='block-error'` if `BLOCK_RE` matches `e.message` |
| Concurrency loop | `pool(items, n, fn)` — line 552 |
| Backoff-retry wrapper | `scrapeWithBackoff(rec)` — line 540 |
| Per-pincode loop body (checkpoint) | `pool(PINCODES, ...)` callback — line 569 (`if (require.main === module)`) |

## What was added

1. **Checkpoint/resume** — `.progress.<UTC-date>.json` holds the full per-pincode result
   keyed by `pincode`, rewritten after every pincode (`saveProgress`). On start,
   `loadProgress()` reloads it and the loop body `if (done[rec.pincode]) return done[...]`
   skips finished pincodes, logging `[resume] N pincodes already done … resuming`.
   `result.json` is therefore complete even across a kill/restart, with no duplicate work.
   (The full25 config has 1,885 **distinct** pincodes, so the key never collides.)
2. **Block-detection + exponential backoff** — `BLOCK_RE` matches `access denied / akamai /
   reference #N / too many requests / rate-limit / captcha / forbidden / cloudfront /
   request blocked` in the response body, and HTTP `403 / 429 / 503` on the per-pincode
   ENTRY calls (store-resolution and the primary `jivo` search). A blocked attempt triggers
   `backoff(attempt)` (2s→4s→8s…, capped 60s, jittered) and retries up to
   `MAX_BLOCK_RETRIES` (env `ZEPTO_BLOCK_RETRIES`, default 4); if still blocked it records
   0 rows and tags the pincode `partial_block`. This closes the silent-false-green gap where
   a gateway 403 previously read as "not serviceable, 0 rows" with no signal. (The existing
   per-call 429 micro-retry inside `searchPage`/`fetchPdp` is unchanged and runs first; the
   per-pincode backoff is the outer, coarser net.)
3. **Partial tolerance** — one pincode can never throw out of the loop (errors are caught in
   `scrapeOne`; the loop body never rethrows). The run always writes `result.json` with a
   top-level `partial` flag (and `summary.partial` / `summary.pincodes_blocked`).

SIM hooks for hermetic tests (inert in production — only active when the env var is set):
`ZEPTO_SIM=1` returns a synthetic serviceable row with no network call; `ZEPTO_BLOCK_SIM=1`
makes every pincode report blocked.

## Fault-injection test 1 — kill & resume  ✅ PASS

Steps (hermetic, SIM mode; same logic exercised as a live kill):
```
# Phase A: full run over a 10-pincode config -> checkpoint has 10 entries
ZEPTO_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resA.json node scrape.js
# Simulate a kill after 4 pincodes: truncate .progress.<date>.json to its first 4 keys
# Phase B: re-run same config
ZEPTO_SIM=1 PINCODES_FILE=test10.json OUT_FILE=resB.json node scrape.js
```
Observed (2026-06-29):
- Phase A wrote a checkpoint with **10** entries (`summary.pincodes_serviceable=10`).
- Phase B logged `[resume] 4 pincodes already done … resuming` (skipped the 4 finished
  pincodes), then scraped the remaining 6.
- Final `resB.json` perPin = **10 pincodes, 10 distinct, 0 duplicates**, `partial: false`.

Conclusion: resume skips already-done pincodes and finishes the run with no duplicate work.

## Fault-injection test 2 — block tolerance  ✅ PASS

Steps (simulate every pincode being blocked):
```
ZEPTO_BLOCK_SIM=1 ZEPTO_BLOCK_RETRIES=1 PINCODES_FILE=test3.json \
  OUT_FILE=resBlk.json node scrape.js ; echo "exit=$?"
```
Observed (2026-06-29):
- `[backoff] attempt 0 -> sleeping ~2.x s` for each pincode, then
  `[blocked] … still blocked after 1 retry (sim-block); recording 0 rows, run is partial`.
- **Process exit code = 0** (the batch wrapper does NOT crash).
- `result.json`: `partial: true`, `summary.partial: true`, `summary.pincodes_blocked: 3`,
  `total_rows: 0`, and every `perPin` entry tagged `partial_block: true`.

Conclusion: blocks back off, then degrade honestly to 0 rows + `partial=true` and exit 0;
the run is never killed and no fabricated rows are recorded.

## Live smoke test — 1 pincode  ✅ PASS

Confirms Zepto is reachable from this IP and the hardening does not interfere with the normal
(non-blocked) path. Output written to a scratch file (no live full/zero-cities scrape):
```
COVERAGE_FULL=1 PINCODES_FILE=<1-pincode subset of pincodes.full25.json> \
  OUT_FILE=<scratch>/smoke_out.json node scrape.js
```
Observed (2026-06-29, Mumbai 400001):
- `[ok] Mumbai 400001 serviceable=true -> 23 jivo SKUs (18.2s)`.
- `summary`: serviceable=1, with_jivo=1, total_rows=23, unique_skus=23, **pincodes_blocked=0**,
  **partial=false**, exit 0. (`pct_non_realtime=100`, reason `mongo_data_exists` — the normal
  Zepto snapshot path, unrelated to blocking.)

Conclusion: reachable, no block, hardening is a transparent no-op on the healthy path.

## Known caveat
The checkpoint filename uses the **UTC** date (`new Date().toISOString()`), while `run.sh`'s
ledger `date_ist` uses the local (IST) date. They differ only for a run that spans UTC midnight
(~05:30 IST); such a run would start a fresh checkpoint file mid-way (re-scraping, never
corrupting). Acceptable for the daily pilot; revisit if runs straddle 05:30 IST. `.progress.*`
files are gitignored (`.gitignore` line 65) and removed after each test/smoke run so they never
shadow the daily cron's own run.
