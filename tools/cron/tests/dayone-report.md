# Day-one verification report — deadline system + post-deploy ID gates

**Auditor:** W3 (read-only on production) · **Date:** 2026-06-06 · **Scope:** first two real
deadline sweeps (`2026-06-06-1000`, `2026-06-06-1500`) + W4's post-deploy identity-field gates.

---

## Part A — first-runs audit: **PASS** (deadline system worked end-to-end, 3 findings)

### A1. Batch delivery — VERIFIED ✅

| Sweep | Cron fire | Chain start | Chain done | Barrier held | Batch window | Result |
|---|---|---|---|---|---|---|
| 2026-06-06-1000 | 06:30:01 (lead=11891s) | 06:41:49 | 09:06:35 | 3205s | **10:00:00–10:00:16** | header + 7 reports + footer, all `ok:true` (msg ids 1020–1035) |
| 2026-06-06-1500 | 11:30:01 (lead=12050s) | 11:39:10 | 14:02:36 | 3444s | **15:00:00–15:00:16** | header + 7 reports + footer, all `ok:true` (msg ids 1050–1066) |

- Both batches **landed exactly at the slot time** — `woke at deadline — releasing batch` at
  10:00:00 / 15:00:00; canonical platform order preserved (flipkart-minutes → flipkart →
  zepto → bigbasket → amazon-fresh → amazon-now → blinkit).
- Spools retired: `output/.batch/sent-2026-06-06-1000/` and `sent-2026-06-06-1500/`, each
  with `.header.sent`, `.footer.sent`, 7 × `<p>.json.sent`.
- **amazon held-marker present in both retired dirs** (`amazon.json`, never renamed `.sent`):
  `{"platform":"amazon","verdict":"SUSPECT","held":true,"reasons":"per_litre_sanity: …"}`
  (ts 1780710177 / 1780728099).
- **Footer listed amazon as held**: `send_batch.py:185-186` computes `held_ps=[amazon]` from
  that marker; `send_batch.py:262-264` makes the footer
  `"Held back (review verdict, owner already alerted): amazon [SUSPECT]"`; the footer send
  returned `ok:true` (msg 1035 / 1066) and `.footer.sent` exists. (telegram.log truncates the
  API body at 200 chars, so the text is verified by marker + code path + successful send,
  and the footer only sends at all when `foot` is non-empty — here solely the held line.)
- Per-run owner alerts for the held amazon runs fired immediately at scrape time
  (07:12:56 and 12:11:38, msg 1016 / 1044) — verdict-gating unchanged.
- Footer reported `0 missing`, no late note (chain finished early both sweeps).

### A2. Durations ledger + tomorrow's prediction — VERIFIED ✅

- `tools/cron/durations.jsonl`: **exactly +16 records** today (8 per sweep, tagged with the
  correct `sweep` id). Every `secs` matches the cron.log inter-platform gap to ±1s, e.g.
  1000-sweep: fkm 71, flipkart 468, zepto 535, bigbasket 180, amazon 616, fresh 974,
  now 1629, blinkit 4213 — all reconciled against the 06:41:49→09:06:35 timeline.
- `LEAD_MAX=12600 python3 tools/cron/predict_lead.py` after today's data:
  `total=12059` (fkm 222, flipkart 693, zepto 917, bigbasket 336, amazon 885, fresh 1345,
  now 2096, blinkit 4965). **Sane**: under the 12600 cap, p90 sits correctly just above
  today's actuals (~2h25m chain → 10:00 sweep would start ~06:39; for the owner's new 12:00
  slot, fire 08:30 → start ~08:39).
- bigbasket's p90 grew 186→336 because its recorded duration now includes the guardian's two
  in-loop heal re-runs (see A3.1) — self-learning behaving as designed, but it bakes the
  wasted heals into the lead until A3.1 is fixed.

### A3. Anomalies (beyond the known amazon SUSPECT) — 4 findings

1. **bigbasket: guardian-BROKEN but SHIPPED, both sweeps** *(the one real gap)*
   - review.py: `OK (rows=23 skus=23 base=23)` → run.sh spooled the report.
   - guardian deep-check: `BROKEN — [class 4] priced_row_floor: 10 in-stock priced rows
     (floor 15)` + `shared_price_dup` (₹50/₹50 wheatgrass-juice variants) → QUARANTINED,
     marker `logs/.guardian-broken-bigbasket` set, **2 self-heal re-runs per sweep** (guardian.log
     01:30–01:32Z and 06:29–06:31Z), still BROKEN, owner TG-alerted. Heal machinery itself
     worked exactly as documented.
   - **But the spooled report was never pulled** — `bigbasket.json.sent` went out in BOTH
     batches. Telegram gating keys off review.py's verdict only; a guardian BROKEN after
     spooling has no spool-pull hook. Combined-verdict ≠ delivery-verdict.
   - Assessment: the floor (15) looks **miscalibrated for member-mode bigbasket**, whose
     stable profile since the 2026-06-04 member fix is 23 rows / 10 in-stock — identical
     across the last 5 runs, prices sane, and the ₹50/₹50 dup is genuine (flavour variants of
     the same juice priced identically). So today's shipped data is almost certainly fine —
     but the architecture gap (guardian BROKEN cannot stop an already-spooled report) and the
     every-sweep waste (~2 min of heal re-runs + a guaranteed owner alert) are real.
     → handed to W1 (guardian floor + spool-pull); W3 will adversarially re-verify when it lands.
