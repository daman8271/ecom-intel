# 2026-07-07 Blinkit Live Run Monitoring

Purpose: guard the first daily run after the 2026-07-06 false-OOS and stale-price
incident.

## Current Rule

Blinkit production must run from the Mac Pro residential/login session through
`/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh`. The wrapper must
export:

- `BLINKIT_REQUIRE_AUTH=1`
- `BLINKIT_OOS_PROBE=1`
- `BLINKIT_PDP_OOS_PROBE=1`
- `BLINKIT_PDP_PRICE_PROBE=1`

VPS ingest must keep `BLINKIT_REQUIRE_AUTH_DROP=1`; accepted drops must carry
`summary.auth_session=1`, `summary.auth_required=1`, `summary.auth_verified=1`, and
`summary.auth_verified_pincodes == summary.pincodes_total`.

## Data Semantics

Blinkit pincode text is not the source of truth. The scraper injects coordinates and
Blinkit resolves a dark store for that logged-in session. The same visible pincode can
show different stock or price if the coordinate resolves to another nearby store.

`Listed - Out of stock` means Blinkit listed the SKU for that resolved store and the
OOS state survived the required search/PDP probes. `Not listed` means the expected SKU
was absent for that resolved store; it is not an OOS row.

`Listed - Stock unverified` is not publishable stock data. It means search text looked
OOS but PDP/nearby verification did not complete; ingest and delivery quality gates
reject that state. PDP price probing now covers the screenshot canaries plus
5 L high-value/plain-search rows without offer evidence, because Blinkit can put the lower
effective price only on the PDP/offer block.

For Delhi, false-OOS recovery includes close neighbor-pincode coordinate probes,
not just tiny offsets around the same stored coordinate. If that probe proves stock,
the row's stock/store proof stays attached to that probe location. Later PDP price
checks are price-only: they may update sale/MRP diagnostics, but they must not
rewrite `in_stock`, `listing_status`, `stock_source`, `store_id`, or `store_name`.

## Delivery Gate

The main workbook must include `Listing Status` and `Not Listed Pincodes`. The
standalone `Jivo-Blinkit-Not-Listed-Pincodes-YYYY-MM-DD.xlsx` is delivered to
`917703818227@s.whatsapp.net` only after the main Blinkit workbook passes the quality
monitor. If the main workbook is held, the not-listed direct WhatsApp is skipped too.
The monitor's cron poll alerts; delivery callers run it with
`BLINKIT_MONITOR_EXIT_CODE=1` to block shipping.

## Live Watch

`tools/cron/blinkit_live_watch.sh` runs in tmux and logs Mac process status,
Mac progress counts (`done/resolved/auth_ok/blocked/rows/stock_unverified`), latest
Mac run-log tail, today-dated workbook presence, and dry-run quality-monitor output
until 10:45 IST. The normal cron monitor still runs separately and can alert.

For daily runs, cron starts `tools/cron/start_blinkit_live_watch.sh` at 05:00 IST
and again at 06:25 IST. The starter is idempotent: if
`blinkit-live-watch-YYYYMMDD` already exists, it does nothing.

The live-run hook for tomorrow is therefore:

- `05:00` and `06:25`: start the once-per-day tmux watcher.
- `*/15 05-10`: run `blinkit_quality_monitor.sh poll` and wait if the Mac job is
  still active.
- `*/15 06-12`: retry the standalone not-listed WhatsApp send only after the main
  Blinkit workbook passes quality and no sent marker exists.

Operationally, the watcher is the activation hook: once the Mac scrape starts, it
records live progress side by side and the quality monitor blocks stale, anonymous,
unprobed, stock-unverified, or missing-workbook output from WhatsApp. Manual action
is only needed when the watcher shows no progress, an SSH/tunnel outage, or a hard
quality failure.

If the Mac scrape is still active after the stale-result cutoff, the quality monitor
keeps returning a waiting state instead of alerting on yesterday's `result.json`.
That prevents a slow authenticated run from being misclassified as a stale report
while it is still producing today's drop.

If the VPS-to-Mac reverse tunnel is down while the workbook is still missing, the
monitor also waits until the workbook cutoff (`10:05`) instead of treating the old
`result.json` as final at `09:15`. A present workbook is still validated normally,
and a missing workbook after `10:05` is still a delivery failure.

## 04:00 Hotfix

The first restarted run was stopped because a 5 L Pomace row picked up a 1 L
PDP/related-card price. The hotfix rejects PDP price updates unless the PDP-detected
pack/volume before the first price matches the row volume, then the Blinkit run was
restarted from a clean progress file.

A second stop happened when repeated nearby PDP checks hit Blinkit's access-denied
page and left `400006 / Canola 1 L` as `Listed - Stock unverified`. PDP OOS
verification now defaults to the primary PDP only; nearby same-pincode search probes
still handle false-OOS flips. The isolated `400006` repro then passed with
`unverified_oos=0`.

## 05:15 Hotfix

The `110012 / IARI SO` repro showed the core coordinate issue directly. Primary
search saw Canola 1 L as live but treated Canola 5 L and Pomace 5 L as OOS; the
close `110011` coordinate resolved store `30790` and showed both 5 L SKUs live.
The first patch flipped them live, but the later PDP price probe rechecked the
primary location and could overwrite the stock proof. The fix now runs PDP price
checks for probe-flipped rows against the same neighbor coordinate and preserves
the stock fields. The focused 3-pincode repro passed with `unverified_oos=0`,
`110012 / 406593` live at `1193/1650`, and `110012 / 407561` live at `1687/4999`.

## 06:15 Hotfix

