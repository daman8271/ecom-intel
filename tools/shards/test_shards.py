import json
import os
import subprocess
import tempfile
import unittest


HERE = os.path.dirname(os.path.abspath(__file__))
SPLIT = os.path.join(HERE, "split_pincodes.py")
MERGE = os.path.join(HERE, "merge_platform_shards.py")


class TestShards(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = self.td.name
        self.config = os.path.join(self.root, "pincodes.json")
        pins = [
            {"city": "A", "pincode": "100001"},
            {"city": "A", "pincode": "100002"},
            {"city": "B", "pincode": "100003"},
            {"city": "B", "pincode": "100004"},
        ]
        with open(self.config, "w") as f:
            json.dump(pins, f)

    def tearDown(self):
        self.td.cleanup()

    def split(self, idx):
        out = os.path.join(self.root, f"s{idx}")
        subprocess.check_call([
            "python3", SPLIT, "blinkit", self.config, out,
            "--total", "2", "--index", str(idx), "--run-id", "r1",
        ])
        return out

    def fake_result(self, shard_dir, idx):
        with open(os.path.join(shard_dir, f"manifest.{idx}-of-2.json")) as f:
            manifest = json.load(f)
        per = []
        rows = []
        for pin in manifest["shard_pincodes"]:
            row = {"pincode": pin, "city": "A", "resolved": True, "rows": []}
            if pin.endswith("1") or pin.endswith("4"):
                row["rows"] = [{"pincode": pin, "canonical": f"sku-{pin}", "in_stock": 1}]
                rows.extend(row["rows"])
            per.append(row)
        result = {
            "summary": {
                "wall_s": idx + 1,
                "partial": False,
                "auth_session": 1,
                "auth_required": 1,
                "oos_probe_enabled": 1,
                "oos_probe_flips": idx,
                "pdp_oos_probe_enabled": 1,
                "pdp_oos_probe_flips": idx + 1,
                "pdp_price_probe_enabled": 1,
                "pdp_price_probe_checked": idx + 2,
                "pdp_price_probe_updates": idx,
            },
            "perPin": per,
            "allRows": rows,
        }
        path = os.path.join(shard_dir, "result.json")
        with open(path, "w") as f:
            json.dump(result, f)
        return os.path.join(shard_dir, f"manifest.{idx}-of-2.json"), path

    def test_split_deterministic_modulo(self):
        s0 = self.split(0)
        s1 = self.split(1)
        with open(os.path.join(s0, "pincodes.0-of-2.json")) as f:
            p0 = [x["pincode"] for x in json.load(f)]
        with open(os.path.join(s1, "pincodes.1-of-2.json")) as f:
            p1 = [x["pincode"] for x in json.load(f)]
        self.assertEqual(p0, ["100001", "100003"])
        self.assertEqual(p1, ["100002", "100004"])

    def test_merge_validates_and_recomputes(self):
        pairs = [self.fake_result(self.split(0), 0), self.fake_result(self.split(1), 1)]
        out = os.path.join(self.root, "merged.json")
        flat = []
        for p in pairs:
            flat.extend(p)
        subprocess.check_call(["python3", MERGE, "blinkit", out, *flat])
        with open(out) as f:
            merged = json.load(f)
        self.assertEqual(merged["summary"]["pincodes_total"], 4)
        self.assertEqual(merged["summary"]["pincodes_with_jivo"], 2)
        self.assertEqual(merged["summary"]["unique_skus"], 2)
        self.assertEqual(merged["summary"]["auth_session"], 1)
        self.assertEqual(merged["summary"]["oos_probe_enabled"], 1)
        self.assertEqual(merged["summary"]["pdp_oos_probe_enabled"], 1)
        self.assertEqual(merged["summary"]["pdp_price_probe_enabled"], 1)
        self.assertEqual(merged["summary"]["oos_probe_flips"], 1)
        self.assertEqual(merged["summary"]["pdp_oos_probe_flips"], 3)
        self.assertEqual(merged["summary"]["pdp_price_probe_checked"], 5)
        self.assertEqual(merged["summary"]["pdp_price_probe_updates"], 1)
        self.assertEqual(merged["summary"]["unverified_oos"], 0)
        self.assertEqual([p["pincode"] for p in merged["perPin"]], ["100001", "100002", "100003", "100004"])


if __name__ == "__main__":
    unittest.main()
