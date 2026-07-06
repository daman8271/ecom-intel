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

VPS ingest must keep `BLINKIT_REQUIRE_AUTH_DROP=1`.

## Data Semantics

Blinkit pincode text is not the source of truth. The scraper injects coordinates and
Blinkit resolves a dark store for that logged-in session. The same visible pincode can
show different stock or price if the coordinate resolves to another nearby store.

`Listed - Out of stock` means Blinkit listed the SKU for that resolved store and the
OOS state survived the required search/PDP probes. `Not listed` means the expected SKU
was absent for that resolved store; it is not an OOS row.

## Delivery Gate

The main workbook must include `Listing Status` and `Not Listed Pincodes`. The
standalone `Jivo-Blinkit-Not-Listed-Pincodes-YYYY-MM-DD.xlsx` is delivered to
`917703818227@s.whatsapp.net` only after the main Blinkit workbook passes the quality
monitor. If the main workbook is held, the not-listed direct WhatsApp is skipped too.

## Live Watch

For the 2026-07-07 run, `tools/cron/blinkit_live_watch.sh` is running in tmux and logs
Mac process status, today-dated workbook presence, and dry-run quality-monitor output
until 10:45 IST. The normal cron monitor still runs separately and can alert.

For future daily runs, cron starts `tools/cron/start_blinkit_live_watch.sh` at 06:25
IST. The starter is idempotent: if `blinkit-live-watch-YYYYMMDD` already exists, it
does nothing.
