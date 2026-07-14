#!/usr/bin/env python3
"""Exit zero only when a competitor artifact has an exact accepted promotion."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--platform", choices=("blinkit", "zepto"), required=True)
    parser.add_argument("--receipts", default="logs/direct-competitor-report-receipts")
    args = parser.parse_args()

    candidate = Path(args.file).resolve()
    if not candidate.is_file() or candidate.is_symlink():
        return 1
    digest = sha256_file(candidate)
    workflow = "blinkit-top8" if args.platform == "blinkit" else "zepto-competitor"
    run_pattern = re.compile(
        rf"^{args.date.replace('-', '')}-[0-9]{{6}}-{args.platform}-competitor-direct-a[0-9]{{2}}$"
    )
    for path in (Path(args.receipts) / args.date).glob("*.json"):
        try:
            if path.is_symlink():
                continue
            value = json.loads(path.read_text(encoding="utf-8-sig"))
            if not all((
                value.get("schema") == "jivo-direct-competitor-promotion-receipt-v1",
                value.get("status") == "accepted",
                value.get("date_ist") == args.date,
                value.get("platform") == args.platform,
                value.get("workflow_kind") == workflow,
                isinstance(value.get("run_id"), str) and run_pattern.fullmatch(value["run_id"]),
            )):
                continue
            artifacts = value.get("artifacts")
            if not isinstance(artifacts, list):
                continue
            kinds = [item.get("kind") for item in artifacts if isinstance(item, dict)]
            if len(kinds) != 3 or set(kinds) != {"workbook", "merged_capture", "delivery_audit"}:
                continue
            exact = [
                item for item in artifacts
                if isinstance(item, dict)
                and item.get("kind") == "workbook"
                and Path(str(item.get("destination") or "")).resolve() == candidate
                and item.get("sha256") == digest
                and item.get("bytes") == candidate.stat().st_size
            ]
            if len(exact) != 1:
                continue
            # Recheck every promoted dependency, not just the workbook.
            verified = True
            for item in artifacts:
                artifact = Path(str(item.get("destination") or ""))
                if not artifact.is_file() or artifact.is_symlink() \
                   or artifact.stat().st_size != item.get("bytes") \
                   or sha256_file(artifact) != item.get("sha256"):
                    verified = False
                    break
            if verified:
                return 0
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            continue
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
