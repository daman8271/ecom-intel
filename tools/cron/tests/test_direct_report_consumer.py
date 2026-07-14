#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from openpyxl import Workbook


ROOT = Path(__file__).resolve().parents[3]
CONSUMER = ROOT / "tools/cron/direct_report_consumer.py"
ACCEPTED_GATE = ROOT / "tools/cron/direct_report_is_accepted.py"
DATE = "2026-07-15"
RUN_ID = "20260715-000000-zepto-direct"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DirectReportConsumerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.inbox = self.base / "inbox"
        self.output = self.base / "output"
        self.receipts = self.base / "receipts"
        self.failures = self.base / "failures"
        self.run = self.inbox / RUN_ID
        self.run.mkdir(parents=True)
        self.book = self.run / f"Jivo-Zepto-Live-Report-{DATE}.xlsx"
        workbook = Workbook()
        workbook.remove(workbook.active)
        for name in ("Summary", "Master Data", "Pricing Matrix", "Stock Status", "Discount Analysis", "Coverage & Gaps"):
            sheet = workbook.create_sheet(name)
            sheet.append(["header", "value"])
            for row in range(100):
                value = hashlib.sha256(f"{name}-{row}".encode()).hexdigest()
                sheet.append([f"row-{row}", value])
        workbook.save(self.book)
        self.receipt = {
            "schema": "jivo-direct-report-receipt-v1",
            "platform": "zepto",
            "date_ist": DATE,
            "run_id": RUN_ID,
            "attempt_id": "01",
            "status": "ready",
            "review_verdict": "OK",
            "plan_sha256": "b" * 64,
            "source_sha256": "c" * 64,
            "scraper_sha256": "d" * 64,
            "merged_sha256": "a" * 64,
            "merged_bytes": 12345,
            "merge_receipt_sha256": "e" * 64,
            "input_result_sha256": {"macpro": "f" * 64, "windows": "1" * 64},
            "pincodes_total": 2,
            "total_rows": 2,
            "quality_policy": {"min_serviceable_pct": 20.0, "min_rows_per_source_pincode": 1.0},
            "workbooks": [{"name": self.book.name, "bytes": self.book.stat().st_size, "sha256": sha256(self.book)}],
        }
        (self.run / "report.ready.json").write_text(json.dumps(self.receipt), encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_consumer(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(CONSUMER), "--inbox", str(self.inbox), "--output", str(self.output),
             "--receipts", str(self.receipts), "--failure-receipts", str(self.failures),
             "--date", DATE, "--stable-age", "0", "--ack-host", ""],
            text=True, capture_output=True,
        )

    def run_gate(self, file: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(ACCEPTED_GATE), "--file", str(file), "--date", DATE,
             "--inbox", str(self.inbox), "--receipts", str(self.receipts)],
            text=True, capture_output=True,
        )

    def test_valid_report_is_promoted_once(self) -> None:
        self.assertNotEqual(self.run_gate(self.book).returncode, 0)
        first = self.run_consumer()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)["new"], 1)
        self.assertEqual(sha256(self.output / self.book.name), sha256(self.book))
        self.assertEqual(self.run_gate(self.output / self.book.name).returncode, 0)
        second = self.run_consumer()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads(second.stdout)["new"], 0)
        self.assertEqual(json.loads(second.stdout)["existing"], 1)

    def test_tampered_workbook_is_rejected(self) -> None:
        self.book.write_bytes(self.book.read_bytes() + b"tamper")
        result = self.run_consumer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hash/size mismatch", result.stderr)
        self.assertFalse((self.output / self.book.name).exists())

    def test_different_existing_report_is_not_overwritten(self) -> None:
        self.output.mkdir()
        (self.output / self.book.name).write_bytes(b"different")
        result = self.run_consumer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite", result.stderr)
        self.assertEqual((self.output / self.book.name).read_bytes(), b"different")

    def test_tampered_accepted_output_is_rejected(self) -> None:
        first = self.run_consumer()
        self.assertEqual(first.returncode, 0, first.stderr)
        promoted = self.output / self.book.name
        promoted.write_bytes(promoted.read_bytes() + b"tamper")
        second = self.run_consumer()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("accepted output hash changed", second.stderr)

    def test_missing_accepted_output_is_restored(self) -> None:
        first = self.run_consumer()
        self.assertEqual(first.returncode, 0, first.stderr)
        promoted = self.output / self.book.name
        promoted.unlink()
        second = self.run_consumer()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(sha256(promoted), sha256(self.book))

    def test_unsafe_run_isolated_while_valid_run_promotes(self) -> None:
        bad_id = "20260715-000001-zepto-direct;touch-x"
        bad_run = self.inbox / bad_id
        shutil.copytree(self.run, bad_run)
        bad_receipt_path = bad_run / "report.ready.json"
        bad_receipt = json.loads(bad_receipt_path.read_text())
        bad_receipt["run_id"] = bad_id
        bad_receipt_path.write_text(json.dumps(bad_receipt))
        result = self.run_consumer()
        self.assertNotEqual(result.returncode, 0)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["new"], 1)
        self.assertEqual(len(summary["errors"]), 1)
        self.assertIn("unsafe run_id", result.stderr)
        self.assertTrue((self.output / self.book.name).is_file())

    def test_endpoint_failure_alerts_once(self) -> None:
        failed_id = "20260715-000002-zepto-direct"
        failed = self.inbox / failed_id
        failed.mkdir()
        failure = {
            "schema": "jivo-direct-failure-receipt-v1",
            "plan_sha256": "b" * 64,
            "platform": "zepto",
            "date_ist": DATE,
            "run_id": failed_id,
            "attempt_id": "01",
            "status": "failed",
            "phase": "windows-terminal",
            "reason": "runner_rc=1",
        }
        (failed / "failure.json").write_text(json.dumps(failure))
        first = self.run_consumer()
        self.assertEqual(len(json.loads(first.stdout)["endpoint_failures"]), 1)
        second = self.run_consumer()
        self.assertEqual(len(json.loads(second.stdout)["endpoint_failures"]), 0)


if __name__ == "__main__":
    unittest.main()
