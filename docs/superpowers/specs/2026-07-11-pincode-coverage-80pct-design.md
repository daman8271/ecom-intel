# Pincode Coverage → literal 80% minimum, all cells, big-bang — Design

**Date:** 2026-07-11 · **Owner decisions:** literal 80% (list membership) · Amazon Fresh+Now included at full literal · big-bang rollout in one sweep (tonight 00:30 IST chain → live morning 2026-07-12).

## 1 · Goal

Every per-pincode platform cell in the 24-city matrix on jivo-city-coverage-guide.vercel.app reads **≥80% of that city's India Post district universe**, measured exactly the way the site measures it: pins present in the platform's daily cron list. The five zero cities (Amritsar, Jalandhar, Mangalore, Howrah, Madurai) plus thin cities (Mohali, Faridabad, Nashik, Nagpur, Coimbatore, …) are covered on all 7 per-pincode platforms.

Explicitly accepted by owner (2026-07-11):

- Many added pins will return "not serviceable" daily — the metric is attempted coverage, not yield. We log serviceability outcomes but never auto-drop pins.
- Amazon account-flag risk at ~1,260 pins/day on each of the two accounts (fresh='Damanpreet', now='Kanhaiya').
- ~3× scrape volume across all platforms in a single night.

Non-goals: national platforms (Amazon marketplace, Flipkart marketplace, BigBasket price) unchanged; no pin currently scraped is dropped (all outside-city pins — Jaipur, Kochi, Indore, Surat, etc. — stay); no serviceability-based pruning in this project.

## 2 · Target pin set (shared across all platforms)

- **Universe source:** `/opt/ecom-intel/docs/pincodes/drr_pincode.csv` (India Post June-2024, 19,300 PINs), same 24 district definitions the guide used (Delhi = NCT, Mumbai = City+Suburban, Noida = Gautam Buddha Nagar, Chandigarh = whole UT, Mohali = S.A.S Nagar, Mangalore = Dakshina Kannada, etc.). A new `tools/pincodes/universe_guide24.py` encodes these 24 predicates (separate file from `universe25.py`, which belongs to the pincode-leads programme and has a different city list — do not touch it).
- **Selection:** per city, take **~85% of universe pins** (buffer above 80%). Ranking for inclusion: (1) pins already in ANY platform's live list, (2) Head/Sub post-office pins (urban), (3) Branch-office pins (rural) last — so the excluded ~15% are the most-rural pins.
- **Determinism:** one generator script emits the per-city target set + per-platform merged lists; committed, re-runnable, asserts ≥80% per city before writing anything.
- **List ordering — existing pins first:** every generated list puts the platform's current pins at the front and new pins appended after. Proven-yield pins therefore finish on today's timetable even if a run overruns; the tail is only never-scraped probes. Morning reports can never be worse than today's because of this expansion.

## 3 · Per-platform list changes

