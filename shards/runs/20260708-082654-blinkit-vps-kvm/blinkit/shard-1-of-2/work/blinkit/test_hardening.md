# Blinkit scraper hardening — fault-injection record

Wave-1 coverage pilot (2026-06-29). Hardening added to `platforms/blinkit/scrape.js`:
checkpoint/resume, block-detection + exponential backoff, and partial-run tolerance.
**No proxies, no WAF-evasion** — on a block we only wait and retry politely, then record
`0 rows` and flag the run `partial`. (Owner hard rule.)

2026-07-06 update: authenticated availability is now a required correctness condition.
Anonymous Blinkit sessions can return false Out of Stock for live SKUs, so production
runs fail closed unless `BLINKIT_REQUIRE_AUTH=1` has a valid auth state and Blinkit
accepts it in-page.

2026-07-07 update: ingest now rejects raw drops before promotion when OOS rows are
present without both search and PDP OOS probe summary flags, when OOS rows remain
unverified, when PRID/listing URLs regress, when price arithmetic is inconsistent,
or when the expected pincode config has coordinates outside the India bounding box.
The current promoted repaired artifact is grandfathered with
`BLINKIT_ALLOW_LEGACY_REPAIRED_OOS=1`; new raw drops still fail closed by default.

2026-07-07 live-run correction: the Mac Pro collector copy was synced to the VPS
scraper hash before the 06:30 run, and the Mac wrapper now exports
`BLINKIT_PDP_PRICE_PROBE=1`. The quality monitor rejects any accepted Blinkit result
missing `summary.pdp_price_probe_enabled=1`. A temporary live watcher can be started
with `tools/cron/blinkit_live_watch.sh`; it writes
`logs/blinkit_live_watch-YYYY-MM-DD.log` and repeatedly records Mac process status,
today's expected workbooks, and the read-only quality monitor result.

2026-07-07 post-run hardening: targeted PDP price probes now record
`pdp_price_probe_attempted` and `pdp_price_probe_failed`. Ingest and
`tools/cron/blinkit_quality_monitor.sh` default to `0` allowed failed PDP price
probes, so a stale search-card price cannot be silently delivered when a canary or
high-value PDP probe fails to resolve/parse. The accepted main Blinkit workbook is
also direct-sent to the Ecom WhatsApp group by
`tools/whatsapp/send_blinkit_main_direct.sh`; retry cron and batch spool paths use
`logs/blinkit-main-wa-YYYY-MM-DD.sent` to avoid duplicate group documents.

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

1. **Checkpoint/resume** — `.progress.<IST-date>.json` holds the full per-pincode result
   keyed by pincode, rewritten after every pincode (`saveProgress`). On start,
   `loadProgress()` reloads it and the loop body `if (done[rec.pincode]) return done[...]`
   skips finished pincodes, logging `[resume] N pincodes already done … resuming`.
   Result.json is therefore complete even across a kill/restart, with no duplicate work.
   A resumed production checkpoint is publishable only if it was produced by the
   current authenticated/probed code path and has no `stock_unverified`, stale canary
   price, auth, or coordinate failures. Older or suspect checkpoints must be moved
   aside before rerun. Checkpoint hits skip the normal per-pincode jitter delay, so
   an interrupted full run can resume quickly while fresh pincode scrapes still keep
   the polite pacing.
2. **Block-detection + exponential backoff** — `BLOCK_RE` matches `access denied / akamai /
   reference #N / too many requests / rate-limit / captcha / forbidden` in the page body,
   and HTTP `403/429/503` on the navigation response. A blocked attempt triggers
   `backoff(attempt)` (2s→4s→8s…, capped 60s, jittered) and retries up to
   `MAX_BLOCK_RETRIES` (env `BLINKIT_BLOCK_RETRIES`, default 4); if still blocked it
   records 0 rows and tags the pincode `partial_block`.
3. **Partial tolerance** — one pincode can never throw out of the loop (errors are caught
   in `scrapeOne`; the loop body never rethrows). The run always writes `result.json` with
   a top-level `partial` flag (and `summary.partial` / `summary.pincodes_blocked`).
4. **Auth-required fail-closed mode** — `BLINKIT_REQUIRE_AUTH=1` exits before scraping
   if no Blinkit token is available. The page must also populate logged-in state
   (`localStorage.user`/`authKey`) after hydration; accepted runs mark
   `summary.auth_session=1`, `summary.auth_required=1`, `summary.auth_verified=1`,
   and `summary.auth_verified_pincodes == summary.pincodes_total`.
   Downstream ingest rejects unauthenticated or any-pincode unverified-auth drops by default.
5. **Ingest validation gates** — `ingest.sh` validates identity coverage, OOS probe
   evidence, unverified OOS count, price math, and expected-config coordinates before
   writing `result.json`, building Excel, reviewing, or delivering.
6. **PDP price-probe failure gate** — targeted PDP price checks set attempted/failed
   counters. `BLINKIT_MAX_PDP_PRICE_PROBE_FAILED` and
   `BLINKIT_MONITOR_MAX_PDP_PRICE_PROBE_FAILED` default to `0`, forcing a holdback
   when the run cannot verify a targeted stale-price risk row.
7. **Late main WhatsApp direct send** — accepted Blinkit drops immediately direct-send
   the main workbook to the Ecom WhatsApp group and separately send the not-listed
   workbook to the configured direct contact. Both are idempotent by date marker.

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

## Fault-injection test 3 — auth-required fail closed  ✅ PASS

Steps (hermetic, SIM mode; no live Blinkit calls):

