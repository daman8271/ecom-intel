# DEPLOY-DOCTOR.md — Ecom Doctor install runbook (LEAD)

The **Ecom Doctor** is the self-healing watchdog. It runs in the evening (after the noon
sweep + the 18:00 guardian), gathers deterministic health signals
(`tools/cron/health_snapshot.py`), and — only when something is wrong — invokes a bounded
headless Claude agent to diagnose and alert the owner on Telegram.

It ships in **two stages**:

- **Stage 1 — ALERT-ONLY (the default, `DOCTOR_AUTOFIX=0`).** The headless agent runs
  **READ-ONLY**: it diagnoses + writes proposed fixes into the report, but its scoped
  settings DENY `Edit`, `Write`, `NotebookEdit`, the `tools/cron/safe_fixes/` menu, and
  `./run.sh` — it applies **nothing**. The owner Telegram says *"ALERT-ONLY (auto-fix OFF)
  — proposed actions inside, none applied."* Run this until you trust the alerts.
- **Stage 2 — AUTO-FIX (`DOCTOR_AUTOFIX=1`).** The agent regains `Edit`/`Write` + the
  vetted `safe_fixes/` menu and may auto-apply a fix. Flip this only after ~a week of
  trusted Stage-1 alerts (step (d) below).

In **both** stages the always-on denies hold: **no** `git push`, `run_all.sh`, `curl`,
`crontab`, `rm -rf`, or `sudo`. The doctor never pushes, is flock-guarded against overlap,
and a doctor crash can **never** touch the 12:00 noon sweep or the 18:00 guardian.

---

## PRIME DIRECTIVE
The doctor must **never** affect the 12:00 noon sweep. Its cron fires **18:30** — after
the sweep and the guardian. The merged crontab keeps the existing sweep + guardian lines
**byte-identical**; it only ADDS 3 doctor lines (18:30 daily / Sun 19:00 weekly / 1st
19:30 monthly).

---

## INSTALL — 3 steps

### (a) Append the two flags to `secrets.env`
Stage 1 = alert-only. Append (do not touch existing keys):

```bash
cd /opt/ecom-intel
cat >> secrets.env <<'EOF'
ECOM_DOCTOR_ENABLE=1
DOCTOR_AUTOFIX=0
EOF
```

- `ECOM_DOCTOR_ENABLE=1` — the master enable. Unset (or `!=1`) = the doctor no-ops. (This
  is the kill switch — see below.)
- `DOCTOR_AUTOFIX=0` — alert-only. The safe default; an unset/garbage value is treated as
  `0` by `doctor.sh`, but set it explicitly so Stage 2 is a one-line flip.

> Owner alerts go to `TELEGRAM_OWNER_CHAT_ID` if set, else fall back to the existing
> `TELEGRAM_CHAT_ID` (already in `secrets.env`) — no extra Telegram config needed.

### (b) Merge the ecom-intel cron block
```bash
cd /opt/ecom-intel
crontab -l > /tmp/root.crontab.before-ecom-doctor
```
`tools/cron/doctor.crontab.txt` is the ecom-intel cron block, not the whole root crontab.
Merge its ecom lines into the live crontab while preserving other repo schedules on the host.
Do not run `crontab tools/cron/doctor.crontab.txt` on a shared root crontab.

### (c) Verify the install
```bash
# 1) the 3 sweep+guardian lines are unchanged + the 3 doctor lines are present:
crontab -l | grep -E '# ecom-intel'
# expect 6 lines: bigbasket-pincode (03:00), deadline-batch 12:00, guardian-daily,
#                 doctor-daily (18:30), doctor-weekly (Sun 19:00), doctor-monthly (1st 19:30)

# 2) the doctor parses + the alert-only settings are correct (no install side-effects):
bash -n tools/cron/doctor.sh && echo "doctor.sh OK"

# 3) optional dry-run — produces a report + a DRY Telegram payload, mutates NOTHING:
ECOM_DOCTOR_ENABLE=1 DOCTOR_DRY_RUN=1 \
  DOCTOR_AGENT_CMD='cat >/dev/null; echo stub' \
  tools/cron/doctor.sh daily
# expect the DRY tg_message to contain: "ALERT-ONLY (auto-fix OFF) — proposed actions inside, none applied."
```

---

## (d) STAGE-2 SWITCH — enable auto-fix (after ~a week of trusted alerts)
Flip the one flag in `secrets.env` (no crontab change needed):
```bash
cd /opt/ecom-intel
sed -i 's/^DOCTOR_AUTOFIX=0/DOCTOR_AUTOFIX=1/' secrets.env
grep '^DOCTOR_AUTOFIX=' secrets.env   # confirm: DOCTOR_AUTOFIX=1
```
Now the agent may apply VETTED-SAFE fixes from `tools/cron/safe_fixes/` (and the owner
Telegram switches to *"MODE: AUTO-FIX ON …"*). The always-on denies (push/sweeps/curl/
crontab/destructive) still hold. To revert to alert-only, set it back to `0`.

---

## (e) KILL SWITCH — disable the doctor entirely
The doctor is a no-op unless `ECOM_DOCTOR_ENABLE=1`. To stop it without touching the
crontab:
```bash
cd /opt/ecom-intel
sed -i 's/^ECOM_DOCTOR_ENABLE=1/ECOM_DOCTOR_ENABLE=0/' secrets.env
```
The 18:30/19:00/19:30 cron lines still fire but `doctor.sh` logs `disabled … no-op exit`
and stops immediately. (To remove the lines too: re-install the pre-doctor crontab, or
delete the `# ecom-intel doctor-*` lines.) The sweeps + guardian are unaffected either way.

---

## Notes
- `doctor.sh` is fail-safe: any internal error still fires an owner alert and exits 0; it
  has no path that can abort or modify the sweep crons.
- The three doctor lines are ≥30m apart and additionally serialized by `logs/.doctor.lock`,
  so the daily/weekly/monthly never overlap.
- This runbook is the LEAD's to run. The W2 deliverables (`doctor.sh`, `doctor.crontab.txt`,
  this file) do **not** edit `secrets.env` or install the crontab themselves.
