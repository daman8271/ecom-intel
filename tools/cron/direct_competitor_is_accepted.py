#!/usr/bin/env python3
"""Snapshot an exact accepted competitor promotion for delivery."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
from typing import Any


SNAPSHOT_SCHEMA = "jivo-direct-competitor-accepted-snapshot-v1"
ARTIFACT_KINDS = {"workbook", "merged_capture", "delivery_audit"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
BLINKIT_BRANDS = {
    "borges", "del monte", "figaro", "fortune", "gulab",
    "hudson", "oreal", "saffola", "sundrop", "tata",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_artifacts(value: dict[str, Any]) -> list[dict[str, Any]]:
    artifacts = value.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 3:
        raise ValueError("promotion must contain exactly three artifacts")
    if any(not isinstance(item, dict) for item in artifacts):
        raise ValueError("promotion artifact is not an object")
    kinds = [item.get("kind") for item in artifacts]
    if set(kinds) != ARTIFACT_KINDS or len(set(kinds)) != 3:
        raise ValueError("promotion artifact kinds are incomplete or duplicated")
    for item in artifacts:
        if not isinstance(item.get("destination"), str) or not item["destination"]:
            raise ValueError("promotion artifact destination is missing")
        if not isinstance(item.get("bytes"), int) or item["bytes"] < 1:
            raise ValueError("promotion artifact byte count is invalid")
        if not isinstance(item.get("sha256"), str) or not SHA256_RE.fullmatch(item["sha256"]):
            raise ValueError("promotion artifact hash is invalid")
    return artifacts


def valid_sha(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def checked_promotion(value: dict[str, Any], platform: str, run_id: str) -> None:
    attempt_match = re.search(r"-a([0-9]{2})$", run_id)
    if attempt_match is None or value.get("attempt_id") != attempt_match.group(1):
        raise ValueError("promotion attempt identity is invalid")
    for field in (
        "plan_sha256", "source_sha256", "scraper_sha256", "merge_receipt_sha256",
        "source_receipt_sha256", "merged_sha256", "brand_set_sha256",
    ):
        if not valid_sha(value.get(field)):
            raise ValueError(f"promotion provenance hash is invalid: {field}")
    for field in ("input_result_sha256", "input_progress_sha256", "input_terminal_sha256"):
        hashes = value.get(field)
        if not isinstance(hashes, dict) or set(hashes) != {"macpro", "windows"} \
           or any(not valid_sha(item) for item in hashes.values()):
            raise ValueError(f"promotion endpoint hash map is invalid: {field}")
    for field in ("support_files", "code_files"):
        manifest = value.get(field)
        if not isinstance(manifest, list) or not manifest \
           or any(not isinstance(item, dict) or not valid_sha(item.get("sha256")) for item in manifest):
            raise ValueError(f"promotion manifest is invalid: {field}")
    brands = value.get("brand_set")
    if not isinstance(brands, list) or any(not isinstance(item, str) for item in brands) \
       or brands != sorted(set(brands)) \
       or value.get("brand_set_count") != len(brands):
        raise ValueError("promotion reviewed brand set is invalid")
    brand_payload = json.dumps(brands, ensure_ascii=True, separators=(",", ":")).encode("ascii")
    if hashlib.sha256(brand_payload).hexdigest() != value["brand_set_sha256"]:
        raise ValueError("promotion reviewed brand hash is invalid")
    expected_pins = 75 if platform == "blinkit" else 25
    if value.get("pincodes_total") != expected_pins or int(value.get("total_rows") or 0) <= 0:
        raise ValueError("promotion row/pincode counts are invalid")
    if not isinstance(value.get("quality_policy"), dict) or not isinstance(value.get("baseline"), dict):
        raise ValueError("promotion quality policy/baseline is missing")
    anchors = {" ".join(str(item).split()).casefold() for item in value.get("anchor_brands") or []}
    competitors = {" ".join(str(item).split()).casefold() for item in value.get("competitor_brands") or []}
    capture = {" ".join(str(item).split()).casefold() for item in value.get("capture_brands") or []}
    if anchors != {"jivo", "sano"} or competitors != set(brands) or capture != anchors | competitors:
        raise ValueError("promotion brand scope is invalid")
    if platform == "blinkit" and competitors != BLINKIT_BRANDS:
        raise ValueError("promotion Blinkit rival scope is invalid")
    if platform == "zepto" and len(competitors) < 8:
        raise ValueError("promotion Zepto rival scope is too small")


def snapshot_one(source: Path, destination: Path, expected_size: int, expected_sha: str) -> None:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    source_fd = os.open(source, flags)
    digest = hashlib.sha256()
    size = 0
    try:
        source_stat = os.fstat(source_fd)
        if not stat.S_ISREG(source_stat.st_mode):
            raise ValueError(f"accepted artifact is not a regular file: {source}")
        with destination.open("xb") as target:
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                target.write(chunk)
                digest.update(chunk)
                size += len(chunk)
            target.flush()
            os.fsync(target.fileno())
    finally:
        os.close(source_fd)
    if size != expected_size or digest.hexdigest() != expected_sha:
        raise ValueError(f"accepted artifact changed while snapshotting: {source}")
    destination.chmod(0o400)


def validate_snapshot(bundle: Path, artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    snapshots: list[dict[str, Any]] = []
    for item in artifacts:
        source = Path(item["destination"])
        snapshot = bundle / f"{item['kind']}-{source.name}"
        if snapshot.is_symlink() or not snapshot.is_file():
            raise ValueError(f"snapshot artifact is missing: {snapshot}")
        if snapshot.stat().st_size != item["bytes"] or sha256_file(snapshot) != item["sha256"]:
            raise ValueError(f"snapshot artifact hash/size mismatch: {snapshot}")
        snapshots.append({
            "kind": item["kind"],
            "original_path": str(source.absolute()),
            "snapshot_path": str(snapshot.resolve()),
            "bytes": item["bytes"],
            "sha256": item["sha256"],
        })
    return snapshots


def create_snapshot_bundle(
    snapshot_root: Path,
    date_ist: str,
    platform: str,
    run_id: str,
    receipt_sha256: str,
    artifacts: list[dict[str, Any]],
) -> tuple[Path, list[dict[str, Any]]]:
    parent = snapshot_root / date_ist / platform / run_id
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    bundle = parent / receipt_sha256
    if not bundle.exists():
        temporary = Path(tempfile.mkdtemp(prefix=f".{receipt_sha256}.", dir=parent))
        try:
            for item in artifacts:
                source = Path(item["destination"])
                if source.is_symlink():
                    raise ValueError(f"accepted artifact is symlinked: {source}")
                destination = temporary / f"{item['kind']}-{source.name}"
                snapshot_one(source, destination, item["bytes"], item["sha256"])
            os.chmod(temporary, 0o500)
            try:
                os.rename(temporary, bundle)
            except OSError:
                if not bundle.is_dir():
                    raise
        finally:
            if temporary.exists():
                os.chmod(temporary, 0o700)
                shutil.rmtree(temporary)
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError("snapshot bundle is not a real directory")
    return bundle, validate_snapshot(bundle, artifacts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--platform", choices=("blinkit", "zepto"), required=True)
    parser.add_argument("--receipts", default="logs/direct-competitor-report-receipts")
    parser.add_argument("--snapshot-root")
    args = parser.parse_args()

    candidate_input = Path(args.file)
    if candidate_input.is_symlink() or not candidate_input.is_file():
        return 1
    candidate = candidate_input.resolve()
    receipt_root = Path(args.receipts)
    snapshot_root = (
        Path(args.snapshot_root).resolve()
        if args.snapshot_root
        else (receipt_root.parent / "direct-competitor-send-snapshots").resolve()
    )
    workflow = "blinkit-top8" if args.platform == "blinkit" else "zepto-competitor"
    run_pattern = re.compile(
        rf"^{args.date.replace('-', '')}-[0-9]{{6}}-{args.platform}-competitor-direct-a[0-9]{{2}}$"
    )
    for path in sorted((receipt_root / args.date).glob("*.json")):
        try:
            if path.is_symlink():
                continue
            raw_receipt = path.read_bytes()
            value = json.loads(raw_receipt.decode("utf-8-sig"))
            run_id = value.get("run_id")
            if not all((
                value.get("schema") == "jivo-direct-competitor-promotion-receipt-v1",
                value.get("status") == "accepted",
                value.get("date_ist") == args.date,
                value.get("platform") == args.platform,
                value.get("workflow_kind") == workflow,
                isinstance(run_id, str) and run_pattern.fullmatch(run_id),
            )):
                continue
            checked_promotion(value, args.platform, run_id)
            artifacts = checked_artifacts(value)
            workbook = [item for item in artifacts if item["kind"] == "workbook"]
            if len(workbook) != 1 or Path(workbook[0]["destination"]).resolve() != candidate:
                continue
            receipt_sha256 = hashlib.sha256(raw_receipt).hexdigest()
            bundle, snapshots = create_snapshot_bundle(
                snapshot_root, args.date, args.platform, run_id, receipt_sha256, artifacts
            )
            # Rehash every immutable copy after the bundle is installed.
            snapshots = validate_snapshot(bundle, artifacts)
            print(json.dumps({
                "schema": SNAPSHOT_SCHEMA,
                "platform": args.platform,
                "date_ist": args.date,
                "run_id": run_id,
                "promotion_receipt": str(path.resolve()),
                "promotion_receipt_sha256": receipt_sha256,
                "snapshot_bundle": str(bundle.resolve()),
                "artifacts": snapshots,
            }, sort_keys=True))
            return 0
        except (OSError, TypeError, ValueError, json.JSONDecodeError, UnicodeDecodeError):
            continue
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
