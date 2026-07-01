#!/usr/bin/env python3
"""
edit_cron.py [--apply] — switch the ecom-intel pipeline from 2x/day to 1x/day @ noon.

Reads the LIVE crontab (`crontab -l`), applies these exact transforms, shows a diff:
  DROP  the 15:00 deadline sweep            (line w/ deadline_sweep.sh 15:00)
  DROP  the 15:00 layout gate               (10 15 * * * check_layout.py)
  DROP  the 16:00 pm mailer                 (mail_price_data.sh pm)
  RETIME the noon sweep  30 8 ->  0 4  and  LEAD_MAX=12600 -> 27000
         (fire 04:00 so the self-aligning sleep lands the longer chain at 12:00;
          27000s=7.5h ceiling > the ~6h predicted lead for ~460 anchors)
  RETIME the BigBasket paid pull  0 8 -> 0 3   (fresh before the sweep scrapes)
  KEEP   the 10:00 am mailer (waits up to 3h -> catches the ~12:00 batch),
         the 12:10 layout gate, guardian, doctor.

Backs up the live crontab to tools/cron/crontab.prepincode.bak before applying.
Without --apply: dry run (prints the proposed crontab + diff, installs nothing).

NOTE: the live 1x/day cron now lives in tools/cron/doctor.crontab.txt (single 12:00 sweep);
this script performed the one-time 2x/day -> 1x/day cutover.
"""
import subprocess, sys, os, re, difflib

APPLY = "--apply" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
BAK = os.path.join(HERE, "..", "cron", "crontab.prepincode.bak")

cur = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
if cur.returncode != 0:
    sys.exit("could not read crontab: " + cur.stderr)
lines = cur.stdout.splitlines()

out = []
changes = []
for ln in lines:
    drop = False
    if "deadline_sweep.sh 15:00" in ln:
        drop = True; changes.append("DROP 15:00 sweep")
    elif "check_layout.py" in ln and ln.strip().startswith("10 15"):
        drop = True; changes.append("DROP 15:00 layout gate")
    elif "mail_price_data.sh pm" in ln:
        drop = True; changes.append("DROP 16:00 pm mailer")
    if drop:
        continue
    new = ln
    if "deadline_sweep.sh 12:00" in ln:
        new = re.sub(r"^\s*30\s+8\s+", "0 4 ", new)
        new = new.replace("LEAD_MAX=12600", "LEAD_MAX=27000")
        if new != ln:
            changes.append("RETIME noon sweep 30 8->0 4, LEAD_MAX 12600->27000")
    elif "run_pincode.sh" in ln and re.match(r"^\s*0\s+8\s+", ln):
        new = re.sub(r"^\s*0\s+8\s+", "0 3 ", new)
        if new != ln:
            changes.append("RETIME bigbasket pull 0 8->0 3")
    out.append(new)

new_crontab = "\n".join(out) + "\n"
print("=== CHANGES ===")
for c in changes:
    print("  -", c)
print("\n=== DIFF ===")
for d in difflib.unified_diff(lines, new_crontab.splitlines(),
                              "crontab.current", "crontab.proposed", lineterm=""):
    print(d)

if APPLY:
    with open(BAK, "w") as f:
        f.write(cur.stdout if cur.stdout.endswith("\n") else cur.stdout + "\n")
    p = subprocess.run(["crontab", "-"], input=new_crontab, text=True)
    if p.returncode != 0:
        sys.exit("crontab install FAILED")
    print(f"\nAPPLIED. Backup saved to {os.path.abspath(BAK)}")
    print("Verify with: crontab -l")
else:
    print("\nDRY-RUN. Re-run with --apply to install.")
