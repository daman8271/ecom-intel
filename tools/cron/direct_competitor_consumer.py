#!/usr/bin/env python3
"""Validate and promote final Mac-built competitor packages only.

This consumer never accepts endpoint shards and never performs capture, merge, or
workbook construction.  Its accepted receipt is the delivery authorization.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from typing import Any

from openpyxl import load_workbook


IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
HEX64 = re.compile(r"^[0-9a-f]{64}$")
RUN_ID = re.compile(
    r"^(?P<day>[0-9]{8})-[0-9]{6}-(?P<platform>blinkit|zepto)-competitor-direct-a[0-9]{2}$"
)
SCHEMA = "jivo-direct-competitor-report-receipt-v1"
PROMOTION_SCHEMA = "jivo-direct-competitor-promotion-receipt-v1"
FAILURE_SCHEMA = "jivo-direct-competitor-failure-receipt-v1"
FAILURE_ACCEPTED_SCHEMA = "jivo-direct-competitor-failure-accepted-v1"

PLATFORM = {
    "blinkit": {
        "workflow": "blinkit-top8",
        "pins": 75,
        "label": "Blinkit",
        "sheets": ["Summary", "City-Pin-SKU Prices", "Run Scope", "Anchor Watch", "Master Data"],
        "code": {
            "select_blinkit_top8_pincodes.py",
            "build_blinkit_top8_daily.py",
            "build_competitor_report.py",
        },
        "brands": {
            "borges", "del monte", "figaro", "fortune", "gulab",
            "hudson", "oreal", "saffola", "sundrop", "tata",
        },
    },
    "zepto": {
        "workflow": "zepto-competitor",
        "pins": 25,
        "label": "Zepto",
        "sheets": ["Summary", "Anchor Watch", "Master Data"],
        "code": {"build_competitor_report.py"},
    },
}

REQUIRED_SUPPORT = {
    "category_queries.json",
    "competitor_brands.json",
    "competitor_match_map.json",
    "maps_to_jivo.json",
    "oil_classifier.json",
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    with temp.open("w", encoding="ascii") as handle:
        json.dump(value, handle, indent=2, sort_keys=True, ensure_ascii=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, path)


def copy_fsync(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as incoming, target.open("wb") as outgoing:
        shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
        outgoing.flush()
        os.fsync(outgoing.fileno())


def normalized_brands(value: Any) -> list[str]:
    if not isinstance(value, list):
        raise ValueError("brand_set must be a list")
    brands = sorted({" ".join(str(item).split()).casefold() for item in value if str(item).strip()})
    if len(brands) != len(value):
        raise ValueError("brand_set contains blank or duplicate names")
    return brands


def brand_hash(brands: list[str]) -> str:
    raw = json.dumps(brands, ensure_ascii=True, separators=(",", ":")).encode("ascii")
    return hashlib.sha256(raw).hexdigest()


def valid_hash(value: Any) -> bool:
    return isinstance(value, str) and HEX64.fullmatch(value) is not None


def validate_hash_map(receipt: dict[str, Any], name: str) -> dict[str, str]:
    values = receipt.get(name)
    if not isinstance(values, dict) or set(values) != {"macpro", "windows"}:
        raise ValueError(f"{name} must bind macpro and windows")
    if any(not valid_hash(value) for value in values.values()):
        raise ValueError(f"{name} contains an invalid hash")
    return values


def validate_named_hashes(value: Any, field: str, required: set[str]) -> list[dict[str, str]]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field} manifest is missing")
    output: list[dict[str, str]] = []
    names: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            raise ValueError(f"{field} entry is invalid")
        name = item.get("name")
        digest = item.get("sha256")
        if not isinstance(name, str) or Path(name).name != name or name in names:
            raise ValueError(f"{field} name is unsafe or duplicated")
        if not valid_hash(digest):
            raise ValueError(f"{field} hash is invalid: {name}")
        names.add(name)
        output.append({"name": name, "sha256": digest})
    if not required.issubset(names):
        raise ValueError(f"{field} is missing required files: {sorted(required - names)}")
    return output


def expected_names(platform: str, date_ist: str) -> tuple[str, str]:
    spec = PLATFORM[platform]
    workbook = f"Competitor-Price-Watch-{spec['label']}-{date_ist}.xlsx"
    capture = f"{platform}_competitor_{date_ist}.json"
    return workbook, capture


def delivery_audit_name(platform: str, date_ist: str) -> str:
    if platform == "blinkit":
        return f"blinkit-top8-{date_ist}.audit.json"
    return f"zepto-competitor-{date_ist}.audit.json"


def validate_manifest_entry(value: Any, expected_name: str, field: str) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("name") != expected_name:
        raise ValueError(f"{field} name mismatch")
    if Path(expected_name).name != expected_name:
        raise ValueError(f"unsafe {field} name")
    if not isinstance(value.get("bytes"), int) or value["bytes"] <= 0 or not valid_hash(value.get("sha256")):
        raise ValueError(f"{field} size/hash is invalid")
    return {"name": expected_name, "bytes": value["bytes"], "sha256": value["sha256"]}


def verify_file(run_dir: Path, entry: dict[str, Any], minimum: int = 1) -> Path:
    path = run_dir / entry["name"]
    if path.is_symlink() or not path.is_file() or path.stat().st_size < minimum:
        raise ValueError(f"artifact missing or too small: {entry['name']}")
    if path.stat().st_size != entry["bytes"] or sha256_file(path) != entry["sha256"]:
        raise ValueError(f"artifact hash/size mismatch: {entry['name']}")
    return path


def validate_quality_policy(platform: str, policy: Any) -> dict[str, Any]:
    if not isinstance(policy, dict):
        raise ValueError("quality_policy is missing")
    if platform == "blinkit":
        exact = {
            "require_resolved": True,
            "require_auth": True,
            "require_rows_each_pincode": True,
        }
        if any(policy.get(key) != value for key, value in exact.items()):
            raise ValueError("Blinkit quality_policy is incomplete")
    elif float(policy.get("min_serviceable_pct") or 0) <= 0:
        raise ValueError("Zepto quality_policy has no serviceability floor")
    for key in ("min_rows_per_source_pincode", "min_unique_brands", "baseline_min_row_fraction", "baseline_min_brand_fraction"):
        if float(policy.get(key) or 0) <= 0:
            raise ValueError(f"quality_policy has no positive {key}")
    return policy


def validate_capture(path: Path, receipt: dict[str, Any], platform: str) -> dict[str, Any]:
    capture = load_json(path)
    if not isinstance(capture, dict):
        raise ValueError("merged capture is not an object")
    summary = capture.get("summary")
    rows = capture.get("allRows")
    if not isinstance(summary, dict) or not isinstance(rows, list) or not rows:
        raise ValueError("merged capture summary/allRows is invalid")
    checks = {
        "mode": summary.get("mode") == "competitor",
        "platform": summary.get("platform") == platform,
        "date": summary.get("date_ist") == receipt["date_ist"],
        "run": summary.get("run_id") == receipt["run_id"],
        "pins": summary.get("pincodes_total") == PLATFORM[platform]["pins"],
        "rows": summary.get("total_rows") == len(rows) == receipt["total_rows"],
        "partial": summary.get("partial") is False and int(summary.get("pincodes_blocked") or 0) == 0,
    }
    if not all(checks.values()):
        raise ValueError(f"merged capture identity/quality failed: {checks}")
    row_pins = {str(row.get("pincode") or "").strip() for row in rows}
    row_pins.discard("")
    if platform == "blinkit":
        if len(row_pins) != 75 or summary.get("pincodes_resolved") != 75 \
           or summary.get("auth_verified") != 1 or summary.get("auth_verified_pincodes") != 75:
            raise ValueError("Blinkit capture is not 75/75 resolved and authenticated")
    else:
        minimum = math.ceil(PLATFORM[platform]["pins"] * float(receipt["quality_policy"]["min_serviceable_pct"]) / 100)
        if int(summary.get("pincodes_serviceable") or 0) < minimum:
            raise ValueError("Zepto capture is below the serviceability floor")
    return capture


def validate_workbook(path: Path, platform: str, receipt: dict[str, Any]) -> None:
    workbook = load_workbook(path, read_only=True, data_only=False)
    try:
        expected = PLATFORM[platform]["sheets"]
        if workbook.sheetnames != expected:
            raise ValueError(f"workbook sheets mismatch: {workbook.sheetnames}")
        if workbook["Master Data"].max_row - 1 != receipt["total_rows"]:
            raise ValueError("workbook Master Data row count mismatch")
        if platform == "blinkit" and workbook["Run Scope"].max_row != 82:
            raise ValueError("Blinkit Run Scope row count mismatch")
    finally:
        workbook.close()


def validate_audits(
    run_dir: Path,
    receipt: dict[str, Any],
    platform: str,
    workbook: dict[str, Any],
    capture: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    values = receipt.get("audits")
    if not isinstance(values, list) or not values:
        raise ValueError("audits manifest is missing")
    verified: list[dict[str, Any]] = []
    names: set[str] = set()
    parsed: dict[str, dict[str, Any]] = {}
    for value in values:
        if not isinstance(value, dict) or not isinstance(value.get("name"), str):
            raise ValueError("audit manifest entry is invalid")
        name = value["name"]
        if Path(name).name != name or name in names:
            raise ValueError("audit name is unsafe or duplicated")
        entry = validate_manifest_entry(value, name, "audit")
        path = verify_file(run_dir, entry)
        try:
            audit = load_json(path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            raise ValueError(f"audit is not valid JSON: {name}") from exc
        if not isinstance(audit, dict):
            raise ValueError(f"audit is not an object: {name}")
        names.add(name)
        parsed[name] = audit
        verified.append(entry)
    required_name = delivery_audit_name(platform, receipt["date_ist"])
    if required_name not in parsed:
        raise ValueError(f"required delivery audit is missing: {required_name}")
    audit = parsed[required_name]
    brands = receipt["brand_set"]
    common = {
        "brands": audit.get("brand_set") == brands,
        "brand_count": audit.get("brand_set_count") == len(brands),
        "brand_hash": audit.get("brand_set_sha256") == receipt["brand_set_sha256"],
    }
    if platform == "blinkit":
        summary = audit.get("summary") or {}
        common.update({
            "date": audit.get("date") == receipt["date_ist"],
            "pins": summary.get("pincodes_total") == 75 and summary.get("pincodes_resolved") == 75,
            "auth": summary.get("auth_verified") == 1 and summary.get("auth_verified_pincodes") == 75,
            "partial": summary.get("partial") is False,
            "rows": summary.get("total_rows") == receipt["total_rows"],
            "capture": audit.get("capture_sha256") == receipt["merged_capture"]["sha256"],
            "workbook": audit.get("workbook_sha256") == workbook["sha256"],
        })
    else:
        common.update({
            "schema": audit.get("schema") == "jivo-direct-competitor-quality-audit-v1",
            "platform": audit.get("platform") == platform,
            "workflow": audit.get("workflow_kind") == receipt["workflow_kind"],
            "date": audit.get("date_ist") == receipt["date_ist"],
            "run": audit.get("run_id") == receipt["run_id"],
            "status": audit.get("status") == "OK",
            "capture": audit.get("merged_sha256") == receipt["merged_capture"]["sha256"],
            "workbook": audit.get("workbook_sha256") == workbook["sha256"],
        })
    if not all(common.values()):
        raise ValueError(f"delivery audit provenance/quality failed: {common}")
    del capture
    return verified, next(item for item in verified if item["name"] == required_name)


def acknowledge(receipt_path: Path, run_id: str, host: str, root: str) -> str:
    if not host:
        return "disabled"
    remote = f"{root.rstrip('/')}/{run_id}.json"
    root_q, part_q, remote_q = map(shlex.quote, (root, f"{remote}.part", remote))
    try:
        subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host, f"mkdir -p -- {root_q}"],
            check=True, timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["scp", "-q", "-o", "BatchMode=yes", str(receipt_path), f"{host}:{part_q}"],
            check=True, timeout=60, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["ssh", "-o", "BatchMode=yes", host, f"mv -- {part_q} {remote_q}"],
            check=True, timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return "accepted"
    except (OSError, subprocess.SubprocessError):
        return "pending"


def acknowledge_once(receipt_path: Path, run_id: str, host: str, root: str) -> str:
    marker = receipt_path.with_suffix(".promotion-acked.json")
    if marker.is_file():
        return "accepted"
    status = acknowledge(receipt_path, run_id, host, root)
    if status == "accepted":
        atomic_json(marker, {"status": status, "run_id": run_id})
    return status


def destination_manifest(
    output_dir: Path,
    data_dir: Path,
    audit_dir: Path,
    platform: str,
    date_ist: str,
    workbook: dict[str, Any],
    capture: dict[str, Any],
    delivery_audit: dict[str, Any],
) -> list[dict[str, Any]]:
    values = [
        {**workbook, "kind": "workbook", "destination": str((output_dir / workbook["name"]).resolve())},
        {**capture, "kind": "merged_capture", "destination": str((data_dir / capture["name"]).resolve())},
    ]
    target = audit_dir / delivery_audit_name(platform, date_ist)
    values.append({**delivery_audit, "kind": "delivery_audit", "destination": str(target.resolve())})
    return values


def restore_or_verify(run_dir: Path, artifacts: list[dict[str, Any]]) -> int:
    restored = 0
    for item in artifacts:
        destination = Path(item["destination"])
        if destination.exists():
            if destination.is_symlink() or sha256_file(destination) != item["sha256"]:
                raise ValueError(f"accepted destination hash changed: {destination}")
            continue
        source = run_dir / item["name"]
        if not source.is_file() or sha256_file(source) != item["sha256"]:
            raise ValueError(f"accepted artifact cannot be restored: {item['name']}")
        temp = destination.with_name(f".{destination.name}.restore.part")
        try:
            copy_fsync(source, temp)
            if sha256_file(temp) != item["sha256"]:
                raise ValueError(f"restored hash mismatch: {item['name']}")
            os.replace(temp, destination)
            restored += 1
        finally:
            temp.unlink(missing_ok=True)
    return restored


def consume_run(
    run_dir: Path,
    date_ist: str,
    output_dir: Path,
    data_dir: Path,
    audit_dir: Path,
    receipt_root: Path,
    stable_age: int,
    ack_host: str,
    ack_root: str,
) -> tuple[str, str]:
    source_receipt = run_dir / "report.ready.json"
    age = dt.datetime.now().timestamp() - source_receipt.stat().st_mtime
    if age < stable_age:
        return "waiting", f"receipt is only {int(age)}s old"
    if run_dir.is_symlink() or source_receipt.is_symlink():
        raise ValueError("symlinked inbox paths are prohibited")
    match = RUN_ID.fullmatch(run_dir.name)
    if not match:
        raise ValueError("unsafe competitor run_id")
    receipt_bytes = source_receipt.read_bytes()
    receipt_sha = hashlib.sha256(receipt_bytes).hexdigest()
    receipt = json.loads(receipt_bytes.decode("utf-8-sig"))
    platform = match.group("platform")
    spec = PLATFORM[platform]
    expected = {
        "schema": SCHEMA,
        "platform": platform,
        "workflow_kind": spec["workflow"],
        "date_ist": date_ist,
        "run_id": run_dir.name,
        "status": "ready",
        "review_verdict": "OK",
        "pincodes_total": spec["pins"],
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            raise ValueError(f"competitor receipt mismatch: {key}")
    if match.group("day") != date_ist.replace("-", "") or not str(receipt.get("attempt_id") or ""):
        raise ValueError("competitor run date/attempt identity is invalid")
    for field in ("plan_sha256", "source_sha256", "scraper_sha256", "merge_receipt_sha256"):
        if not valid_hash(receipt.get(field)):
            raise ValueError(f"{field} is missing or invalid")
    if not isinstance(receipt.get("total_rows"), int) or receipt["total_rows"] <= 0:
        raise ValueError("total_rows is invalid")
    receipt["quality_policy"] = validate_quality_policy(platform, receipt.get("quality_policy"))
    validate_hash_map(receipt, "input_result_sha256")
    validate_hash_map(receipt, "input_progress_sha256")
    validate_hash_map(receipt, "input_terminal_sha256")
    validate_named_hashes(receipt.get("support_files"), "support_files", REQUIRED_SUPPORT)
    validate_named_hashes(receipt.get("code_files"), "code_files", spec["code"])

    brands = normalized_brands(receipt.get("brand_set"))
    if len(brands) != receipt.get("brand_set_count") or brand_hash(brands) != receipt.get("brand_set_sha256"):
        raise ValueError("brand_set count/hash mismatch")
    if {"jivo", "sano"} & set(brands):
        raise ValueError("brand_set must be rival-only")
    if platform == "blinkit" and set(brands) != spec["brands"]:
        raise ValueError("Blinkit approved rival brand set mismatch")
    if platform == "zepto" and len(brands) < 8:
        raise ValueError("Zepto rival brand set is unexpectedly small")
    receipt["brand_set"] = brands

    workbook_name, capture_name = expected_names(platform, date_ist)
    workbooks = receipt.get("workbooks")
    if not isinstance(workbooks, list) or len(workbooks) != 1:
        raise ValueError("workbooks manifest must contain exactly one workbook")
    workbook = validate_manifest_entry(workbooks[0], workbook_name, "workbook")
    capture_entry = validate_manifest_entry(receipt.get("merged_capture"), capture_name, "merged_capture")
    if receipt.get("merged_sha256") != capture_entry["sha256"] or receipt.get("merged_bytes") != capture_entry["bytes"]:
        raise ValueError("legacy merged hash/size fields disagree with merged_capture")
    workbook_path = verify_file(run_dir, workbook, minimum=10_000)
    capture_path = verify_file(run_dir, capture_entry)
    capture = validate_capture(capture_path, receipt, platform)
    validate_workbook(workbook_path, platform, receipt)
    audits, delivery_audit = validate_audits(run_dir, receipt, platform, workbook, capture)
    artifacts = destination_manifest(
        output_dir, data_dir, audit_dir, platform, date_ist,
        workbook, capture_entry, delivery_audit,
    )

    accepted_path = receipt_root / date_ist / f"{run_dir.name}.json"
    if accepted_path.is_file():
        if accepted_path.is_symlink():
            raise ValueError("symlinked accepted promotion is prohibited")
        accepted = load_json(accepted_path)
        if accepted.get("schema") != PROMOTION_SCHEMA or accepted.get("source_receipt_sha256") != receipt_sha:
            raise ValueError("accepted promotion conflicts with source receipt")
        if accepted.get("artifacts") != artifacts:
            raise ValueError("accepted promotion artifact manifest changed")
        restored = restore_or_verify(run_dir, artifacts)
        ack = acknowledge_once(accepted_path, run_dir.name, ack_host, ack_root)
        return "existing", f"already accepted; restored={restored}; Mac acknowledgement={ack}"

    for item in artifacts:
        destination = Path(item["destination"])
        if destination.exists() and (destination.is_symlink() or sha256_file(destination) != item["sha256"]):
            raise ValueError(f"refusing to overwrite different competitor artifact: {destination}")

    staged: list[tuple[Path, Path, str]] = []
    try:
        for item in artifacts:
            source = run_dir / item["name"]
            destination = Path(item["destination"])
            temp = destination.with_name(f".{destination.name}.direct-{run_dir.name}.part")
            copy_fsync(source, temp)
            if sha256_file(temp) != item["sha256"]:
                raise ValueError(f"staged hash mismatch: {item['name']}")
            staged.append((temp, destination, item["sha256"]))
        for temp, destination, expected_sha in staged:
            if destination.exists() and sha256_file(destination) != expected_sha:
                raise ValueError(f"destination changed during promotion: {destination}")
            os.replace(temp, destination)
    finally:
        for temp, _, _ in staged:
            temp.unlink(missing_ok=True)

    accepted = {
        "schema": PROMOTION_SCHEMA,
        "status": "accepted",
        "platform": platform,
        "workflow_kind": spec["workflow"],
        "date_ist": date_ist,
        "run_id": run_dir.name,
        "attempt_id": receipt["attempt_id"],
        "plan_sha256": receipt["plan_sha256"],
        "source_receipt_sha256": receipt_sha,
        "merged_sha256": capture_entry["sha256"],
        "brand_set_sha256": receipt["brand_set_sha256"],
        "artifacts": artifacts,
        "audits": audits,
        "accepted_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    atomic_json(accepted_path, accepted)
    ack = acknowledge_once(accepted_path, run_dir.name, ack_host, ack_root)
    return "accepted", f"promoted {len(artifacts)} artifact(s); Mac acknowledgement={ack}"


def consume_failure(source: Path, date_ist: str, failure_root: Path) -> tuple[str, dict[str, str]]:
    run_dir = source.parent
    match = RUN_ID.fullmatch(run_dir.name)
    if run_dir.is_symlink() or source.is_symlink() or not match:
        raise ValueError("unsafe competitor failure path")
    receipt = load_json(source)
    platform = match.group("platform")
    expected = {
        "schema": FAILURE_SCHEMA,
        "platform": platform,
        "workflow_kind": PLATFORM[platform]["workflow"],
        "date_ist": date_ist,
        "run_id": run_dir.name,
        "status": "failed",
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            raise ValueError(f"competitor failure receipt mismatch: {key}")
    if match.group("day") != date_ist.replace("-", "") or not str(receipt.get("attempt_id") or ""):
        raise ValueError("competitor failure date/attempt is invalid")
    if not valid_hash(receipt.get("plan_sha256")) or not str(receipt.get("phase") or "") \
       or not str(receipt.get("reason") or ""):
        raise ValueError("competitor failure provenance is incomplete")
    source_sha = sha256_file(source)
    target = failure_root / date_ist / f"{run_dir.name}.json"
    detail = {
        "run_id": run_dir.name,
        "platform": platform,
        "workflow_kind": PLATFORM[platform]["workflow"],
        "phase": str(receipt["phase"]),
        "reason": str(receipt["reason"]),
    }
    if target.is_file():
        if load_json(target).get("source_receipt_sha256") != source_sha:
            raise ValueError("accepted competitor failure receipt changed")
        return "existing", detail
    atomic_json(target, {
        "schema": FAILURE_ACCEPTED_SCHEMA,
        "status": "accepted",
        "date_ist": date_ist,
        "source_receipt_sha256": source_sha,
        **detail,
    })
    return "new", detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inbox", default="shards/mac-direct-competitor-ready")
    parser.add_argument("--output", default="output")
    parser.add_argument("--data", default="tools/competitor/data")
    parser.add_argument("--audit-dir", default="logs")
    parser.add_argument("--receipts", default="logs/direct-competitor-report-receipts")
    parser.add_argument("--failure-receipts", default="logs/direct-competitor-report-failures")
    parser.add_argument("--date", default=dt.datetime.now(IST).date().isoformat())
    parser.add_argument("--stable-age", type=int, default=30)
    parser.add_argument("--ack-host", default="macpro")
    parser.add_argument("--ack-root", default="/Users/danny./ecom-direct/receipts/competitor-promotion")
    args = parser.parse_args()

    inbox = Path(args.inbox)
    receipt_root = Path(args.receipts)
    summary: dict[str, Any] = {
        "date": args.date, "new": 0, "existing": 0, "waiting": 0,
        "rejected": 0, "endpoint_failures": [], "errors": [],
    }
    if inbox.exists():
        for source in sorted(inbox.glob("*/report.ready.json")):
            run_dir = source.parent
            if not run_dir.name.startswith(args.date.replace("-", "")):
                continue
            rejection = receipt_root / args.date / "rejected" / f"{hashlib.sha256(run_dir.name.encode()).hexdigest()}.json"
            try:
                source_sha = sha256_file(source)
            except OSError:
                source_sha = "unreadable"
            if rejection.is_file():
                try:
                    if load_json(rejection).get("source_receipt_sha256") == source_sha:
                        summary["rejected"] += 1
                        continue
                except (OSError, ValueError, json.JSONDecodeError):
                    pass
            try:
                status, message = consume_run(
                    run_dir, args.date, Path(args.output), Path(args.data), Path(args.audit_dir),
                    receipt_root, args.stable_age, args.ack_host, args.ack_root,
                )
                summary["new" if status == "accepted" else status] += 1
                print(f"{run_dir.name}: {status}: {message}", file=sys.stderr)
            except Exception as exc:
                summary["errors"].append({"run_id": run_dir.name, "error": str(exc)})
                print(f"{run_dir.name}: rejected: {exc}", file=sys.stderr)
                atomic_json(rejection, {
                    "schema": "jivo-direct-competitor-rejection-v1",
                    "run_id": run_dir.name,
                    "source_receipt_sha256": source_sha,
                    "error": str(exc),
                })
        for source in sorted(inbox.glob("*/failure.json")):
            if not source.parent.name.startswith(args.date.replace("-", "")):
                continue
            try:
                status, detail = consume_failure(source, args.date, Path(args.failure_receipts))
                if status == "new":
                    summary["endpoint_failures"].append(detail)
            except Exception as exc:
                summary["errors"].append({"run_id": source.parent.name, "error": str(exc)})
                print(f"{source.parent.name}: rejected failure receipt: {exc}", file=sys.stderr)

    for accepted in (receipt_root / args.date).glob("*.json"):
        try:
            value = load_json(accepted)
            run_id = str(value.get("run_id") or "")
            if value.get("schema") == PROMOTION_SCHEMA and RUN_ID.fullmatch(run_id):
                acknowledge_once(accepted, run_id, args.ack_host, args.ack_root)
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
    print(json.dumps(summary, sort_keys=True))
    return 1 if summary["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
