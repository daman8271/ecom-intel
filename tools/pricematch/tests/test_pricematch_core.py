import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import pricematch_core as pc


def ctx_with_rows(rows):
    return {
        "_comparisons": {},
        "regime": "BAU",
        "basis_pincode": None,
        "sku_names": ["JIVO POMACE 5L"],
        "master": {
            "JIVO POMACE 5L": {
                "bau": 1688,
                "svd": 1688,
                "art": 1688,
                "mrp": 4999,
            }
        },
        "map": {
            "JIVO POMACE 5L": {
                "platforms": {
                    "blinkit": {
                        "id": "407561",
                        "url": "https://blinkit.com/prn/jivo-pomace-olive-oil/prid/407561",
                        "title": "Jivo Pomace Olive Oil",
                        "confidence": "exact",
                    }
                }
            }
        },
        "pending": {},
        "live": {
            "blinkit": {
                "by_id": {"407561": rows} if rows is not None else {},
                "by_canonical": {},
                "rows": len(rows or []),
                "mtime": None,
                "path": "fixture",
            }
        },
    }


class PriceMatchBlinkitListingStatusTest(unittest.TestCase):
    def test_mapped_listing_absent_is_not_listed_not_oos(self):
        rec = pc.platform_comparison(ctx_with_rows([]), "blinkit")[0]
        self.assertEqual(rec["status"], "NOT_LISTED")

    def test_explicit_live_oos_row_is_oos(self):
        rec = pc.platform_comparison(ctx_with_rows([{
            "prid": "407561",
            "pincode": "110094",
            "city": "Delhi",
            "sale": 1688,
            "mrp": 4999,
            "in_stock": 0,
            "listing_status": "listed_out_of_stock",
        }]), "blinkit")[0]
        self.assertEqual(rec["status"], "OOS")


if __name__ == "__main__":
    unittest.main()
