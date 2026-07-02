> **HISTORICAL (2×/day era, pre-2026-06-28) — the live crontab is now a single 12:00 sweep.**

# Ecom Doctor — W3 end-to-end dry-run verdict

**VERDICT: ✅ PASS — 41/41 assertions PASS, 0 FAIL, 0 SKIP** (with `--with-real-agent`;
39/39 + 1 opt-in SKIP without it). This PASS gates the crontab install.

- Harness: `tools/cron/tests/doctor_dryrun.sh` (re-runnable; artifacts under
  `tools/cron/tests/doctor/`, gitignored). Run: `bash tools/cron/tests/doctor_dryrun.sh [--with-real-agent]`.
- Subjects: W1 `health_snapshot.py` + `doctor.sh`; W2 `safe_fixes/` + `doctor_prompt.md`.
- Date of run: 2026-06-08 (IST). Real-repo overall at verification time: **YELLOW**
  (only `batch_held:2026-06-08-1200` — a today's-`cron.log` artifact from the morning batch
  that shipped with flipkart+zepto held; the held *streaks themselves have cleared* after the
  LEAD re-ran review on the sweep run-ids, and the batch_held line ages out tomorrow).

## How the dry-run stays safe (no scrape / no Telegram / no Claude spend / no install)
- **Fixtures via `HEALTH_ROOT`**: each scenario is a throwaway fake root (`reviews/` +
  `logs/cron.log`) that `health_snapshot.py` reads via its `HEALTH_ROOT` override — the **real
  `reviews/` is never touched**.
- **PATH shims** (`tests/doctor/bin/`) make the run hermetic regardless of doctor.sh internals:
  `curl` logs every Telegram call and **never hits the network**; `git` makes `push` a tripwire
  (fails) and `commit` a no-op (so the working tree is never mutated); `claude` is the agent stub.
- **`DOCTOR_DRY_RUN=1`** is the primary no-send guarantee (doctor.sh *logs* payloads instead of
  curling). doctor.sh sources the real `secrets.env`, so dead-cred env vars alone wouldn't help —
  `DOCTOR_DRY_RUN` + the curl shim are what actually prevent a send.
- **`DOCTOR_AGENT_CMD`** stub exercises doctor.sh's full orchestration with **zero Claude spend**.
- The one real sonnet call (`--with-real-agent`) runs in an **isolated temp dir**, never the real
  repo (rationale below).

## Assertion results (per the agent-3 task's 4 deliverable-2 areas)

### 1. Detection — fixtures drive the exact verdicts
| # | Assertion | Result |
|---|---|---|
| 1.YELLOW | overall=YELLOW for flipkart×2 + zepto×2 SUSPECT held + 6 OK | ✅ PASS |
| 1.YELLOW | issues name `held_streak:flipkart` and `held_streak:zepto` | ✅ PASS |
| 1.YELLOW | reasons carried (`shared_price_dup`, `price_staleness`) | ✅ PASS |
| 1.YELLOW | the other 6 platforms NOT false-flagged held (×6) | ✅ PASS |
| 1.RED | overall=RED for a BROKEN platform (bigbasket×2) | ✅ PASS |
| 1.RED | overall=RED for a **missing batch** (no send_batch line past grace) | ✅ PASS |
| 1.RED | the missing-batch issue carries `batch_delivery` + names `batch_missing:<today>-1200` | ✅ PASS |
| 1.GREEN | overall=GREEN + **zero issues** when all platforms OK & batches delivered | ✅ PASS |

### 2. Orchestration is bounded (doctor.sh)
| # | Assertion | Result |
|---|---|---|
| 2.GREEN | GREEN ⇒ doctor does **NOT** invoke the agent | ✅ PASS |
| 2.GREEN | GREEN ⇒ emits a one-line all-clear owner message | ✅ PASS |
| 2.YELLOW | non-GREEN ⇒ invokes the headless agent (via `DOCTOR_AGENT_CMD` stub) | ✅ PASS |
| 2.YELLOW | agent writes its diagnosis to the doctor-supplied `DOCTOR_DIAGNOSIS_PATH` | ✅ PASS |
| 2.YELLOW | health `report.json` persisted under `logs/doctor/<scope>-<date>.json` | ✅ PASS |
| 2.YELLOW | owner Telegram **alert fires** (DRY-logged, `overall=YELLOW`) | ✅ PASS |
| 2.YELLOW | no Telegram curl escaped DRY mode | ✅ PASS |
| 2b.LIVE | **one real isolated sonnet call** launches headless + writes its file | ✅ PASS |
| 2b.LIVE | the real agent is **BLOCKED from `git push`** by the scoped settings (live) | ✅ PASS |

