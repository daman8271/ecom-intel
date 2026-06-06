# VERIFY — violations-engine adversarial gate report

**Date:** 2026-06-06 (SVD day) · **Verifier:** VERIFY session (owns `tools/pricematch/tests/`)
**Verdict: PASS** — 160 harness checks + 33 wiring checks + full SIM e2e, **0 FAIL** on the
final committed state (`pm-core` c0f9309d · `pm-sheets` 78b0a03b · `pm-master` 754facab).

Gates this PASS opens: today's files to the owner, cron wiring staying installed, GitHub push.

## How verified
Four runnable harnesses (bare python3 / bash, stdlib + openpyxl only), all committed under
`tools/pricematch/tests/`:

| harness | what | result |
|---|---|---|
| `test_core.py` | Phase 1 engine golden tests in a sandbox fake-repo with hand-computed fixtures | **55/55 PASS** |
| `check_sheets.py` | Phase 2 color direction cell-by-cell, all 8 platforms + master Matrix + Ecom Head, vs engine `--json` | **76/76 PASS** |
| `check_master_deep.py` | Phase 2 deep: top-10, scoreboard arithmetic, Violations/Above/Coverage sheets | **18/18 PASS** |
| `check_safety.py` | Phase 2b idempotency, originals-untouched, builder byte-stability, crash-safety | **11/11 PASS** |
| `check_wiring.sh` | Phase 3 run.sh hook, run_all block (defer/plain/crash/SIM/CHAIN_SKIPPED), send_batch order | **33/33 PASS** |

## Phase 1 — ENGINE golden tests (hand-computed, independent of engine math)

| item | result | evidence |
|---|---|---|
| Tolerance edges at exactly ±₹1 (ref 140: live 139→MATCH, 138→BELOW, 141→MATCH, 142→ABOVE, 140→MATCH; diff values exact) | PASS | 20 checks, fixture P1–P5 |
| OOS (rows exist, none in stock) | PASS | status OOS, no verdict |
| PENDING_REVIEW exclusion (review-list candidate; counted, never priced) | PASS | fixture P7 via `sku_map["review"]` — the engine's real mechanism |
| Low-confidence mapping NEVER priced (hard safety property) | PASS | conf="review" mapping → no BELOW/ABOVE/MATCH leak |
| retired exclusion (entirely absent from records) | PASS | RETIRED FIX 1L absent |
| NOT_LISTED (master SKU, no mapping on platform) | PASS | |
| **Regime exhaustive week** 2026-06-01 Mon BAU → 06-08 Mon BAU, Fri/Sat/Sun SVD | PASS | 8 dates incl. 06-06 Sat→SVD, 06-07 Sun→SVD |
| Override flips a date to ART **and flows into ref_price** (130) + verdict | PASS | 06-03 override: regime ART, ref 130, 140 vs 130 → ABOVE |
| Bad regime.json (garbage) → weekday defaults, no crash | PASS | *initially FAIL on the 16:43 engine — crashed with JSONDecodeError; ENGINE fixed at 16:44, re-verified* |
| Missing regime.json → weekday defaults, no crash | PASS | same fix |
| stores_below: modal 150 (ABOVE) but one store 130@560001 — must surface | PASS | exactly that store, price carried, healthy stores excluded |
| **Live-join**: map snapshot sale_modal=999, result.json says 138 ⇒ records carry 138 | PASS | live_modal=138, status BELOW |
| NO_REF (svd null on SVD day) | PASS | |
| CLI `--json` / `--json <platform>`: exit 0, valid JSON, fixture records present | PASS | |
| Engine reads paths relative to its location (sandboxable, no hardcoded /opt) | PASS | sandbox produced fixture SKUs only |

**Real-data spot-check (independent recompute from raw `allRows`):** blinkit CANOLA 5L
(65 rows: modal 1193 vs SVD ref 1249 → diff −56, 55 stores below) and EXTRA LIGHT 2L
(112 rows: 1135 vs 1189 → −54, 94 stores) — engine record exactly equals hand math,
including stores_below counts.

