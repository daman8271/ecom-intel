#!/usr/bin/env python3
"""Send email via Gmail SMTP (app-password auth).

Best-effort helper for ecom-intel — mirrors the Telegram delivery philosophy in
run.sh: it prints an error and exits non-zero on failure, but never raises an
uncaught exception, so a caller can ignore the exit code and keep the run alive.

Credentials are read from the environment (source secrets.env first):
  GMAIL_USER            sender Gmail address
  GMAIL_APP_PASSWORD    16-char app password (spaces optional; they are stripped)

Usage:
  set -a; . /opt/ecom-intel/secrets.env; set +a
  python3 tools/send_email.py --to a@b.com[,c@d.com] --subject "..." --body "..." \
          [--attach report.xlsx ...] [--from-name "Jivo Intel"]
  echo "body text" | python3 tools/send_email.py --to a@b.com --subject "..."
"""
import argparse
import mimetypes
import os
import smtplib
import ssl
import sys
from email.message import EmailMessage

SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 465  # implicit SSL


def main() -> int:
    ap = argparse.ArgumentParser(description="Send email via Gmail SMTP.")
    ap.add_argument("--to", required=True, help="comma-separated recipient addresses")
    ap.add_argument("--subject", default="(no subject)")
    ap.add_argument("--body", default=None, help="body text; if omitted, read from stdin")
    ap.add_argument("--attach", action="append", default=[], help="file to attach (repeatable)")
    ap.add_argument("--from-name", default=None, help="display name for the sender")
    args = ap.parse_args()

    user = os.environ.get("GMAIL_USER", "").strip()
    pw = os.environ.get("GMAIL_APP_PASSWORD", "").replace(" ", "")
    if not user or not pw:
        print("ERROR: GMAIL_USER / GMAIL_APP_PASSWORD not set (source secrets.env first)",
              file=sys.stderr)
        return 2

    body = args.body if args.body is not None else sys.stdin.read()

    msg = EmailMessage()
    msg["From"] = f"{args.from_name} <{user}>" if args.from_name else user
    recipients = [r.strip() for r in args.to.split(",") if r.strip()]
    if not recipients:
        print("ERROR: no valid recipients in --to", file=sys.stderr)
        return 2
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = args.subject
    msg.set_content(body)

    for path in args.attach:
        if not os.path.isfile(path):
            print(f"WARN: attachment not found, skipping: {path}", file=sys.stderr)
            continue
        ctype, _ = mimetypes.guess_type(path)
        maintype, subtype = (ctype.split("/", 1) if ctype else ("application", "octet-stream"))
        with open(path, "rb") as fh:
            msg.add_attachment(fh.read(), maintype=maintype, subtype=subtype,
                               filename=os.path.basename(path))

    try:
        ctx = ssl.create_default_context()
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=ctx, timeout=60) as s:
            s.login(user, pw)
            s.send_message(msg, to_addrs=recipients)
    except Exception as e:  # best-effort: report, never crash the caller
        print(f"ERROR: send failed: {e}", file=sys.stderr)
        return 1

    print(f"OK: sent '{msg['Subject']}' to {', '.join(recipients)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
