> **HISTORICAL (2×/day era, pre-2026-06-28) — the live crontab is now a single 12:00 sweep.**

# W3 — Go-Live Adversarial Gate: "nothing breaks tomorrow"

**Verdict: ✅ PASS — both changes are safe to push + install.**
Tomorrow's 12:00 + 15:00 IST sweeps run at full quality, unaffected.

- Date: 2026-06-08
- W1 commit verified: `8bf79b60` (ctnow-resilient: per-pincode try/catch)
- W2 commit verified: `2f008518` (doctor-alertonly) + `doctor.crontab.txt` @ `f3e3ecba`
- Prod result.json (`platforms/amazon-now/result.json`) md5 **`1d30c21b54cf9603e460148a3cda8fb0`**, mtime `2026-06-08 16:08:44` — **identical before/after every live action below.** Never overwritten.

All live actions ran under `flock .amazon-now.lock` with `OUT_FILE=/tmp/...`. Read-only on prod otherwise.

---

## W1 — scrape.ctnow.js (the scraper that runs in tomorrow's sweep)

### Check 1 — Normal path byte-identical · ✅ PASS
- `node --check` on the committed file: **clean**.
- Commit diffstat: `54 insertions(+), 37 deletions(-)` — but that is re-indentation noise.
- **Indentation-insensitive diff** (strip leading whitespace + blank lines, `8bf79b60~1` → `8bf79b60`):
  - Lines **added** = only the resilience scaffolding:
    `let failedPins = 0;` · the resilience comment · `try {` · `} catch (err) {` · `[skip]` stderr ·
    the failed-pincode `perPin.push({...serviceable:false, rows:[]})` · `failedPins++;` · `continue;` ·
    `[done]` stderr · the catastrophic-guard comment · `if (failedPins > PINCODES.length/2) [ALARM]`.
  - Lines **removed = NONE (zero `<` lines).**
- ⇒ Every line of the **Now-gate** (`amazon_now_page` / `isInstantNow`), **GLOW/token mint**, **row
  parsing** (`fastSetAndSearch` evaluate, badge/`nowBadge` discriminator), **dedup** (`seen`/`canonical`),
  **result.json schema** (`{summary, perPin, allRows}`), and the **SESSION_EXPIRED** fail-closed path
  (lines 232–240, *outside* the loop) is present **byte-identical** — only re-indented one level into the `try`.

### Check 2 — Resilience actually works · ✅ PASS
Independently reproduced (committed file, `LIMIT=4`, `OUT_FILE=/tmp`, under lock):

**(a) Live normal smoke** — `EXIT=0`:
```
[ok] Bengaluru 560001 nowPage=true  svc=true  -> 5  jivo-now [1/4]
[ok] Bengaluru 560014 nowPage=false svc=false -> 0  jivo-now [2/4]   (gate correctly rejects non-Now)
[ok] Bengaluru 560019 nowPage=true  svc=true  -> 5  jivo-now [3/4]
[ok] Bengaluru 560028 nowPage=true  svc=true  -> 11 jivo-now [4/4]
[done] 4 pincodes, 0 failed (skipped)
summary: 4 total / 3 serviceable / 21 rows / all "10 min" tier / 0 mismatch
```
Behaviour on success is unchanged.

**(b) Real fault-injection** — a one-shot `TypeError('Failed to fetch')` (the *exact* original crash
signature) forced on pincode 560019's search-evaluate via a `/tmp` preload that wraps the public
playwright API on the cached module object — **no edit to scrape.ctnow.js**:
```
[ok]   Bengaluru 560001 ... -> 5 jivo-now [1/4]
[ok]   Bengaluru 560014 ... -> 0 jivo-now [2/4]
[skip] 560019 Failed to fetch            <- caught, recorded as 0-row/failed
[ok]   Bengaluru 560028 ... -> 11 jivo-now [4/4]   <- run CONTINUED past the failure
[done] 4 pincodes, 1 failed (skipped)
EXIT=0   (no crash; temp result.json well-formed: 4 total / 2 svc / 16 rows / 1 mismatch)
```
One transient blip no longer kills the sweep — it skips that pincode and finishes the rest.

### Check 3 — Catastrophic still surfaces (resilience does NOT mask an outage) · ✅ PASS
Forced **every** pincode's search to throw:
```
[skip] 560001 / 560014 / 560019 / 560028 Failed to fetch
[done] 4 pincodes, 4 failed (skipped)
[ALARM] majority of pincodes failed       <- loud, but NO hard-exit (crash not reintroduced)
summary: total_rows = 0
```
Fed that 0-row result.json to the **real `tools/review.py`** (against the real committed
`baselines/amazon-now.json`, expected rows 607; harness redirected writes to /tmp, baseline read-only):
```
VERDICT: BROKEN
reasons: non_zero_rows 0 · rows_above_floor 0 (floor 20) ·
         rows_vs_baseline 0% of 607 (collapse) · skus_vs_baseline 0% ·
         pincode_coverage collapsed · priced_floor_block collapse
```
A mass outage still lands as **BROKEN** → held back from stakeholders by the verdict gate. The safety net is intact.