## Phase 2 — SHEETS verification (real generated files)

### COLOR DIRECTION (the one unforgivable bug) — ZERO mismatches
- **Per-platform "Price Match" sheets, all 8 platforms, 291 data rows**: for each row the
  truth was recomputed independently from engine numbers (`live < ref−1 ⇒ red`,
  `live > ref+1 ⇒ green`) and compared with the actual fill of the diff, live AND status
  cells (openpyxl). Red=F4CCCC only on BELOW, green=D9EAD3 only on ABOVE, MATCH/OOS/PENDING
  unfilled. Also asserted: a BELOW/ABOVE row *missing* its fill fails. 0 mismatches.
- **Master Matrix, 171 priced cells** across all 8 platform columns: fill ⟺ status ⟺
  recomputed truth, value == engine live_modal, hyperlink present on every priced cell,
  NOT_LISTED rendered "—" uncolored, OOS rendered "OOS" uncolored. 0 mismatches.

### Other Phase 2 items
| item | result | evidence |
|---|---|---|
| Sheet numbers/status == engine records (ref, live, diff per row) | PASS | all 8 platforms |
| Section order BELOW (worst diff first) → ABOVE → MATCH → OOS → PENDING; NOT_LISTED omitted | PASS | |
| stores-below count cell == len(engine stores_below) | PASS | |
| Footer summary counts == engine | PASS | |
| Regime badge "SVD day" on every sheet + master | PASS | |
| Ecom Head is the FIRST sheet | PASS | |
| Ecom Head KPIs == summary() exactly (113/8/51/85/35/113/7/₹5,804) | PASS | |
| Top-10 violations sorted by diff, equals engine's global worst BELOW, ref/live exact | PASS | −360 … −169 |
| Platform scoreboard: per-row mapped/violations/biggest-offender == engine; violations sum to 85; mapped sums to 291 | PASS | |
| Violations sheet: 1977 rows == engine Σ stores_below (incl. cheap-store-under-healthy-modal — the every-store check), sorted by loss desc, spot rows (70) match engine entries + loss math | PASS | |
| Above-reference sheet: 35 rows == engine ABOVE; Diff % cells carry number formats | PASS | |
| Coverage & pending: NOT_LISTED 613, PENDING 7, OOS 113 on sheet | PASS | |
| Matrix regime column highlight: "SVD ◀ today", only today's column marked | PASS | |
| Matrix covers all 113 engine SKUs | PASS | |
| Appender idempotency: 3× re-run on a workbook ⇒ exactly one "Price Match" sheet, stable count | PASS | temp copy of bigbasket workbook |
| Existing sheets untouched: content-hash (values+fills+fonts+merges) of every original sheet pre/post append | PASS | zero drift |
| Master builder byte-stable across two builds | PASS | *initially FAIL: docProps/core.xml timestamps; SHEETS-B pinned doc props + zip mtimes to --date (754facab), re-verified byte-identical* |

### Adversarial finding (fixed before ship) — stub-fallback color risk
The original appender (eebc144d) fell back to an embedded `_StubCore` when the real engine
crashed. I diffed stub vs engine on today's live data: **29 divergences, including color
flips** (flipkart EXTRA LIGHT 1L engine=OOS / stub=BELOW→red; GROUNDNUT 5L + MUSTARD 5L
engine=OOS / stub=ABOVE→green; MUSTARD 1L diff 46 vs 8). A mid-run engine failure would
have silently shipped stub colors. **LEAD ruling implemented (78b0a03b): production crash
path = warn + exit 0 + workbook untouched; stub is dev-only behind PM_DEV_STUB=1.**
Re-verified: engine-crash run leaves the workbook byte-identical (check_safety +
check_wiring 1c). Today's shipped sheets were engine-built (they match engine records
exactly, including all the cases where the stub diverged).