### 3. Guardrails hold
| # | Assertion | Result |
|---|---|---|
| 3a | `ECOM_DOCTOR_ENABLE` unset ⇒ no-op (no agent) + logs "disabled" | ✅ PASS |
| 3b | `logs/.doctor.lock` held ⇒ a second doctor refuses (no overlap) | ✅ PASS |
| 3c | scoped agent settings **DENY** `git push`; doctor.sh has no push invocation; prompt never allows it; runtime tripwire saw **zero** push attempts | ✅ PASS (×4) |
| 3d | a `safe_fixes/` script exits **≠0 on ambiguity** ⇒ propose-only (`unhold_false_positive.sh <bogus>` → rc=1, did nothing) | ✅ PASS |
| 3e | a crash / odd input still produces an owner alert; doctor.sh **never touches the crontab** | ✅ PASS (×2) |

### 4. No-regression on the REAL repo (strictly read-only)
| # | Assertion | Result |
|---|---|---|
| 4 | `health_snapshot` produces valid JSON on the live repo | ✅ PASS |
| 4 | running the full `doctor.sh` leaves **HEAD unchanged** (no commit) | ✅ PASS |
| 4 | **no push** attempted | ✅ PASS |
| 4 | **no working-tree mutation** beyond W3's own deliverables | ✅ PASS |
| 4 | non-GREEN handled without repo mutation (agent engages correctly) | ✅ PASS |

**On the "all 8 OK ⇒ GREEN all-clear" premise:** at build time the live repo was *not* clean —
the latest *sweep-runid* reviews for flipkart/zepto were still SUSPECT (the unhold fix had only
written OK `-unhold` sidecars, which the sweep-runid regex correctly excludes). So `health_snapshot`
was *right* to report YELLOW. The clean GREEN all-clear path is therefore proven by the **GREEN
fixture** (1.GREEN + 2.GREEN), and the real-repo test asserts the true safety guarantee — doctor.sh
is **read-only** (no push, no commit, no tree mutation, no crontab touch). The LEAD has since
re-run review on the sweep run-ids (held streaks cleared); a residual `batch_held` log-artifact
remains and ages out next day. (Reported to the LEAD on the bus.)

## Why the real sonnet call runs ISOLATED, not through doctor.sh's live path
doctor.sh's live branch hardcodes `--add-dir <real repo>` with `Edit/Write/safe_fixes` allowed.
Pointed at a held-flipkart report, a live model would be *invited* to re-run the real review
pipeline unattended — the exact "edits a production pipeline on its own authority" risk the whole
design guards against. So the `--with-real-agent` probe instead exercises the **identical live
seam** (`claude -p --model sonnet --output-format text --add-dir <tmp> --settings <scoped>`, the
same scoped `settings.json` doctor.sh writes) in a throwaway temp dir, proving (i) a live headless
agent launches with no permission prompts and writes its output, and (ii) the scoped **deny blocks
`git push` live**. doctor.sh's full orchestration around that seam is proven separately by the
`DOCTOR_AGENT_CMD` stub. Together they cover the whole path with zero production exposure.

---

## Deliverable: the ecom-intel cron block the LEAD merges
The ecom block is **`tools/cron/doctor.crontab.txt`**. Merge it into the live root crontab
while preserving non-ecom repo schedules; do not install it as the whole crontab on shared hosts.
It contains the live ecom deadline sweep, guardian, watchdog, layout gate, mailer, and these
three additive doctor lines (IST; cron runs in system-local = IST):

```cron
# Ecom Doctor — daily 18:30 (after both sweeps land + the 18:00 guardian: sees the whole day)
30 18 * * * cd /opt/ecom-intel && ./tools/cron/doctor.sh daily   >> logs/doctor.log 2>&1   # ecom-intel doctor-daily
# weekly 7-day trends — Sunday 19:00 (after the daily; lock-serialized)
0 19 * * 0 cd /opt/ecom-intel && ./tools/cron/doctor.sh weekly  >> logs/doctor.log 2>&1   # ecom-intel doctor-weekly
# monthly 30-day rollup — 1st 19:30 (after daily/weekly; lock-serialized)
30 19 1 * * cd /opt/ecom-intel && ./tools/cron/doctor.sh monthly >> logs/doctor.log 2>&1   # ecom-intel doctor-monthly
```

**Install safety:** ADDITIVE — the sweep + guardian lines are untouched. The three doctor times
(18:30 / 19:00 / 19:30, ≥30m apart) sit in the evening well clear of the sweep chains
(~08:41–14:02) and the read-only 18:00 guardian, and are further serialized by
`logs/.doctor.lock`. `setup_cron.sh` only edits `# ecom-intel`-tagged lines, so it stays
re-runnable over this file. **Before un-pausing**, the LEAD must set `ECOM_DOCTOR_ENABLE=1` in
`secrets.env` (kill switch = unset it); without it every doctor line is a logged no-op.

## Reproduce
```bash
bash tools/cron/tests/doctor_dryrun.sh                 # 39 asserts, hermetic, ~seconds
bash tools/cron/tests/doctor_dryrun.sh --with-real-agent   # +2 live (one isolated sonnet call)
cat tools/cron/tests/doctor/results.tsv                # machine-readable PASS/FAIL
```
