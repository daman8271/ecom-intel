# W3 — competitor price-match adversarial gate · VERDICT: **PASS**

Date: 2026-06-09 (regime BAU · day 9 Tue). Gate owner: W3. Verifies W1 (engine + first-week
regime), W2 (the 2 new PM Check sheets), and the tomorrow-safety of the pincode edit.
All checks independently recomputed from raw `platforms/*/result.json` — not trusting the engine's
own numbers.

## Summary
| Check | Result |
|---|---|
| Job A — add 560005 to 4 sweep pincodes.json | **PASS** |
| Check 1 — regime first-week rule | **PASS** (0 mismatches over a full month + cross-month) |
| Check 2 — competitor color polarity | **PASS** (8/8 cells vs independent recompute; 0 polarity failures) |
| Check 3 — rebuilt xlsx: new sheets + existing byte-identical | **PASS** (Check 3/4 harness: 20/20) |
| Check 4 — pincodes parse + new-sheet build fail-safe | **PASS** |
| Scope-add — fix stale regime asserts in test_core.py + first-week positive | **PASS** (suite GREEN 59/0) |

Reproduce: `python3 tests/test_core.py` (regime + engine contract) and
`python3 tests/w3_check34.py` (xlsx sheets + byte-identity + fail-safe). Check 1/2 recompute
snippets are inline below.

---

## Job A — pincode 560005 added to the 4 quick-comm sweeps
Owner reference pincodes: 110095 (Delhi, already swept) + 560005 (Bengaluru, was NOT a standalone
scrape entry — only listed inside the 560001 coverage cluster). Added a standalone entry to each:

| file | before | after | Δ |
|---|---|---|---|
| platforms/amazon-now/pincodes.json | 332 | **333** | +1 |
| platforms/blinkit/pincodes.json | 332 | **333** | +1 |
| platforms/zepto/pincodes.json | 332 | **333** | +1 |
| platforms/flipkart-minutes/pincodes.json | 345 | **346** | +1 |

Total: +52 insertions, **0 deletions** (pure additions; no existing entry touched). New entry
(identical in all 4, key order matches siblings exactly):
```json
{ "city": "Bengaluru", "tier": 1, "pincode": "560005", "locality": "Pulikeshinagar",
  "landmark": "Pulikeshinagar, Bengaluru, 560005, India", "lat": 12.9986, "lon": 77.6205,
  "represents": 1, "pincodes": ["560005"] }
```
- All 4 files `json.load` clean; new entry's keys == a sibling singleton (560019)'s keys.
- Scrapers tag each row with `rec.pincode` (verified blinkit scrape.js:211 `pincode: rec.pincode`),
  so this entry produces `pincode:"560005"` rows in result.json on the next sweep → the compete
  engine's `price_at(..., "560005")` will then resolve. Until then it is correctly NOT_SERVICEABLE.
- Adding 1 entry to ~332 is negligible runtime → tomorrow's 08:32→12:00 sweep stays full-quality.

## Check 1 — regime first-week rule (independent recompute)
Rule (owner 2026-06-09): SVD on **days 1–7 of any month (any weekday) OR Fri/Sat/Sun**; else BAU;
exact-date override (incl. ART) wins outright. Compared `regime_for` against an independent
implementation over all of June 2026 + cross-month dates: **0 mismatches**.

| date | dow | regime_for | expect |
|---|---|---|---|
| 2026-06-01..07 | any | SVD | SVD (first week) |
| 2026-06-03 (+ART override) | Wed | **ART** | ART (override beats first-week) |
| 2026-06-08 | Mon | BAU | BAU (day 8, weekday) |
| 2026-06-09 (today) | Tue | **BAU** | BAU |
| 2026-06-12/13/14 | Fri/Sat/Sun | SVD | SVD (weekday rule) |
| 2026-07-02 | Thu | SVD | SVD (first week, other month) |
| 2026-07-09 | Thu | BAU | BAU |
→ The agreed-price sheets' regime label (BAU, today) is correct.

## Check 2 — competitor color polarity (SACRED · independent recompute @110095)
Recomputed each competitor's price vs the Amazon-Now reference straight from raw result.json
(modal of in-stock priced rows at the pincode), classified independently, compared to the engine.
Polarity asserted: **RED ⟺ diff < −₹1 (competitor undercuts our Amazon); GREEN ⟺ diff > +₹1;
MATCH within ±₹1.** `diff = competitor − ref`.

8/8 cells agree (0 mismatch). Sample (engine vs my recompute, all OK):