### Check 4 — Tomorrow's production result.json untouched · ✅ PASS
md5 `1d30c21b54cf9603e460148a3cda8fb0`, mtime `16:08:44` — **identical** before the smoke, after the
smoke, after the fault run, after the catastrophic run, and at end of verification. All output went to `/tmp`.

---

## W2 — Doctor ALERT-ONLY + crontab

### Check 1 — Crontab is additive (sweep+guardian byte-identical, +3 doctor lines) · ✅ PASS
Compared the **active (non-comment) cron lines** of the live `crontab -l` vs `tools/cron/doctor.crontab.txt`.
`diff` result = `3a4,6` — i.e. the 3 live lines are unchanged and exactly 3 lines are appended, **0 removed/modified**:

```
  30 8  * * *  ... deadline_sweep.sh 12:00 ...   # ecom-intel deadline-batch 12:00     [identical]
  30 11 * * *  ... deadline_sweep.sh 15:00 ...   # ecom-intel deadline-batch 15:00     [identical]
  0  18 * * *  ... guardian_daily.sh    ...      # ecom-intel guardian-daily           [identical]
+ 30 18 * * *  ... doctor.sh daily   ...         # ecom-intel doctor-daily             [ADDED]
+ 0  19 * * 0  ... doctor.sh weekly  ...         # ecom-intel doctor-weekly            [ADDED]
+ 30 19 1 * *  ... doctor.sh monthly ...         # ecom-intel doctor-monthly           [ADDED]
```
The three doctor lines fire **18:30 / Sun 19:00 / 1st 19:30 IST** — all evening, well clear of the
sweep chains (~08:41–14:02) and the 18:00 guardian.
*Note (non-blocking):* `doctor.crontab.txt` carries different *comment* prose than the installed crontab
(it drops the long overlap-analysis comment block). Comments are inert to cron; the executable schedule
is provably additive. The lead installs.

### Check 2 — Alert-only is truly read-only · ✅ PASS
- `bash -n doctor.sh`: clean. `DOCTOR_AUTOFIX` defaults to **0** (`${DOCTOR_AUTOFIX:-0}`, any non-`1` coerced to 0).
- Both generated `settings.json` heredocs are **valid JSON**. Tool placement:

  | tool | AUTOFIX=0 (default) | AUTOFIX=1 |
  |---|---|---|
  | Edit / Write / NotebookEdit | **DENY** | allow (NotebookEdit absent) |
  | `safe_fixes/*` | **DENY** | allow |
  | `./run.sh` | **DENY** | allow |
  | git push · run_all.sh · curl · crontab · rm -rf · sudo | **DENY** | **DENY** (always-on) |

  AUTOFIX=0 allow-list is read-only only (Read/Grep/Glob + `python3/node/ls/cat/grep/.../git status|diff|log|show`).
- **Dry alert-only run** (`ECOM_DOCTOR_ENABLE=1 DOCTOR_DRY_RUN=1`, AUTOFIX unset, read-only stub agent):
  - Telegram payload: `🩺⚠️ Ecom Doctor (daily) ... overall=YELLOW` / **`MODE: ALERT-ONLY (auto-fix OFF) — proposed actions inside, none applied.`**
  - git **HEAD unchanged** (`2f008518`), working **tree unchanged** (42 porcelain lines, empty diff before/after). Mutated nothing.
  - With `DOCTOR_AUTOFIX=1`: mode line becomes `MODE: AUTO-FIX ON ...` (stage-2 path exists, OFF by default).

### Check 3 — No effect on sweeps · ✅ PASS (by inspection)
- Fires 18:30/19:00/19:30 — after both sweeps + the 18:00 guardian.
- Holds **only** `logs/.doctor.lock` (`flock -n`, single-flight) — **never** the sweep-chain lock, `run_all.sh`, or `deadline_sweep.sh`.
- `run_all` / `result.json` appear in doctor.sh **only** inside deny-rules and prompt text (read-context) — no write path to either.
- Fail-safe: `ECOM_DOCTOR_ENABLE!=1` ⇒ no-op `exit 0` (kill switch verified); any internal error ⇒ owner alert ⇒ `exit 0`. No path can abort or modify the sweep crons.
- `DEPLOY-DOCTOR.md` runbook present: append `ECOM_DOCTOR_ENABLE=1`+`DOCTOR_AUTOFIX=0` to secrets.env · merge the ecom-intel block while preserving other repo crons · verify via `crontab -l | grep '# ecom-intel'` · stage-2 flip · kill switch.

---

## Lead action items (only on this PASS)
1. Push W1 `8bf79b60` + W2 `2f008518`.
2. Append to `secrets.env`: `ECOM_DOCTOR_ENABLE=1`, `DOCTOR_AUTOFIX=0`.
3. Merge `tools/cron/doctor.crontab.txt` into the live root crontab, preserving non-ecom repo lines; verify `crontab -l` shows the sweep+guardian lines unchanged + doctor lines.
4. Housekeeping (non-blocking): an empty stray file `platforms/amazon-now/8` (W1 flock artifact, 17:18 IST) can be `rm`'d.
