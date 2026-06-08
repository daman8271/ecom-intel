# Ecom Doctor — Safe-Fix Menu (the HARD auto-apply boundary)

This directory IS the doctor's authority. The headless doctor agent may AUTO-APPLY **only**
the fixes listed here, exactly as written, one platform/target per invocation. **Anything not
on this menu is PROPOSE-ONLY** — diagnose it, write a proposed patch into the report, alert the
owner, and apply nothing.

## Governing policy
**DIAGNOSE always · AUTO-APPLY only these vetted fixes · PROPOSE-ONLY everything else · NEVER
push · ALWAYS report.**

Every script here obeys the same contract:
- **Deterministic** — no LLM, no randomness; same inputs → same action.
- **Idempotent** — safe to run twice; a second run is a no-op (markers / lock probes).
- **Self-verifying** — it proves the precondition AND the post-condition before claiming success.
- **Fails loud and safe** — on ANY doubt it logs the reason and `exit 1`, which the agent reads
  as "this fix does not apply → fall back to PROPOSE-ONLY." It never half-applies.
- **Logs** every decision to `logs/doctor/safe_fixes.log` (gitignored).
- **Never** pushes, never edits engine/scraper/review code, never scrapes (except
  `rerun_platform.sh`, which is lock-guarded and refuses during a live sweep).

Shared helpers live in `_common.sh` (sourced by all; not a fix). Dry hooks for testing:
`DOCTOR_DRY=1` (no real Telegram / no launch), `RUNNER_OVERRIDE` (stub `./run.sh`).

---

## 1. `unhold_false_positive.sh <platform>`
**Trigger condition.** A platform's latest committed review verdict is SUSPECT/BROKEN (held),
AND **every** held reason is one of the two KNOWN false-positive classes:
- `shared_price_dup` — seller-duplicate / combo listings counted as distinct SKUs (the flipkart
  2026-06-08 incident).
- `price_staleness` — stable prices on the realtime path with movers present (the zepto
  2026-06-08 incident).

Both were genuine review.py false positives, now FIXED in committed logic (review-cal a4bce2db).

**What it does.** Re-runs `review.py` on the **same, unchanged** `result.json` with a synthetic
`<date>-doctor` RUN_ID. If the fresh verdict is **OK with zero reasons**, the hold was a proven
false positive: it rebuilds the workbook from that `result.json` (no scrape) and delivers —
**spools into the batch** if inside a deadline sweep (`SWEEP_ID` set → `send_batch` ships it
timely to stakeholders), otherwise **sends the recovered workbook to the OWNER channel** with a
clear "false-positive hold, re-verified OK" note (no unattended stale blast to stakeholders).

**Blast radius.** Re-reads existing data; writes a `reviews/*-doctor.json` verdict; rebuilds ONE
workbook; spools one batch file OR sends one message. No scrape, no push. A delivery marker
(`logs/doctor/.unheld-<p>-<mtime>`) prevents double-send.

**Why it's safe.** It can only ever *clear* a hold that the committed, version-controlled
review logic itself now rates OK — it does not invent a verdict. A non-FP held reason, a
re-review that is not clean OK, changed/unreadable data, or a failed build/delivery all → `exit
1` (propose-only). It never publishes data the review would reject.

## 2. `rerun_platform.sh <platform>`
**Trigger condition.** A single platform shows a TRANSIENT failure or empty/partial run (a lone
traceback, 0 rows, a one-off error) while the rest of the day looks healthy — i.e. worth one
clean retry, not a code fix.

**What it does.** Re-runs that one platform's pipeline (`./run.sh <platform>`), then verifies the
fresh verdict is OK.

**Blast radius.** One platform's full pipeline (this is the only network-touching fix). Bounded
to a SINGLE attempt — the self-heal already does bounded retries; the doctor is not a retry loop.

**Why it's safe.** Heavily lock-guarded: refuses (`exit 1`) if a live sweep holds
`logs/.sweep-chain.lock` or if a per-account Amazon lock is held, and it **holds** the
sweep-chain lock for the rerun so a sweep can't start under it — preserving the cardinal rule
*never scrape concurrently with a sweep*. If the rerun exits non-zero or the verdict is still
not OK → `exit 1` (propose-only / escalate).

## 3. `clear_stale_lock.sh <lockfile>`
**Trigger condition.** A lock file is suspected orphaned (its holder died) and the agent wants to
assert it is free / tidy it.

**What it does.** Probes the lock with a NON-BLOCKING `flock`. If it acquires it, no live process
holds it → the lock is provably orphaned → it removes the file. If it cannot acquire it → a live
holder exists → refuses.

**Blast radius.** Removes one provably-orphaned `.lock` file inside the repo. Missing file =
already-clear no-op.

**Why it's safe.** It is impossible to break an *active* lock: the only path to removal is having
just held it non-blockingly. Guards: path must be inside the repo, end in `.lock`, not be a
directory, and not be git-tracked. (Note: with `flock`, a leftover file is normally harmless
anyway — the kernel releases on holder death — so this is mostly hygiene.)

## 4. `restart_helper.sh <name>`
**Trigger condition.** A known background helper is enabled but provably dead.

**What it does.** For an allow-listed helper (`wa-bridge`) that is enabled by its own env gate
and currently not running, relaunches it; verifies it came up.

**Blast radius.** Restarts one allow-listed helper. Unknown name, already-running, disabled, or
relaunch-didn't-come-up → `exit 1`.

**Why it's safe.** The pipeline is cron-driven with no resident services in the scrape/review/
deliver path, so this is **almost always a deliberate no-op** (`exit 1` → propose-only). It will
never restart anything not on the allow-list, never one that is disabled, and never one already
alive.

---

## Adding a new safe fix (the bar)
A candidate becomes a menu item only when it is: deterministic, idempotent, self-verifying,
non-pushing, with a tightly bounded blast radius, a clear single trigger, and a documented "why
it's safe" — and after a dry-run proves both the apply path and the `exit 1` propose-only
fallback. Until then it stays PROPOSE-ONLY in the agent's report.
