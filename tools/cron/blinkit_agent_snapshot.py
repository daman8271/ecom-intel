#!/usr/bin/env python3
"""Compact production snapshot for the Blinkit agent hook.

This script is intentionally read-only. It summarizes the current Blinkit run,
latest fallback shards, report files, sent markers, and the exact bad pincodes
that would require targeted auth/OOS repair.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path("/opt/ecom-intel")
IST = dt.timezone(dt.timedelta(hours=5, minutes=30))


def read_json(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def file_info(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"path": str(path), "exists": False, "size": 0, "mtime": None}
    st = path.stat()
    return {
        "path": str(path),
        "exists": True,
        "size": st.st_size,
        "mtime": dt.datetime.fromtimestamp(st.st_mtime, IST).isoformat(),
    }


def flag(value: Any) -> bool:
    if value is True:
        return True
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value == 1
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def pincode(value: Any) -> str:
    return str(value or "").strip()


def bad_pins(result: dict[str, Any]) -> list[str]:
    bad: set[str] = set()
    for rec in result.get("perPin") or []:
        if not isinstance(rec, dict):
            continue
        pin = pincode(rec.get("pincode"))
        if pin and not flag(rec.get("auth_accepted")):
            bad.add(pin)
    for row in result.get("allRows") or []:
        if not isinstance(row, dict):
            continue
        pin = pincode(row.get("pincode"))
        if not pin:
            continue
        stock_source = str(row.get("stock_source") or "").strip().lower()
        if row.get("pdp_price_probe_failed"):
            bad.add(pin)
        if not row.get("in_stock") and not row.get("pdp_checked") and stock_source not in {"pdp", "pdp_probe"}:
            bad.add(pin)
    return sorted(bad)


def summarize_result(path: Path) -> dict[str, Any]:
    data = read_json(path)
    info = file_info(path)
    if not isinstance(data, dict):
        return {**info, "readable": False, "summary": {}, "bad_pins": []}
    summary = data.get("summary") or {}
    per_pin = [r for r in (data.get("perPin") or []) if isinstance(r, dict)]
    rows = [r for r in (data.get("allRows") or []) if isinstance(r, dict)]
    resolved = [r for r in per_pin if flag(r.get("resolved"))]
    store_counts: dict[str, int] = {}
    for rec in resolved:
        store = str(rec.get("store_id") or "").strip()
        if store:
            store_counts[store] = store_counts.get(store, 0) + 1
    top_store_share = max(store_counts.values()) / len(resolved) if resolved and store_counts else 0.0
    return {
        **info,
        "readable": True,
        "summary": {
            k: summary.get(k)
            for k in (
                "captured_at",
                "started_at",
                "scraper_sha256",
                "pincodes_total",
                "pincodes_resolved",
                "pincodes_unresolved",
                "pincodes_with_jivo",
                "total_rows",
                "unique_skus",
                "wall_s",
                "shard_wall_s_total",
                "auth_session",
                "auth_required",
                "auth_verified",
                "auth_verified_pincodes",
                "unverified_oos",
                "pdp_price_probe_checked",
                "pdp_price_probe_failed",
                "pdp_price_probe_enabled",
                "oos_probe_enabled",
                "pdp_oos_probe_enabled",
                "merged_shards",
            )
        },
        "per_pin_count": len(data.get("perPin") or []),
        "row_count": len(data.get("allRows") or []),
        "run_health": {
            "resolved_rate": len(resolved) / len(per_pin) if per_pin else 0.0,
            "auth_rate": sum(1 for r in per_pin if flag(r.get("auth_accepted"))) / len(per_pin) if per_pin else 0.0,
            "distinct_resolved_stores": len(store_counts),
            "top_store_share": top_store_share,
            "price_evidence_complete": all(
                key in summary for key in (
                    "pdp_price_probe_attempted", "pdp_price_probe_checked",
                    "pdp_price_probe_failed")
            ),
        },
        "bad_pins": bad_pins(data),
    }


def expected_pincodes() -> int:
    data = read_json(ROOT / "platforms/blinkit/pincodes.daily.json")
    return len(data) if isinstance(data, list) else 0


def latest_fallback_runs(limit: int = 3) -> list[dict[str, Any]]:
    base = ROOT / "shards/runs"
    dirs = [p for p in base.glob("*blinkit-vps-kvm*") if p.is_dir()]
    dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    out = []
    for run in dirs[:limit]:
        bdir = run / "blinkit"
        shards = []
        for result in sorted(bdir.glob("shard-*-of-*/result.json")):
            shards.append(summarize_result(result))
        out.append(
            {
                "run_id": run.name,
                "path": str(run),
                "mtime": dt.datetime.fromtimestamp(run.stat().st_mtime, IST).isoformat(),
                "merged": summarize_result(bdir / "merged-result.json"),
                "shards": shards,
            }
        )
    return out


def latest_mac_drop(date_ist: str) -> dict[str, Any]:
    compact = date_ist.replace("-", "")
    base = ROOT / "platforms/blinkit/mac-drops"
    paths = list(base.glob(f"blinkit-{compact}-*.json")) + list(base.glob(f"blinkit-{compact}T*.json"))
    paths = [p for p in paths if p.is_file()]
    paths.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    if not paths:
        return {"exists": False, "path": str(base), "summary": {}, "bad_pins": []}
    return summarize_result(paths[0])


def local_blinkit_processes() -> list[str]:
    try:
        proc = subprocess.run(
            ["ps", "-eo", "pid,etime,command"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return []
    lines = []
    needles = (
        "blinkit_vps_kvm_fallback.sh",
        "run_platform_shard.sh blinkit",
        "platforms/blinkit/scrape.js",
        "blinkit_today_supervisor.sh",
    )
    for line in proc.stdout.splitlines():
        if any(n in line for n in needles) and "blinkit_agent_snapshot.py" not in line:
            lines.append(line.strip())
    return lines[:30]


def derive_state(now: dt.datetime, date_ist: str, reports: dict[str, Any], result: dict[str, Any], fallback_runs: list[dict[str, Any]], processes: list[str], mac_drop: dict[str, Any]) -> str:
    main_exists = reports["main"]["exists"]
    not_listed_exists = reports["not_listed"]["exists"]
    main_sent = reports["main_sent"]["exists"]
    not_listed_sent = reports["not_listed_sent"]["exists"]
    if main_exists and not_listed_exists and main_sent and not_listed_sent:
        return "complete"
    if main_exists and not_listed_exists:
        return "accepted_pending_send"
    if processes:
        return "running"
    mac_summary = mac_drop.get("summary") or {}
    if mac_drop.get("exists") and (
        mac_drop.get("bad_pins")
        or mac_summary.get("auth_verified") != 1
        or int(mac_summary.get("unverified_oos") or 0) > 0
        or int(mac_summary.get("pdp_price_probe_failed") or 0) > 0
    ):
        return "quality_hold"
    latest_bad: list[str] = []
    if fallback_runs:
        merged = fallback_runs[0].get("merged") or {}
        latest_bad = merged.get("bad_pins") or []
        ms = merged.get("summary") or {}
        if ms and (ms.get("auth_verified") != 1 or int(ms.get("unverified_oos") or 0) > 0 or int(ms.get("pdp_price_probe_failed") or 0) > 0):
            return "quality_hold"
    rs = result.get("summary") or {}
    if result.get("exists") and rs and rs.get("captured_at"):
        captured = str(rs.get("captured_at") or "")
        if date_ist not in captured and not (main_exists and not_listed_exists):
            pass
    if latest_bad:
        return "quality_hold"
    cutoff = now.replace(hour=10, minute=0, second=0, microsecond=0)
    if now >= cutoff and not (main_exists and not_listed_exists):
        return "missing_after_1000"
    return "waiting"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=os.environ.get("BLINKIT_AGENT_DATE"))
    args = ap.parse_args()

    now = dt.datetime.now(IST)
    date_ist = args.date or now.date().isoformat()
    reports = {
        "main": file_info(ROOT / "output" / f"Jivo-Blinkit-Live-Report-{date_ist}.xlsx"),
        "not_listed": file_info(ROOT / "output" / f"Jivo-Blinkit-Not-Listed-Pincodes-{date_ist}.xlsx"),
        "main_sent": file_info(ROOT / "logs" / f"blinkit-main-wa-{date_ist}.sent"),
        "not_listed_sent": file_info(ROOT / "logs" / f"blinkit-not-listed-wa-{date_ist}.sent"),
    }
    fallback_runs = latest_fallback_runs()
    mac_drop = latest_mac_drop(date_ist)
    result = summarize_result(ROOT / "platforms/blinkit/result.json")
    processes = local_blinkit_processes()
    snapshot = {
        "date_ist": date_ist,
        "now_ist": now.isoformat(),
        "expected_pincodes": expected_pincodes(),
        "reports": reports,
        "result": result,
        "latest_mac_drop": mac_drop,
        "latest_fallback_runs": fallback_runs,
        "local_blinkit_processes": processes,
    }
    snapshot["state"] = derive_state(now, date_ist, reports, result, fallback_runs, processes, mac_drop)
    print(json.dumps(snapshot, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
