#!/usr/bin/env python3
"""
check_layout.py — post-batch layout gate (alert-only, never breaks the chain).

Owner rule 2026-06-10: agreed-price (BAU/SVD/ART) content is Amazon-only.
After each batch this verifies, for today's books:
  - competitor platforms (zepto/blinkit/flipkart/flipkart-minutes/bigbasket):
      NO "Price Match" tab, NO agreed-price block on the Leadership View
  - Amazon family (amazon/amazon-fresh/amazon-now):
      "Price Match" tab present

Telegram: FAILs always ping. PASS pings exactly once (first run after install,
state file logs/.layout_gate_bootstrapped) so the owner gets one positive
confirmation, then silence-unless-broken. --dry-run = check + print only.
Exit 0 always (alert-only, mirrors the doctor philosophy).
"""

import datetime
import glob
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))                 # /opt/ecom-intel
STATE = os.path.join(ROOT, "logs", ".layout_gate_bootstrapped")
TG_ENV = "/root/.config/tg/env"

COMPETITORS = ["zepto", "blinkit", "flipkart", "flipkart-minutes", "bigbasket"]
AMAZON_FAMILY = ["amazon", "amazon-fresh", "amazon-now"]
BAU_MARKERS = ("price plan", "Below reference", "BELOW reference",
               "below reference", "agreed price")


def newest_book(platform, date):
    pat = os.path.join(ROOT, "platforms", platform, f"Jivo-*{date}*.xlsx")
    books = sorted(glob.glob(pat), key=os.path.getmtime)
    return books[-1] if books else None


def check_book(platform, path):
    """Return a list of problem strings (empty = compliant)."""
    import openpyxl
    problems = []
    wb = openpyxl.load_workbook(path, read_only=True)
    try:
        has_tab = "Price Match" in wb.sheetnames
        if platform in AMAZON_FAMILY:
            if not has_tab:
                problems.append(f"{platform}: 'Price Match' tab MISSING")
            return problems
        if has_tab:
            problems.append(f"{platform}: 'Price Match' tab present (Amazon-only)")
        ws = wb[wb.sheetnames[0]]
        for row in ws.iter_rows():
            for c in row:
                v = str(c.value or "")
                if any(m in v for m in BAU_MARKERS):
                    problems.append(f"{platform}: agreed-price text on "
                                    f"{ws.title} r{c.row}: {v[:60]!r}")
                    return problems          # one example is enough
        return problems
    finally:
        wb.close()


def telegram(text):
    tok = chat = None
    try:
        for line in open(TG_ENV):
            line = line.strip()
            if line.startswith("TELEGRAM_BOT_TOKEN="):
                tok = line.split("=", 1)[1]
            elif line.startswith("TELEGRAM_CHAT_ID="):
                chat = line.split("=", 1)[1]
        if not (tok and chat):
            raise RuntimeError("tg env incomplete")
        urllib.request.urlopen(
            f"https://api.telegram.org/bot{tok}/sendMessage",
            data=urllib.parse.urlencode({"chat_id": chat, "text": text}).encode(),
            timeout=30)
    except Exception as e:                    # alert-only: never raise
        sys.stderr.write(f"check_layout: telegram failed (non-fatal): {e}\n")


def main(argv):
    dry = "--dry-run" in argv
    date = datetime.date.today().isoformat()
    problems, missing, checked = [], [], 0
    for p in COMPETITORS + AMAZON_FAMILY:
        path = newest_book(p, date)
        if not path:
            missing.append(p)                 # batch may have held a report
            continue
        checked += 1
        problems.extend(check_book(p, path))

    if problems:
        msg = ("🚨 LAYOUT GATE FAIL — today's batch violates the Amazon-only "
               "rule:\n" + "\n".join("• " + q for q in problems[:10])
               + (f"\n(books missing: {', '.join(missing)})" if missing else ""))
        print(msg)
        if not dry:
            telegram(msg)
        return 0
    note = (f"layout gate PASS — {checked} book(s) compliant"
            + (f" ({', '.join(missing)} not built yet)" if missing else ""))
    print(note)
    if not dry and not os.path.exists(STATE):
        telegram("✅ Layout gate live: today's batch verified — competitor "
                 "reports carry no agreed-price content, Amazon books intact. "
                 "This pings again only if a future batch ever breaks the rule.")
        open(STATE, "w").write(date + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
