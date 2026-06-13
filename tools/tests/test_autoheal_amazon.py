#!/usr/bin/env python3
"""
Regression tests for tools/autoheal_amazon.py — the Amazon canonical-collision
auto-heal. Pure/synthetic (no network, no live files), so it runs anywhere fast.

The end-to-end proof against the REAL held run + REAL Claude adjudicator was run
once at build time (2026-06-13, amazon-now-2026-06-13-1346): 8 collisions, Claude
merged 3 stubs via matching ASIN, verdict SUSPECT->OK, priced multiset identical.
These tests lock in the guarantees so a future edit can't silently break them.

Run:  python3 tools/tests/test_autoheal_amazon.py
"""
import copy
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import autoheal_amazon as ah  # noqa: E402


def _row(canonical, sale, mrp, pincode, asin=None, sku_raw=None, item=None, in_stock=1):
    return {"canonical": canonical, "sale": sale, "mrp": mrp,
            "discount_pct": round((1 - sale / mrp) * 100) if mrp else 0,
            "pincode": pincode, "city": "Delhi", "in_stock": in_stock,
            "asin": asin, "sku_raw": sku_raw or canonical, "item": item}


def _fixture():
    """A scrape where one product (canola) got a truncated stub canonical sharing
    its (sale,mrp) + ASIN, plus an unrelated product at a different price."""
    full = "jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-1l"
    stub = "jivo-canola-cold-pressed-edible-oil-1-litre-cooking-o-1l"
    other = "jivo-extra-light-olive-oil-1l"
    rows = []
    # full canola across 6 pincodes at 263/375
    for i, pin in enumerate(("110001", "110002", "110003", "560001", "560002", "560003")):
        rows.append(_row(full, 263, 375, pin, asin="B09MJ6QDX7",
                         sku_raw="Jivo Canola Cold Pressed Edible Oil 1 Litre Cooking Oil for Daily Use"))
    # the stub: SAME product, truncated title, SAME asin, SAME price, 2 pincodes
    for pin in ("110026", "110027"):
        rows.append(_row(stub, 263, 375, pin, asin="B09MJ6QDX7",
                         sku_raw="Jivo Canola Cold Pressed Edible Oil 1 Litre Cooking O"))
    # an unrelated product at a different discounted price (must NOT be touched)
    for pin in ("110001", "560001", "560002"):
        rows.append(_row(other, 690, 999, pin, asin="B07XYZAAAA",
                         sku_raw="Jivo Extra Light Olive Oil 1L"))
    return {"summary": {"pincodes_total": 8, "unique_skus": 3, "total_rows": len(rows)},
            "allRows": rows, "perPin": []}


class TestCollisionDetection(unittest.TestCase):
    def test_finds_shared_price_pair(self):
        data = _fixture()
        pairs = ah.colliding_pairs(ah.all_rows(data))
        self.assertEqual(len(pairs), 1)
        canon = {c for agg in pairs[0]["identities"].values() for c in agg["canonicals"]}
        self.assertIn("jivo-canola-cold-pressed-edible-oil-1-litre-cooking-o-1l", canon)
        self.assertEqual(len(pairs[0]["identities"]), 2)  # full + stub = 2 identities

    def test_unrelated_price_not_flagged(self):
        # the olive-oil 690/999 is held by only ONE product -> never a collision
        data = _fixture()
        pairs = ah.colliding_pairs(ah.all_rows(data))
        for p in pairs:
            self.assertNotIn((690.0, 999.0), [(p["sale"], p["mrp"])])


class TestMergeValidation(unittest.TestCase):
    def setUp(self):
        self.present = {r["canonical"] for r in ah.all_rows(_fixture())}

    def test_accepts_good_merge(self):
        parsed = {"merges": [{"survivor": "jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-1l",
                              "stubs": ["jivo-canola-cold-pressed-edible-oil-1-litre-cooking-o-1l"]}]}
        mm = ah.validate_merges(parsed, self.present)
        self.assertEqual(mm, {"jivo-canola-cold-pressed-edible-oil-1-litre-cooking-o-1l":
                              "jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-1l"})

    def test_rejects_unknown_canonicals(self):
        parsed = {"merges": [{"survivor": "does-not-exist", "stubs": ["also-fake"]}]}
        self.assertEqual(ah.validate_merges(parsed, self.present), {})

    def test_rejects_self_merge(self):
        c = "jivo-extra-light-olive-oil-1l"
        self.assertEqual(ah.validate_merges({"merges": [{"survivor": c, "stubs": [c]}]}, self.present), {})

    def test_empty_when_no_merges(self):
        self.assertEqual(ah.validate_merges({"merges": [], "distinct": ["x"]}, self.present), {})


class TestIdentityOnlyMerge(unittest.TestCase):
    def test_prices_byte_identical_and_skus_drop(self):
        data = _fixture()
        before = ah.priced_signature(ah.all_rows(data))
        n_before = len({r["canonical"] for r in ah.all_rows(data)})
        mm = {"jivo-canola-cold-pressed-edible-oil-1-litre-cooking-o-1l":
              "jivo-canola-cold-pressed-edible-oil-1-litre-cooking-oil-for-daily-use-1l"}
        healed = copy.deepcopy(data)
        rewritten = ah.apply_merges(healed, mm)
        ah.refresh_summary(healed)
        after = ah.priced_signature(ah.all_rows(healed))
        n_after = len({r["canonical"] for r in ah.all_rows(healed)})
        self.assertEqual(rewritten, 2)                 # the 2 stub rows
        self.assertEqual(before, after)                # PRICE TRIPWIRE: nothing touched
        self.assertEqual(len(ah.all_rows(healed)), len(ah.all_rows(data)))  # no rows dropped
        self.assertEqual(n_before - n_after, 1)        # stub SKU folded away
        # the collision is gone after merge
        self.assertEqual(ah.colliding_pairs(ah.all_rows(healed)), [])

    def test_merge_rewrites_perpin_too(self):
        data = {"summary": {}, "allRows": [], "perPin": [
            {"pincode": "110001", "rows": [_row("stub-x", 100, 150, "110001")]}]}
        ah.apply_merges(data, {"stub-x": "survivor-y"})
        self.assertEqual(data["perPin"][0]["rows"][0]["canonical"], "survivor-y")


class TestFailSafeParsing(unittest.TestCase):
    def test_extract_plain_json(self):
        self.assertEqual(ah._extract_json('{"merges": []}'), {"merges": []})

    def test_extract_fenced_json(self):
        self.assertEqual(ah._extract_json('```json\n{"merges": [], "distinct": []}\n```'),
                         {"merges": [], "distinct": []})

    def test_extract_json_with_prose(self):
        out = ah._extract_json('Here is my answer:\n{"merges": [{"survivor":"a","stubs":["b"]}]}\nDone.')
        self.assertEqual(out["merges"][0]["survivor"], "a")

    def test_junk_returns_none(self):
        self.assertIsNone(ah._extract_json("the model is currently unavailable"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