The clean full run was stopped at Bengaluru because localized card titles such as
`Jivo Cold Pressed Canola Oil (Canola Enne)` and
`Jivo Extra Light Olive Oil (Olive Enne)` left a few search-card OOS rows as
`stock_unverified`. The primary PDP parser was matching the localized title too
strictly, and the wrong-pack guard correctly rejected nearby 1 L/2 L segments when
they did not match the row volume. The fix now tries both the displayed localized
title and the base English title, then still accepts stock/price only when the PDP
segment volume matches the row. Offline tests and the 4-pincode Bengaluru repro
passed with `unverified_oos=0`.

## 08:22 Live Checkpoint

The clean full run restarted from the Mac at `2026-07-07 06:21:57 IST` with
`auth=required`, `BLINKIT_OOS_PROBE=1`, `BLINKIT_PDP_OOS_PROBE=1`, and
`BLINKIT_PDP_PRICE_PROBE=1`. At `08:22:49 IST`, progress was:

- `570/902` pincodes touched.
- `545` resolved.
- `570` auth accepted.
- `0` blocked.
- `1526` rows.
- `0` `stock_unverified`.
- `0` bad low 5 L prices.

The VPS quality monitor correctly waited because the 2026-07-07 workbook had not
landed yet and the Mac process was still active. It did not send the stale
2026-07-06 workbook.

## 08:32 Tunnel Outage

The VPS-to-Mac reverse tunnel on `127.0.0.1:22022` dropped after the last clean
Mac progress checkpoint. Last direct progress before the outage was clean:

- `612/902` pincodes touched.
- `587` resolved.
- `612` auth accepted.
- `0` blocked.
- `1526` rows.
- `0` `stock_unverified`.

The `08:45` Blinkit batch guard saw no 2026-07-07 workbook and attempted a Mac
rerun, but the trigger failed because SSH was unreachable. Health remained failed
at `08:50`. The VPS monitor is deliberately holding delivery and waiting for either
a fresh Mac drop or the `10:05` missing-workbook cutoff.

A small VPS emergency canary against `110012`, `110013`, `110094`, `400006`, and
Bengaluru localized rows verified that the scraper logic still flips false OOS rows
and keeps `unverified_oos=0`, but it also showed VPS/datacenter price/store behavior
can differ from the Mac residential session. Therefore VPS canary output is useful
diagnostically only; it must not replace the production Mac-auth Blinkit workbook
unless the full drop passes the normal hard gates.

## 09:46-09:51 Late Resume

The Mac reverse tunnel recovered at `09:45 IST`. A late Mac run started at
`09:46:37 IST` with the same production wrapper, auth state, and probe flags:

- `BLINKIT_REQUIRE_AUTH=1`
- `BLINKIT_OOS_PROBE=1`
- `BLINKIT_PDP_OOS_PROBE=1`
- `BLINKIT_PDP_PRICE_PROBE=1`

The run resumed from the existing `.progress.2026-07-07.json` checkpoint containing
`626/902` pincodes. That checkpoint was from the corrected authenticated run after
the 04:00, 05:15, and 06:15 fixes; prior live checks showed `0` stock-unverified rows
and clean Delhi/Bengaluru canaries. Resume is acceptable in this case because the
partial checkpoint had already passed the false-OOS guardrails. If a checkpoint was
created before the auth/probe fixes, or contains `stock_unverified` rows, stale
canary prices, unauthenticated pincodes, or bad coordinates, it must be moved aside
and the Mac run must restart cleanly.

The first late process showed that checkpoint hits were still paying the normal
per-pincode jitter before reaching new work. `platforms/blinkit/scrape.js` now marks
checkpoint hits internally and skips that delay, so resumed runs jump straight to the
remaining pincodes while real fresh pincode scrapes keep the normal jitter. The
patched scraper was synced to the Mac, the idle late process was replaced, and the
new `09:51:05 IST` run moved past the checkpoint immediately, completing
`160017` and `160018` by `09:51:48 IST`.

No Blinkit workbook should be delivered until the final Mac drop is ingested and the
quality monitor accepts the main workbook. If the final drop misses the cutoff or
fails quality, the 10:00 batch must exclude Blinkit and the not-listed WhatsApp must
remain unsent.

## 10:35 Completion

The late Mac run completed at `10:35 IST` and dropped
`blinkit-20260707-095105.json` to VPS ingest. Final scrape summary:

- `902/902` pincodes processed.
- `876` resolved.
- `902` auth-verified pincodes.
- `481` pincodes with Jivo rows.
- `1977` rows.
- `0` blocked.
- `0` unverified OOS.
- `0` stock-unverified rows.
- `216` OOS rows flipped live by probes.
- `354` PDP price probes, `2` PDP price updates.

VPS ingest accepted the drop, built `Jivo-Blinkit-Live-Report-2026-07-07.xlsx`
and `Jivo-Blinkit-Not-Listed-Pincodes-2026-07-07.xlsx`, and the quality monitor
passed with no issues. The key screenshot canaries were green:

- `110094 / 407561` Pomace 5 L: live, sale `1766`, stock proof
  `neighbor-110090`, price source `pdp_price_probe`.
- `110012 / 407851` Canola 1 L: live, sale `239`, PDP price checked.
- `110012 / 406593` Canola 5 L: live, sale `1193`, PDP price checked.

The 10:00 batch had already been released without Blinkit (`8` reports sent,
`2` missing), so no stale or partial Blinkit workbook was sent in the batch.
After quality passed, the late corrected main Blinkit workbook was sent to the
Ecom team WhatsApp group:

- Header message id: `3EB07A1EAF4BE43C9AB1EE`
- Main workbook document id: `3EB0B8660A2BA960CC855F`

The standalone not-listed workbook was sent separately to
`917703818227@s.whatsapp.net`:

- Header message id: `3EB03CAD5D61A67203FEFE`
- Not-listed workbook document id: `3EB05E1F0ED6C4A70BED98`
