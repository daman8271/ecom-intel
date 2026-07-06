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