| Platform | File(s) | Now → New | Runtime @measured s/pin | Schedule fit |
|---|---|---|---|---|
| Blinkit | `platforms/blinkit/pincodes.daily.json` (synced to the Mac's imported copy — VPS/KVM scrape path is retired; Mac runner is the sole daily path) | 902 → ~1,490 | Mac wall ≈ 3.75s/pin → ~93 min | 6:30 AM store-floor start (unchanged), done ~8:05 → 10:30 hard rule holds with hours of margin. Ingest ceilings raised: `BLINKIT_MAX_UNRESOLVED` 45→700, `BLINKIT_MAX_WALL_S` 4000→7800 |
| Zepto | `platforms/zepto/pincodes.daily.json` | 693 → ~1,365 | 2.1 → ~48 min | Mac 7:20 launch — fine |
| FK Minutes | `platforms/flipkart-minutes/pincodes.daily.json` | 340 → ~1,320 | 0.27 → ~6 min | KVM1 7:30 trio — trivial |
| Amazon Fresh | core `pincodes.daily.json` UNCHANGED (169, Option-C set) + NEW `pincodes.daily.tail.json` (~1,100) scraped by a post-batch tail sweep | 169 core + ~1,100 tail | tail ~4h chunked | Core stays in the 10:00 chain exactly as today (fresh+now are separate accounts and may run concurrently; each holds its own `.<platform>.lock`). Tail = `tools/cron/amazon_tail_sweep.sh`, cron 10:15 AM, per-city chunks with `.done` markers — a tarpit night loses only unfinished chunks, never the daily report. Daily attempted coverage = core ∪ tail = literal 80% |
| Amazon Now | core `pincodes.daily.json` UNCHANGED (376) + NEW `pincodes.daily.tail.json` (~900), same tail sweep | 376 core + ~900 tail | tail ~2h chunked | Chain unchanged; tail starts 10:15 AM (daytime rule satisfied by construction) |
| BB svc | `platforms/bigbasket/pincodes_jivo.json` | 227 → ~1,340 | per-pin cost unmeasured; at an assumed ≤4s/pin ≈ +1.2h — measure on night 1 | 3:00 AM dedicated cron — hours of headroom either way |
| Instamart | `platforms/instamart/pincodes.json` (anchor-cluster config) | 332 anchors → ~540 (→ ~1,250 represented) | Mac-only | New anchors from existing `tools/pincodes/gather_and_geocode.py` + `cluster_anchors.py` over the target set; file synced to wherever the Mac launchd job reads it (verify path on macpro before flip) |

Coverage math for Instamart uses **represented** pins (guide convention).

## 4 · Guard & predictor pre-adjustments (before tonight's sweep)

1. **Deadline predictor warm-start:** with the Amazon core lists unchanged and blinkit/zepto/bigbasket outside the chain, the ONLY chain platform that grows is flipkart-minutes (+~265s) — append 10 synthetic fkm durations to `tools/cron/durations.jsonl`. `LEAD_MAX=11820` and the 00:30 crontab line stay untouched.
2. **check_layout %-inflation scanner (10:10):** verified a value-format guard (cells ≥2000%), NOT a row-count guard — no change needed for the volume jump.
3. **BigBasket ingest floor (75%-of-last-good):** confirm whether it keys on svc rows; if yes, re-anchor last-good after the first expanded run.
4. **blinkit_batch_guard.sh / morning_report_guard.sh:** audit for hard-coded pin counts or expected-row thresholds; fix any found. (Known stale: `run.sh` inline count comments — update while there.)
5. **Backups:** every replaced list gets `<name>.bak-20260711`; rollback = restore backups + re-run warm-start at old counts.

## 5 · Flip sequence (today, IST)

1. Build `universe_guide24.py` + generator; generate all lists; assert every cell ≥80%.
2. Re-split Blinkit shards; verify shard union == daily.json (fix the known 3-pin drift too).
3. Instamart: geocode + cluster new anchors; stage the anchor file for the Mac job; verify on macpro over ssh.
4. Apply guard/predictor adjustments (§4); Amazon Now launch time unchanged (~7:30 AM), list reordered existing-first.
5. All list files in place before the 00:30 sweep fires.

## 6 · Verification (morning 2026-07-12)

- Recompute the matrix from live lists; **assert min cell ≥80%** (regen script, committed into `/root/jivo-city-coverage-guide/` this time).
- Batch released 10:00 AM; Blinkit in Ecom group ≤10:30; morning_report_guard green.
- Per-pin serviceable/not census extracted from day-1 results → `tools/coverage/` artifact per platform (informational only; pruning is a future owner decision).
- Durations recorded vs predicted; if Amazon Now overran 10:00, note and propose earlier/split handling.
- Regenerate + redeploy jivo-city-coverage-guide.vercel.app from live lists (owner `!` if Vercel push is classifier-blocked).

## 7 · Risks & mitigations

| Risk | Mitigation |
|---|---|
| Predictor under-lead → late batch day 1 | §4.1 warm-start |
| Guards false-positive on 3× jump | §4.2–4.4 pre-adjust |
| Amazon account flags (owner-accepted) | Fresh/Now stay serial via account lock; unchanged pacing per request; census identifies dead pins if owner later chooses to prune |
| Mac down on flip night | Blinkit VPS+KVM fallback shards updated with new lists; Instamart silently absent (existing accepted behavior) |
| Platform rate-defense at 3× volume | Request pacing unchanged (volume ↑, rate flat, duration ↑); rollback = restore `.bak` lists |
| Zepto/Blinkit early-morning store collapse | Launch times untouched; only list sizes change |
