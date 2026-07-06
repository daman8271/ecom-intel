#!/usr/bin/env python3
"""send_batch.py <sweep_id> <deadline_epoch> — the delivery barrier.

Called by run_all.sh after the serial platform loop (W2's hook, DEFER_DELIVERY=1).
Reads the spool dir output/.batch/<sweep_id>/ written by run.sh's defer mode after
the deadline barrier, so late off-box spools that land while this process is
sleeping still join the batch. Delivers EVERYTHING as one batch AT the deadline
("everyone comes at the timing"):

  - now < deadline  -> sleep until the deadline (the barrier), then send;
  - chain overran   -> send immediately, header marked "(late by Xm)".

Spool schema v1 (FROZEN on the bus, W2 writes / this script reads):
  OK:   {"platform","verdict":"OK","summary","xlsx","caption","ts":<int epoch>}
  Held: {"platform","verdict":"SUSPECT|BROKEN","held":true,
         "reasons":"<'; '-joined string, may be empty>","ts":<int epoch>}
  A platform MISSING from the dir = not spooled (no Excel, or run.sh's spool-write
  fell back to immediate send — ALREADY delivered): never resend, just list it.

Sends ONE header, then each spooled OK platform's summary + xlsx document in the
CANONICAL order, then a footer listing held / not-spooled / late, to the same
chat ids run.sh uses (secrets.env, same curl flags / parse_mode=Markdown).

Idempotent + partial-send resume safe: each platform file is renamed to
<p>.json.sent after its two sends succeed; header/footer get .sent markers; the
whole dir moves to .batch/sent-<sweep_id> only when everything spooled went out.

Fail-safe (never lose a report): any single failure is logged + skipped, the
file stays in the spool for a resume; this script ALWAYS exits 0 (run_all also
wraps it with || true). An owner alert line goes to stdout (cron.log) and
logs/telegram.log on any failure.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # tools/cron -> repo root
TGLOG = os.path.join(ROOT, "logs", "telegram.log")

CANONICAL = [
    "flipkart-minutes", "flipkart", "zepto", "bigbasket",
    "amazon", "amazon-fresh", "amazon-now", "blinkit",
    "swiggy-instamart",   # residential-IP collector, spooled from output/ by run_all.sh
    "price-match",   # master Price Match workbook — sent LAST (most visible in chat)
]


def now():
    return int(time.time())


def stamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(msg):
    line = f"[{stamp()}] send_batch: {msg}"
    try:                       # even a closed stdout (broken pipe) must not raise
        print(line, flush=True)
    except Exception:
        pass
    try:
        os.makedirs(os.path.dirname(TGLOG), exist_ok=True)
        with open(TGLOG, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def platforms():
    ov = os.environ.get("PLATFORMS_OVERRIDE", "").split()
    return ov if ov else CANONICAL


def read_secrets():
    """Parse secrets.env the same way run.sh sources it (KEY=VALUE shell lines).

    SIM SAFETY (W4 hard requirement, LEAD-ratified): pre-set TELEGRAM_* env vars
    take PRECEDENCE over secrets.env, and SECRETS_FILE overrides the file path —
    so a test harness can inject dead creds and this script can never pick up the
    real token underneath them. TG_DRY_RUN=1 (see curl()) skips the network
    entirely.
    """
    env = {}
    path = os.environ.get("SECRETS_FILE") or os.path.join(ROOT, "secrets.env")
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                if line.startswith("export "):
                    line = line[len("export "):]
                k, _, v = line.partition("=")
                v = v.strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                    v = v[1:-1]
                env[k.strip()] = v
    except OSError:
        pass
    # env vars BEAT the file — sim-injected dead creds always win
    for k in ("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID", "TELEGRAM_OWNER_CHAT_ID"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def curl(args, timeout):
    """Run curl exactly like run.sh does; return (ok, response_text)."""
    if os.environ.get("TG_DRY_RUN") == "1":      # sim mode: no network at all
        log(f"TG_DRY_RUN curl {' '.join(args[:3])} ... (suppressed)")
        return True, '{"ok":true,"dry_run":true}'
    try:
        r = subprocess.run(["curl", "-s", "--max-time", str(timeout)] + args,
                           capture_output=True, text=True, timeout=timeout + 30)
        body = (r.stdout or "").strip()
        try:
            ok = bool(json.loads(body).get("ok"))
        except Exception:
            ok = False
        return ok, body or (r.stderr or "").strip()
    except Exception as e:
        return False, f"curl exception: {e}"


def send_message(tg, chat, text, markdown=True):
    args = ["-X", "POST", f"https://api.telegram.org/bot{tg}/sendMessage",
            "--data-urlencode", f"chat_id={chat}"]
    if markdown:
        args += ["--data-urlencode", "parse_mode=Markdown"]
    args += ["--data-urlencode", f"text={text}"]
    ok, body = curl(args, 60)
    if not ok and markdown:
        # a stray Markdown control char in dynamic text must not lose the report:
        # retry once as plain text
        return send_message(tg, chat, text, markdown=False)
    return ok, body


def send_document(tg, chat, path, caption):
    ok, body = curl(["-X", "POST", f"https://api.telegram.org/bot{tg}/sendDocument",
                     "-F", f"chat_id={chat}",
                     "-F", f"document=@{path}",
                     "-F", f"caption={caption}"], 120)
    return ok, body


def marker(spool, name):
    return os.path.join(spool, name + ".sent")


def main():
    if len(sys.argv) < 3:
        log("usage: send_batch.py <sweep_id> <deadline_epoch> — nothing sent")
        return
    sweep_id = sys.argv[1]
    try:
        deadline = int(float(sys.argv[2]))
    except ValueError:
        log(f"bad deadline '{sys.argv[2]}' — sending immediately, marked late-unknown")
        deadline = now()

    spool = os.path.join(ROOT, "output", ".batch", sweep_id)
    if not os.path.isdir(spool):
        log(f"no spool dir {spool} — nothing to deliver (not a defer sweep?)")
        return

    # ---- the barrier: wait for the deadline ----------------------------------
    wait = deadline - now()
    if wait > 0:
        log(f"sweep {sweep_id}: chain done early — holding batch {wait}s until "
            f"{datetime.fromtimestamp(deadline).strftime('%H:%M:%S')}")
        while True:
            remaining = deadline - now()
            if remaining <= 0:
                break
            time.sleep(min(remaining, 60))
        log(f"sweep {sweep_id}: woke at deadline — releasing batch")

    late_secs = now() - deadline
    late_note = f" (late by {max(1, round(late_secs / 60))}m)" if late_secs > 60 else ""
    if late_secs > 60:
        log(f"sweep {sweep_id}: LATE path — chain overran deadline by "
            f"{round(late_secs / 60)}m, sending immediately")

    # ---- load spooled records (schema v1) -----------------------------------
    # Load after the barrier so off-box collectors that land while send_batch is
    # sleeping (Blinkit/Mac, Swiggy, etc.) still join the deadline batch.
    records = {}
    for p in platforms():
        f = os.path.join(spool, p + ".json")
        if os.path.exists(f + ".sent"):
            records[p] = {"platform": p, "_already_sent": True}
            continue
        if not os.path.isfile(f):
            continue                       # not spooled: already delivered or absent — never resend
        try:
            with open(f, encoding="utf-8") as fh:
                records[p] = json.load(fh)
        except Exception as e:
            log(f"OWNER-ALERT: spool file for {p} unreadable ({e}) — left in place")

    ok_ps = [p for p in platforms() if records.get(p, {}).get("verdict") == "OK"
             or records.get(p, {}).get("_already_sent")]
    held_ps = [p for p in platforms()
               if records.get(p, {}).get("held") and not records[p].get("_already_sent")]
    missing_ps = [p for p in platforms() if p not in records]

    # ---- creds ----------------------------------------------------------------
    sec = read_secrets()
    tg = sec.get("TELEGRAM_BOT_TOKEN", "")
    ch = sec.get("TELEGRAM_CHAT_ID", "")
    if not tg or not ch:
        log(f"OWNER-ALERT: no Telegram creds in secrets.env — batch {sweep_id} NOT sent; "
            f"spool kept at {spool} for manual resend")
        return

    slot = datetime.fromtimestamp(deadline).strftime("%H:%M")
    failures = 0

    # ---- header ----------------------------------------------------------------
    n_total = len(platforms())
    header = (f"\U0001F4E6 Jivo sweep {slot} IST{late_note} — {n_total} platforms, "
              f"{len(ok_ps)} reports, {len(held_ps)} held")
    if not os.path.exists(marker(spool, ".header")):
        ok, body = send_message(tg, ch, header, markdown=False)
        log(f"{sweep_id} header -> {body[:200]}")
        if ok:
            open(marker(spool, ".header"), "w").close()
        else:
            failures += 1

    # ---- each platform, canonical order ----------------------------------------
    for p in platforms():
        rec = records.get(p)
        if not rec or rec.get("_already_sent") or rec.get("verdict") != "OK":
            continue
        xlsx = rec.get("xlsx") or ""
        summary = rec.get("summary") or f"*Jivo {p}*\nReport attached."
        caption = rec.get("caption") or f"Jivo × {p}"

        ok1, body1 = send_message(tg, ch, summary, markdown=True)
        log(f"{sweep_id} {p} sendMessage  -> {body1[:200]}")
        ok2 = True
        if xlsx and os.path.isfile(xlsx):
            ok2, body2 = send_document(tg, ch, xlsx, caption)
            log(f"{sweep_id} {p} sendDocument -> {body2[:200]}")
        else:
            log(f"OWNER-ALERT: {p} spooled xlsx missing on disk ({xlsx!r}) — summary only")

        if ok1 and ok2:
            try:                                   # mark sent -> resume-safe
                os.rename(os.path.join(spool, p + ".json"),
                          os.path.join(spool, p + ".json.sent"))
            except OSError:
                open(marker(spool, p + ".json"), "w").close()
        else:
            failures += 1
            log(f"OWNER-ALERT: {p} batch send FAILED — file kept in spool for resume "
                f"(re-run: python3 tools/cron/send_batch.py {sweep_id} {deadline})")

    # ---- footer -----------------------------------------------------------------
    foot = []
    if held_ps:
        foot.append("Held back (review verdict, owner already alerted): " + ", ".join(
            f"{p} [{records[p].get('verdict', '?')}]" for p in held_ps))
    if missing_ps:
        foot.append("Not in this batch (delivered separately or no report): "
                    + ", ".join(missing_ps))
    if late_secs > 60:
        foot.append(f"Chain overran the {slot} deadline by {round(late_secs / 60)}m.")
    if foot and not os.path.exists(marker(spool, ".footer")):
        ok, body = send_message(tg, ch, "\n".join(foot), markdown=False)
        log(f"{sweep_id} footer -> {body[:200]}")
        if ok:
            open(marker(spool, ".footer"), "w").close()
        else:
            failures += 1

    # ---- retire the spool dir (idempotency) --------------------------------------
    if failures == 0:
        dest = os.path.join(ROOT, "output", ".batch", "sent-" + sweep_id)
        i = 1
        while os.path.exists(dest):
            i += 1
            dest = os.path.join(ROOT, "output", ".batch", f"sent-{sweep_id}-{i}")
        try:
            os.rename(spool, dest)
            log(f"sweep {sweep_id}: batch delivered ({len(ok_ps)} reports, "
                f"{len(held_ps)} held, {len(missing_ps)} missing){late_note} -> {dest}")
        except OSError as e:
            log(f"spool retire failed ({e}) — markers prevent any resend")
    else:
        log(f"OWNER-ALERT: sweep {sweep_id} finished with {failures} send failure(s); "
            f"spool kept at {spool} — re-run send_batch.py to resume")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:                                    # absolute fail-safe
        log(f"OWNER-ALERT: send_batch crashed: {e}")
    sys.exit(0)