2. **Guardian SUSPECTs that shipped (by design, FYI):** flipkart (`shared_price_dup`: 2
   (sale,mrp) pairs across distinct pids), amazon-fresh + amazon-now (`identical price across
   7–10 cities w/o store_id` contamination heuristic — expected for account-global Amazon
   pricing surfaces, reads as a false-positive pattern worth a whitelist).
3. **bigbasket `member_email` now scrapes empty** (was `dp605702@gmail.com` through
   2026-06-05-1601; `member_id` 107517719 still present, `session_expired:false`). Possible
   early signal of session/profile decay — watch; the `BB_SESSION_EXPIRED` fail-safe is intact.
4. **Leftover un-retired SIM spool** `output/.batch/2026-06-06-0248/` (alpha/beta/gamma test
   batch whose footer 401'd on a dummy token). Test debris; safe to delete. The other test
   spool (`sent-2026-06-06-0241`) retired normally under dry-run.

Everything else clean: all 8 platforms completed both sweeps with no scrape errors, no heal
attempts other than bigbasket's, blinkit/zepto/fkm guardian-healthy in both, vault rebuilt +
pushed after each sweep, immediate-fallback path never needed.

---

## Part B — post-deploy ID gates (W4) on today's freshest result.json

Sources: blinkit `result.json` 14:02 (1500 sweep), flipkart-minutes 11:40, bigbasket 12:01
(post-heal re-run of the 1500 sweep; same 23-row payload).

### B1. blinkit `prid` — **SAFE-TO-FOLD** ✅
- 722/722 rows (100%) carry `prid`; **0 format violations** (all 6-digit, within 5–7 rule).
- **9 distinct prids ↔ 9 distinct canonicals — 0 unstable** (same canonical → same prid
  across every pincode; ~80 pincodes per SKU).
- Cross-field: `listing_url` embeds `/prid/<prid>` consistent with the field in **722/722** rows.
- **All 6 owner-blessed sku_map ids match scraped exactly:**

  | sku_map entry | blessed id | scraped prid | |
  |---|---|---|---|
  | CANOLA 1L | 407851 | 407851 | ✅ |
  | CANOLA 5L | 406593 | 406593 | ✅ |
  | EXTRA LIGHT 1L | 406592 | 406592 | ✅ |
  | EXTRA LIGHT 2L | 545244 | 545244 | ✅ |
  | JIVO POMACE 1L | 528706 | 528706 | ✅ |
  | JIVO POMACE 5L | 407561 | 407561 | ✅ |

- 3 NEW stable prids for the slug-anchored entries → proposed: SUNFLOWER 1L = 628632,
  MUSTARD 1L = 540835, MUSTARD 5L = 540970.

### B2. flipkart-minutes `fk_pid` — **SAFE-TO-FOLD** ✅
- 255/255 rows (100%) carry `fk_pid`; all are exactly **16 chars, /^[A-Z0-9]{13,16}$/
  conformant, 0 itm/lst-prefixed**.
- **10 distinct pids ↔ 10 distinct canonicals — 0 unstable.**
- `listing_url`: 0 malformed, 0 missing; url `pid=` param equals the `fk_pid` field in
  **255/255** rows (itm-token stays in the path where it belongs).
- sku_map's 9 flipkart-minutes entries are all slug-anchored (no real pids yet) → proposal
  supplies real pids for all of them + `jivo-mineral-water-1l` (scraped, no sku_map entry yet;
  lead's call).

### B3. bigbasket `ean` — **SAFE-TO-FOLD** ✅
- 9/23 rows carry `ean`; **all 9 match /^890\d{10}$/ exactly; zero non-conforming values**
  (the other 14 rows simply lack the field — absent, not malformed).
- **Anchor cross-check passes:** sku_id 282779 (CANOLA 1L) → ean **8905604001083**, the
  EAN verified from the raw payload. Bonus consistency: 282780 (CANOLA 5L) → 8905604000994.
- 3 of the 9 map onto existing sku_map ids (282779, 282780, 40335332 SODA LEMON 750ML);
  the remaining 6 are wheatgrass-juice/beverage SKUs with no sku_map entry yet — included in
  the proposal keyed by canonical for the lead to fold or park.

### Verdicts
| Platform | Gate | Verdict |
|---|---|---|
| blinkit | prid format + stability + blessed-id match | **SAFE-TO-FOLD** |
| flipkart-minutes | fk_pid regex + stability + url shape | **SAFE-TO-FOLD** |
| bigbasket | ean format + canola anchor | **SAFE-TO-FOLD** |

Ready-to-merge additions: **`tools/cron/tests/id_fold_proposal.json`**
(blinkit ×3, flipkart-minutes ×10, bigbasket ×9 — fold into sku_map.json = lead only).

---

## Pending re-verification before w3.done (owner instruction)
1. **W1 guardian changes** — adversarially re-verify: floor recalibration, spool-pull on
   guardian-BROKEN, no regression in heal/quarantine/alert behavior.
2. **W2 sweep-chain lock in run_all.sh** — re-verify: serialization, backstop skip, SIM
   tests still green.