| SKU | competitor | ref (a-now) | competitor | diff | status / color |
|---|---|---|---|---|---|
| JIVO POMACE 1L | blinkit | 379 | 380 | +1.0 | MATCH / none |
| JIVO POMACE 1L | zepto | 379 | 379 | 0.0 | MATCH / none |
| JIVO POMACE 5L | zepto | 1950 | 2128 | +178 | ABOVE / GREEN |
| JIVO POMACE 5L | flipkart-minutes | 1950 | 2049 | +99 | ABOVE / GREEN |
| EXTRA LIGHT 2L | blinkit | 1135 | 1304 | +169 | ABOVE / GREEN |
| EXTRA LIGHT 2L | flipkart-minutes | 1135 | 1903 | +768 | ABOVE / GREEN |
| CANOLA 1L | blinkit | 259 | 260 | +1.0 | MATCH / none |
| JIVO POMACE 5L | blinkit | 1950 | 1950 | 0.0 | MATCH / none |

- Polarity invariant held on **every** priced engine cell (0 failures). Today @110095:
  **0 RED (undercut), 7 GREEN, 4 MATCH** for the Amazon-Now reference — competitors are at-or-above
  Amazon Now today.
- RED branch proven on real data by flipping the reference: blinkit ref 1304 vs amazon-now 1135 →
  diff −169 → **BELOW = RED = undercut** ✔ (the engine's `diff < -TOLERANCE → BELOW` at
  pricematch_core.py:548 fires correctly).
- National platforms (bigbasket/flipkart/amazon-core): one price applied to BOTH pincodes
  (`national=True`); bigbasket national price identical at 110095 and 560005 for all 9 priced SKUs.
- **560005**: amazon-now ref None (no data yet) → per-pincode competitors (blinkit/zepto/fkm) all
  **NOT_SERVICEABLE**; national bigbasket carries its national price → NO_REF (ref absent). Correct.
- ****: every cell NOT_SERVICEABLE (blank) everywhere — 42 cells. Correct (no feed).

Note on "opposite polarity": the new sheets are RED=below numerically the SAME as the agreed
sheets (both RED=below), but the **subject flips** — agreed sheets flag *our* listing below its own
agreed MAP, the PM sheets flag a *competitor* below *our* Amazon. The legend states the competitor
rule loudly, which is what the owner asked for.

## Check 3 — rebuilt workbook (Jivo-Price-Match-2026-06-09.xlsx)
Built with the working-tree (W2) build script; inspected with openpyxl (harness `tests/w3_check34.py`):
- Both new sheets present (`Amazon Now PM Check`, `Amazon Core PM Check`), **appended after** the 5
  existing sheets.
- Legend (both sheets) states loudly: *"RED = cheaper than Amazon Now/Core (they're UNDERCUTTING
  us)"* + *"GREEN = dearer … (above our price)"* + *"no fill = MATCH (within ±₹1)"*.
-  column present but blank; **560005 block shown as "pending"**.
- Sheet 1: **BigBasket tagged "national"**. Sheet 2: **buybox seller surfaced**.
- **EXISTING sheets BYTE-IDENTICAL**: Ecom Head / Matrix / Violations (and all 5) cell-for-cell
  identical (values + fills + merged ranges) vs a workbook built from the git-HEAD (pre-W2) build
  script on the same data. (W2 independently confirmed identical worksheet XML on a frozen snapshot;
  source diff +353/−0.)
- Workbook RED-cell counts: Amazon Now PM Check = **0** (consistent with Check 2); Amazon Core PM
  Check = **28** (quick-comm undercuts Amazon Core's national buybox at 110095 — expected).

## Check 4 — tomorrow-safe
- The 4 edited pincodes.json all `json.load` clean and the new 560005 entry is well-formed
  (key-for-key == siblings) → a malformed entry cannot break tomorrow's scrape.
- **Fail-safe proven**: monkeypatched `build_compete_sheets` to raise; the workbook **still builds
  and saves**, the 2 new sheets are **omitted** (half-built sheets removed), **all existing sheets
  remain**, and the skip is **logged non-fatally** ("competitor PM sheets SKIPPED (non-fatal)"). A
  bug in the new sheets therefore cannot crash the batch's workbook build.

---

### Verdict: **PASS** — lead may push; the sweep picks up 560005 tomorrow.
Owned edits: `platforms/{amazon-now,blinkit,zepto,flipkart-minutes}/pincodes.json`,
`tools/pricematch/tests/test_core.py` (scope-add, authorized), this report, and the harness
`tools/pricematch/tests/w3_check34.py`. No scraping, no push.
