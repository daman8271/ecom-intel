# amazon-fresh daily pin set — Option C (2026-07-07)

`pincodes.daily.json` = **169 pins / 24 cities** (was 973). Owner-approved
"Option C" cut, effective from the 2026-07-08 night sweep.

## Why

Under Amazon's tarpit (since Jul 4) the 973-pin sweep costs ~24.4s per
serviceable pin (~6.8h) and delivered **0 reports into the 10:00 batch in 4
nights**. 865/973 pins return JIVO rows but collapse to ~175 distinct
(SKU→price) signatures on a full night — most pins are redundant observations
of the same shelf. 169 pins keep every observed price zone at ~1/6 the cost
(tarpit worst ≈ 70m, normal ≈ 10–20m).

## Selection rule (evidence-based, from data/amazon-fresh/history.csv)

Window = the 10 most recent runs (2026-06-25-1310 .. 2026-07-05-1604).

1. **HARD RULE — price-point coverage:** per city, for each of its top-3
   coverage runs, every distinct `(canonical_sku, price)` pair observed in that
   run is present in ≥1 selected pin's rows for that run (greedy set cover).
   A price zone is exactly a group of pins showing a distinct price point, so
   every observed intra-city price zone keeps a representative. (Raw signature
   grouping was rejected: availability noise fragments it — 275 pins.)
2. **Rank / fill:** remaining city quota filled by (a) JIVO-row consistency =
   number of window runs with rows, desc; (b) serviceable in
   `result.last-good.json`; (c) pincode asc (deterministic).
3. **Dead cities keep 2 serviceable pins as standing gap evidence** (Nagpur,
   Coimbatore: 0 JIVO rows in the window). Chandigarh turned out NOT dead —
   1 pin returned rows on 2026-06-30 and is kept.

Quotas: Mumbai 30, Delhi 30, Pune 15, Chennai 12, Kolkata 12, Noida 12,
Bengaluru 12, Hyderabad 6, all others 2. The hard rule may expand a city past
quota (Gurugram 8, Jaipur 4 — real intra-city variance found in the data).

## Per-city result (pins kept / set-cover core / price points covered, top-3 runs)

| City | Kept | Cover core | Price points |
|---|---|---|---|
| Delhi | 30 | 14 | 126 |
| Mumbai | 30 | 9 | 74 |
| Pune | 15 | 6 | 60 |
| Bengaluru | 12 | 8 | 58 |
| Chennai | 12 | 5 | 59 |
| Kolkata | 12 | 4 | 59 |
| Noida | 12 | 6 | 72 |
| Gurugram | 8 | 8 | 71 |
| Hyderabad | 6 | 4 | 51 |
| Jaipur | 4 | 4 | 43 |
| Ahmedabad, Bhubaneswar, Chandigarh, Coimbatore*, Indore, Kochi, Lucknow, Mysuru, Nagpur*, Surat, Thiruvananthapuram, Vadodara, Vijayawada, Visakhapatnam | 2 each | — | — |

\* dead city, gap evidence.

## Guard alignment

- `baselines/amazon-fresh.json` reseeded (house `.NEW` pattern: 6 identical
  synthetic samples) with the **mean of the last-10-run simulation on this
  set**: rows 1299, unique_skus 32, pincodes_with_jivo 109. All 10 historical
  night-patterns verdict OK against these floors (SUSPECT <65, BROKEN <28
  with-jivo); seeding from the single full run would have false-SUSPECTed 5
  of 10 patterns (94 < 95) — and SUSPECT runs never update the rolling
  baseline.
- Clobber check (`tools/coverage/amazon_clobber_check.py`): config overlap
  with amazon-now's 132 pins = 19, Jaccard 0.067 (trip >0.85). Even a full
  serviceable collapse cannot push runtime Jaccard past 19/132 ≈ 0.14.
- `freshness_guard.py` will show a cosmetic, non-gating AMBER on row-drop vs
  the trailing median for a few days until the window refills with 169-pin
  runs. Expected; ignore.

## Reversibility

- Full 973 set preserved at `pincodes.daily.FULL-973.json`; to roll back:
  copy it over `pincodes.daily.json` AND restore
  `baselines/amazon-fresh.json.pre-optc-973.bak` over
  `baselines/amazon-fresh.json` (they must move together), and revert the
  amazon-fresh cap in `run.sh` to 10800.
- The separately staged half-cut (`pincodes.daily.NEW.json`, 442 pins +
  `baselines/amazon-fresh.json.NEW`) is another session's work — untouched.

Builder: `/root/optc_build.py` (deterministic; reads history.csv +
result.last-good.json only).
