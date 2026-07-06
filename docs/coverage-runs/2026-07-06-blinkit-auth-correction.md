# 2026-07-06 Blinkit Auth Correction

## Incident

The first Blinkit report on 2026-07-06 was fresh data, but parts of it were scraped
through an anonymous/headless Blinkit session. Blinkit can show false Out of Stock in
that state while the logged-in web/app session shows the same SKU live.

Confirmed evidence:

- Pincode: `110013`, Delhi / Hazrat Nizamuddin SO
- SKU: Jivo Pomace Olive Oil, 5 L
- PRID: `407561`
- Bad anonymous result: `In stock = No`
- Authenticated live result: ADD available, sale price around `Rs1,875`
- Corrected production output: `In stock = Yes`, sale `1875`, ETA `29`

## Corrected Run

The authenticated Mac Pro Blinkit rerun completed and was delivered on WhatsApp.

- Output workbook: `/opt/ecom-intel/output/Jivo-Blinkit-Live-Report-2026-07-06.xlsx`
- Pincodes in config: `902`
- Resolved pincodes: `870`
- Jivo-priced pincodes: `468`
- Rows: `1915`
- Blocked pincodes: `0`
- Unique stores: `303`
- WhatsApp text id: `3EB0B1B1E781C291CCEB66`
- WhatsApp file id: `3EB0323550CD482EEDD51A`

## OOS Reassessment

The old out-of-stock rows were reassessed after the authenticated rerun.

- Old `No` rows checked: `344`
- Now in stock: `32`
- Still out of stock: `298`
- Missing from corrected output: `14`
- Reassessment CSV: `/opt/ecom-intel/output/blinkit-oos-reassessment-final-2026-07-06.csv`

## Permanent Guardrails

Blinkit production must now run authenticated and fail closed:

- Mac daily auth state: `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`
- VPS emergency/shard auth state: `/opt/ecom-intel/secrets/blinkit-auth-state.json`
- Scraper env: `BLINKIT_REQUIRE_AUTH=1`
- Scraper summary fields: `auth_session`, `auth_required`
- VPS ingest guard: `BLINKIT_REQUIRE_AUTH_DROP=1`
- Missing auth exits before scrape with code `3`
- Unauthenticated Blinkit drops are rejected before build/delivery
- Shard runner auto-discovers the auth state and exits `3` if missing
- Shard merge sets merged `auth_session=1` only when every shard was authenticated
- Mac LaunchAgent: `com.danny.blinkit-mac-to-vps`
- Daily schedule: `06:30` IST
- Mac wrapper: `/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh`

Operational rule: do not publish or accept Blinkit stock data from an anonymous session.
If auth expires or the auth state is missing, the run must fail and alert instead of
delivering a thin or false-OOS report.
