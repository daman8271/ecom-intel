# Blinkit Four-Host Device Parity Test

Test window: 14 July 2026, 02:35:18-02:38:38 IST.

## Verdict

The four-host test is a partial pass, not approval for four-way production
sharding. Mac Pro, Windows, and KVM-1 through the Mac Air residential SOCKS
proxy produced the same 21 normalized rows. The primary VPS direct path matched
20 of 21 rows and failed strict parity on one price/stock observation.

No production schedule or shard allocation was changed.

## Controls

- Same four audited locations: 110094, 110082, 400032, and 201317.
- Same coordinates and config SHA-256 on every host.
- Same scraper SHA-256 on every host.
- Auth, OOS probes, PDP OOS probes, and PDP price probes enabled.
- Concurrency 1 on each host; starts were within three seconds.

## Host Results

| Host | Network path | Runtime | Pins | Rows | Exact rows vs residential consensus | PDP failures | Unverified OOS | Parity |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Mac Pro | Residential direct | 188s | 4/4 | 21 | 21/21 | 2 | 1 | Pass |
| Windows | Residential direct | 190s | 4/4 | 21 | 21/21 | 2 | 1 | Pass; test receipt note below |
| KVM-1 | Mac Air residential SOCKS | 200s | 4/4 | 21 | 21/21 | 2 | 1 | Pass, proxy-dependent |
| Primary VPS | Datacenter direct | 172s | 4/4 | 21 | 20/21 | 1 | 2 | Fail |

All hosts authenticated and resolved the same primary store for all four PIN
codes. Mac Pro, Windows, and KVM-1 also matched exactly on product identity,
sale price, MRP, stock state, resolved row store, and price/stock source.

## Direct VPS Mismatch

At PIN 110082 for product `406593` (Jivo Cold Pressed Canola Oil 5L):

| Observation | Sale | MRP | Stock | Row store | Source |
|---|---:|---:|---|---:|---|
| Residential consensus | Rs 1,240 | Rs 1,650 | In stock | 46791 | Nearby same-PIN search probe |
| Primary VPS direct | Rs 1,196 | Rs 1,650 | Unverified | 30299 | Primary search card |

The direct VPS did not reproduce the nearby-store stock recovery seen on all
three residential routes. That makes it unsafe to merge into tomorrow's report
under an exact-parity rule.

## Quality Risk

Every host returned nonzero PDP-price failures and at least one unverified OOS
row. Even the three matching paths would be held by the strict production
quality gate for this sample. Device parity does not override those gates.

KVM-1's pass is not evidence that its datacenter IP works: its requests exited
through the personal Mac Air proxy. Under the existing emergency-only rule, it
should not become a normal daily shard.

## Test Receipt Note

The temporary Windows parity wrapper produced an empty `windows.run.rc` file
because `echo 0>run.rc` was parsed as an fd-0 redirect. The SSH command itself
exited 0 and the result is complete (`partial:false`, 21 rows, 4/4 authenticated
pins). The normal production Windows runner already uses `>run.rc echo %RC%`, so
this test-harness-only issue does not affect tomorrow's existing shard.

## Independent Audit

Claude Code Opus 4.8 reviewed the package read-only, verified all checksums and
the four raw result files, and independently confirmed the host verdict. It did
not edit files or rerun any scrape.

## Limits

This was a four-PIN night sample, not proof over all 1,791 PIN codes. The Mac Pro
was also running Swiggy, so runtime comparisons are indicative only; row parity
was unaffected in this sample.

Raw evidence is preserved in the four `*.result.json` files, host stderr/stdout
logs, `all-rows.csv`, `pin-resolution.csv`, and `summary.csv` in this directory.