```sh
# Missing auth must fail before scraping.
BLINKIT_SIM=1 BLINKIT_REQUIRE_AUTH=1 PINCODES_FILE=test3.json \
  OUT_FILE=res-noauth.json node scrape.js ; echo "exit=$?"

# Valid auth state must mark the summary as authenticated.
BLINKIT_SIM=1 BLINKIT_REQUIRE_AUTH=1 \
  BLINKIT_AUTH_STATE_FILE=/opt/ecom-intel/secrets/blinkit-auth-state.json \
  PINCODES_FILE=test3.json OUT_FILE=res-auth.json node scrape.js
```

Observed (2026-07-06):
- Missing auth exited `3` with `[auth] BLINKIT_REQUIRE_AUTH=1 but no Blinkit access token was provided`.
- Valid auth wrote `result.json` with `summary.auth_session: 1`,
  `summary.auth_required: 1`, `summary.auth_verified: 1`, and
  `summary.auth_verified_pincodes == summary.pincodes_total`.

Conclusion: the scraper cannot silently fall back to anonymous Blinkit when auth is
required, which prevents the 2026-07-06 false-OOS class from recurring.

## Fault-injection test 4 - ingest gates fail closed  PASS

Steps (validate-only; no promotion/build/delivery):

```sh
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh platforms/blinkit/result.last-good.json

jq 'del(.oos_repair_merge) | del(.summary.correction) | .summary.oos_probe_enabled = 0 | .summary.pdp_oos_probe_enabled = 1 | .summary.unverified_oos = 0' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-no-oos-probe.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-no-oos-probe.json

jq 'del(.oos_repair_merge) | del(.summary.correction) | .summary.oos_probe_enabled = 1 | .summary.pdp_oos_probe_enabled = 0 | .summary.unverified_oos = 0' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-no-pdp-probe.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-no-pdp-probe.json

jq 'del(.oos_repair_merge) | del(.summary.correction) | .summary.oos_probe_enabled = 1 | .summary.pdp_oos_probe_enabled = 1 | .summary.unverified_oos = 5' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-unverified-oos.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-unverified-oos.json

jq '.allRows[0].prid = "" | .allRows[0].listing_url = ""' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-missing-identity.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-missing-identity.json

jq '.allRows[0].listing_url = ""' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-missing-listing-url.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-missing-listing-url.json

jq '.allRows[0].listing_url = "https://blinkit.com/prn/jivo-pomace-olive-oil"' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-bad-listing-url.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-bad-listing-url.json

jq '.allRows[0].per_litre = 1' \
  platforms/blinkit/result.last-good.json > /tmp/blinkit-bad-price.json
BLINKIT_VALIDATE_ONLY=1 platforms/blinkit/ingest.sh /tmp/blinkit-bad-price.json

jq '.[0].lat = 0' platforms/blinkit/pincodes.daily.json > /tmp/blinkit-bad-config.json
BLINKIT_VALIDATE_ONLY=1 BLINKIT_EXPECTED_CONFIG=/tmp/blinkit-bad-config.json \
  platforms/blinkit/ingest.sh platforms/blinkit/result.last-good.json
```

Observed (2026-07-07):
- Current `result.last-good.json` passed validate-only with the legacy repaired-OOS
  compatibility exemption.
- Missing `summary.oos_probe_enabled` failed with `Refusing unprobed Blinkit OOS drop`.
- Missing `summary.pdp_oos_probe_enabled` failed with `Refusing unverified Blinkit OOS drop`.
- Missing `summary.pdp_price_probe_enabled` failed in `tools/cron/blinkit_quality_monitor.sh`
  with `pdp_price_probe_disabled`.
- `summary.pdp_price_probe_failed=1` failed in `tools/cron/blinkit_quality_monitor.sh`
  with `pdp_price_probe_failed`, and ingest rejects the same class via
  `BLINKIT_MAX_PDP_PRICE_PROBE_FAILED=0`.
- Unverified OOS failed with `Refusing excessive unverified Blinkit OOS`.
- Missing PRID, missing listing URL, and malformed listing URL failed with
  `Refusing Blinkit row identity regression`.
- Bad price arithmetic failed with `Refusing Blinkit bad price math`.
- Bad expected-config coordinates failed with
  `Refusing invalid Blinkit expected-config coordinates`.

Default thresholds are fail-closed. Operational overrides are:
`BLINKIT_REQUIRE_OOS_PROBE_ENABLED`, `BLINKIT_REQUIRE_PDP_OOS_PROBE_ENABLED`,
`BLINKIT_MAX_UNVERIFIED_OOS`, `BLINKIT_MAX_MISSING_PRID_RATIO`,
`BLINKIT_MAX_MISSING_LISTING_URL_RATIO`, `BLINKIT_MAX_BAD_LISTING_URL_RATIO`,
`BLINKIT_MAX_BAD_PRICE_ROWS`, `BLINKIT_MAX_PDP_PRICE_PROBE_FAILED`,
`BLINKIT_PRICE_MATH_PER_LITRE_EPS`, `BLINKIT_PRICE_MATH_DISCOUNT_EPS`,
`BLINKIT_INDIA_BBOX`, `BLINKIT_REQUIRE_CONFIG_COORDS`,
`BLINKIT_CONFIG_COORD_ALLOWLIST`, and `BLINKIT_MAX_BAD_CONFIG_COORDS`.

## Current caveat
The checkpoint filename now uses the **IST** date, matching the daily business date
and the Mac wrapper. That avoids the old UTC/IST split around 05:30. The remaining
operator risk is semantic, not date-based: do not resume from a checkpoint created
before the current auth/OOS/PDP-price fixes, or from any checkpoint that the live
watcher/quality monitor has already shown to be dirty.