## Phase 3 — wiring safety

| item | result | evidence |
|---|---|---|
| run.sh hook, tool ABSENT ⇒ byte-identical behavior | PASS | verbatim hook lines in sandbox: exit 0, workbook hash unchanged, output/ mirror identical |
| run.sh hook, tool crashes (rc=7) ⇒ run continues, workbook intact | PASS | `\|\| true` + atomic temp-copy confirmed |
| run.sh hook, REAL appender + engine runtime error (corrupt sku_map/master) ⇒ continues, **no stub sheet written** | PASS | byte-identical workbook |
| run_all pm block, DEFER: spool `output/.batch/<sweep>/price-match.json` written post-loop, schema v1 complete (platform/verdict/summary/xlsx/caption/ts), no immediate send | PASS | block extracted verbatim, stub builder |
| run_all pm block, PLAIN (no defer, no creds): immediate-send path, graceful "no Telegram creds", no spool side-effects | PASS | |
| Builder silent/crashing ⇒ honest log, no bogus spool, block exits 0 (sweep survives) | PASS | |
| SIM gate: SIM_MODE=1 ⇒ pm block fully skipped, zero side-effects | PASS | |
| CHAIN_SKIPPED=1 ⇒ pm block skipped (won't read result.json mid-rewrite by another chain) | PASS | |
| send_batch: "price-match" appended to CANONICAL, sent LAST | PASS | live order test: flipkart-minutes → blinkit → price-match |
| Sweep-chain lock + barrier untouched | PASS | git diff 5e4cf496..HEAD on run.sh/run_all.sh/send_batch.py is **purely additive** (0 deletions); pm block sits after lock release (l.101) and before the barrier (l.211); full SIM e2e re-run green (see below) |
| bash -n run.sh + run_all.sh, py_compile all 4 new py files | PASS | |
| regime.json on disk == frozen contract defaults, overrides=[] | PASS | |
| Builder sidecar summary: 6-line markdown (regime, 85 violations, top-3 offenders, ₹5,804 exposure), caption "Jivo Price Match · 2026-06-06 · SVD day" | PASS | KPIs equal independently verified numbers |

### Full SIM e2e (tools/cron/tests/run_sim.sh — existing W4 harness, unmodified)
**11 pass / 0 fail** with the price-match code installed (run 2026-06-06 17:01–17:05,
sweep `2026-06-06-1704`, fake platforms alpha/beta/gamma, dead TG creds):
serial chain (no overlap) · barrier held, batch released at deadline ±0s · no early send ·
dead-creds failure preserved all spool files · durations ledger +3 exactly ·
dead-creds re-run no-op · TG_DRY_RUN resume delivered + retired spool · post-retirement
re-run clean no-op. The pm block correctly did NOT run (SIM gate) — only alpha/beta/gamma
entries in the sweep spool, no price-match.json. **The sweep machinery is regression-free.**

## Build-time catches (found by this gate, fixed by builders before ship)
1. **ENGINE 16:43**: bad/missing regime.json crashed `regime_for` (contract: degrade to
   weekday defaults). Fixed 16:44.
2. **SHEETS-A stub fallback**: 29 live divergences incl. color flips on engine crash.
   Removed from production path (78b0a03b).
3. **SHEETS-B byte-stability**: docProps timestamps broke determinism. Pinned to --date
   (754facab).

## Re-run the gate
```bash
python3 tools/pricematch/tests/test_core.py          # engine goldens (sandboxed)
python3 tools/pricematch/tests/check_sheets.py       # color direction, all sheets
python3 tools/pricematch/tests/check_master_deep.py  # Ecom Head / Violations deep
python3 tools/pricematch/tests/check_safety.py       # idempotency / crash safety
bash    tools/pricematch/tests/check_wiring.sh       # run.sh + run_all + send_batch
```
All sandboxed: no real workbook is modified, no Telegram is sent (dead creds).
