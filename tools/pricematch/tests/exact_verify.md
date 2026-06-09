# W3 — Adversarial gate: EXACT cross-platform price-match signal

**Date:** 2026-06-09 (BAU day) · **Verdict: ✅ PASS** (one non-blocking hardening note)
**Scope verified:** W1 `pricematch_core.exact_price_match` (commit 0b4dfe08) +
W2 sheet rendering in `build_pricematch.py` (commit 505990fa).
**Method:** independent recompute (never trusting the feature's own math), raw-data
hand-checks, cell-level no-regression diff, fault injection. Read-only on prod build code.

The risk this gate guards: a wrong "price match" claim (grouping platforms that are
*close* but NOT at the identical ₹) misleading the ecom head. The decisive proof that
EXACT ≠ the Matrix ±₹5 cluster is below.

---

## PASS/FAIL per check

| # | Check | Result |
|---|-------|--------|
| 1 | W1 `exact_price_match` unit contract (boundary, anti-±5, 3-way, None, sort, purity) | ✅ PASS — 21 new checks, `test_core.py` GREEN (80/80) |
| 2 | W1 core diff is additive-only (no existing fn changed) | ✅ PASS — 0 deletions; `regime_for/competitor_compare/all_comparisons/price_at/summary` byte-identical |
| 3 | **EXACT ≠ ±₹5 cluster** on real data (the critical distinction) | ✅ PASS — 13 close-but-not-equal pairs all → `[]`; JIVO POMACE 1L 379-group excludes Blinkit@380 |
| 4 | Ecom Head board summary correct vs independent recompute | ✅ PASS — 22 SKUs / 23 groups, ZERO symmetric diff |
| 5 | Competitor ⚡ column correct vs independent per-row recompute | ✅ PASS — 94 rows, 8 ⚡ flagged, 0 mismatch, 0 false group, 0 miss |
| 6 | Raw-data hand-check (2 SKUs straight from `result.json`) | ✅ PASS — POMACE 1L=₹379, EXTRA LIGHT 1L=₹499 confirmed amazon+zepto |
| 7 | Labeling: says EXACT/identical, not confused with ±5 or red/green | ✅ PASS — ⚡ glyph + legend + summary + cell comment all state "identical ₹, NOT the ±₹5 cluster" |
| 8 | Highlight fill is NOT red/green | ✅ PASS — fill `D6F0E0` (BRAND sage); RED=`FFC7CE`, GREEN=`C6EFCE` (distinct) |
| 9 | No-regression: Matrix/Violations/Above/Coverage byte-identical | ✅ PASS — cell-level sha256 identical |
| 10 | No-regression: Ecom Head append-only | ✅ PASS — rows 1–41 identical, 19 rows appended (the new section only) |
| 11 | No-regression: competitor sheets differ only by the new column | ✅ PASS — existing data cols 0 mismatch; only +1 exact column, +1 summary row, +1 legend entry (all W2 deliverables) |
| 12 | Tomorrow-safe: fault injection → workbook still builds | ✅ PASS — rc=0, saves, 5 frozen sheets intact, new bits skipped |
| 13 | Tomorrow-safe: byte-stable double-build | ✅ PASS — md5 identical across rebuilds (`5e452ea7…`) |

---

## 1. W1 helper — `exact_price_match` (test_core.py, 21 new checks)

Hand-computed, imported directly (pure fn). All GREEN inside the full suite (80 checks, 0 FAIL):

- `{a:380,b:380,c:385}` → `[{price:380,[a,b]}]`, c excluded.
- **Boundary:** `380` vs `380.4` (Δ0.4<0.5) → SAME group; `380` vs `380.6` (Δ0.6>0.5) → `[]`.
- **CRITICAL anti-±5:** `{a:380,b:384}` → `[]` (within ₹5 but NOT equal — MUST NOT group).
  `{380,384,384}` → groups ONLY the 384 pair, never 380.
- 3-way `{500,500,500}` → one group of 3, platforms sorted.
- None / `"n/s"` / NaN ignored; single platform / empty → `[]`.
- A platform lands in at most one group; groups sorted size-desc then price-asc; input not mutated.

Core diff = pure additions (`git diff` 0 deletions). Existing engine functions unchanged.

## 3. EXACT ≠ ±₹5 cluster (the headline proof)

Recomputed every cross-platform pair within ₹5 but not equal — **13 such pairs today, all
correctly return `[]` from `exact_price_match`.** Side-by-side on the same SKU:

```
JIVO POMACE 1L
  Matrix ±5 cluster: [FKM, Zepto, Amazon, Amazon-Fresh, Amazon-Now @379  +  Blinkit @380]   (6 platforms, one band)
  EXACT group:       [Amazon, Amazon-Fresh, Amazon-Now, FKM, Zepto @379]  — Blinkit@380 EXCLUDED
CANOLA 1L
  Matrix ±5 cluster: [FKM@258, Amazon/Fresh/Now@259, Blinkit@260]   (5 platforms)
  EXACT group:       [Amazon, Amazon-Fresh, Amazon-Now @259]        — FKM@258 & Blinkit@260 EXCLUDED
GROUNDNUT 5L
  Matrix ±5 cluster: [Amazon-Fresh, Amazon-Now @1074, Amazon@1079]
  EXACT group:       [Amazon-Fresh, Amazon-Now @1074]               — Amazon@1079 EXCLUDED
```

The two signals demonstrably diverge wherever prices are close-but-not-equal. ✅

## 4. Ecom Head board summary — independent recompute

Basis (W2's choice, task-sanctioned): `by_key` + `live_modal` over CANONICAL platforms —
same source as the Matrix. Independently rebuilt `{platform: live_modal}` per SKU and grouped
with a fresh bucket-by-whole-rupee implementation (NOT calling `exact_price_match`):

```
independent recompute = 22 SKUs, 23 groups
engine _board_exact_matches = 22 SKUs, 23 groups
symmetric diff = {}   (IDENTICAL)
```

Rendered Ecom Head matches: KPI "**22 SKUs matching exactly across platforms today**",
top-12 table + "… and 11 more". Top rows hand-verified, e.g.
`JIVO POMACE 1L ⚡ Amazon = Amazon Fresh = Amazon Now = Flipkart Minutes = Zepto @379`
(Blinkit@380 correctly absent).

## 5. Competitor ⚡ column — independent recompute (per-pincode basis)

For every rendered data row I rebuilt `{platform: ₹}` from the prices shown **on that row**
(ref + each competitor at that pincode), grouped independently, and compared to the ⚡ cell:

```
94 rows checked · 8 ⚡-flagged · 0 mismatch · 0 false grouping · 0 miss
```

Every "—" row genuinely has no 2+ platforms at the identical ₹; every ⚡ row's named
platforms are exactly those at the identical whole rupee. Pending (560005) rows show
"pending". Samples: `Amazon Now = Zepto @ ₹379`, `Flipkart Minutes = Zepto @ ₹960`.

## 6. Raw-data hand-check (full independence on price extraction)

Straight from `platforms/*/result.json` (not via the engine):
- JIVO POMACE 1L: amazon `B0821DNF2W` sale=379; zepto @110095 sale=379 → grouped @379 ✓
- EXTRA LIGHT 1L: amazon `B09HZY97FR` sale=499; zepto @110095 sale=499 → grouped @499 ✓

## 7–8. Labeling & color

- ⚡ cell fill = `D6F0E0` (BRAND sage) on competitor sheets AND Ecom Head — **not** RED
  (`FFC7CE`, undercut) and **not** GREEN (`C6EFCE`, above). Distinct, and carries the ⚡
  glyph in a dedicated "Price match (same ₹)" column / "₹ price" table.
- Legend entry, per-sheet summary line, cell comment, and Ecom Head subtitle each state
  EXACT / identical ₹ and explicitly contrast it with the Matrix "Price-Match active (±₹5)"
  band. No naming collision.

## 9–11. No-regression (cell-level, same data, pre-change build = commit 0b4dfe08)

```
Matrix              IDENTICAL  (sha 32246ea19059)
Violations          IDENTICAL  (sha cfd068f4d1ea)
Above reference     IDENTICAL  (sha f424c570b8be)
Coverage & pending  IDENTICAL  (sha 323ef6adbb93)
Ecom Head           rows 1..41 identical; +19 appended (exact section only)
Amazon Now PM Check   existing data cols 1..7  → 0 mismatch (row-shifted by the summary line)
Amazon Core PM Check  existing data cols 1..8  → 0 mismatch
```

Competitor sheets gain exactly: the exact column (col 8 Now / col 9 Core), one summary row
(row 4), one legend entry (⚡ sage definition — explains max_column 10→12 via the span-2
legend layout). All three are explicit W2 deliverables; no existing competitor data moved.

## 12. Fail-safe (tomorrow-safe)

Monkeypatched `core.exact_price_match` to raise on every call, rebuilt:

```
build rc = 0  · workbook saved · byte-stabilized · pm-history captured 904 rows
sheets present: Ecom Head, Matrix, Violations, Above reference, Coverage & pending
Ecom Head exact section: ABSENT (skipped)   ← only the new section dropped
```

The owner's hard requirement — **the 12:00 batch cannot break** — holds: the build succeeds,
saves, and ships all compliance sheets even when the exact engine explodes.

### ⚠️ Non-blocking hardening note (NOT a gate failure)
When `exact_price_match` raises, the Ecom Head correctly skips **only its appended section**,
but both competitor PM Check sheets are dropped **in full** (the per-row exact call at
`_render_compete_sheet` ~line 1312 has no inner guard, so the exception unwinds the whole
sheet and `main()`'s fail-safe removes both). The frozen compliance sheets are unaffected and
the workbook still ships, so this does not break the batch. `exact_price_match` is pure and
fully unit-tested (won't raise on real/None/NaN/str data), so the realistic blast radius is
nil. **Recommendation (future):** wrap the per-row exact call in a try/except that degrades the
cell to "—" so a hypothetical future bug skips only the column, matching the Ecom Head
granularity. Filed for the lead; does not hold the push.

## 13. Byte-stability
Double-build on the same data → md5 identical (`5e452ea7dff8e681cbdaa6813b99c44e`). Idempotent.

---

### Reproduce
```
python3 tools/pricematch/tests/test_core.py        # W1: 80 checks, 0 FAIL
python3 tools/pricematch/pricematch_core.py --date 2026-06-09 --exact-demo
# no-regression: build 0b4dfe08:build_pricematch.py vs HEAD on same date, cell-sha per sheet
```

**Gate verdict: ✅ PASS — lead may push + deliver.** Correctness proven against independent
recompute and raw data; EXACT signal is provably distinct from the ±₹5 cluster; zero false
groupings / zero misses; existing sheets byte-identical; the batch is fault-tolerant and
byte-stable. One non-blocking hardening note logged for the competitor-sheet fail-safe
granularity.
