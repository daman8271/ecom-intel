import unittest
from coverage_report import matrix

class TestMatrix(unittest.TestCase):
    def test_covered_counts_distinct_price_captured(self):
        rows = [
            {"platform":"blinkit","pincode":"560001","city":"Bengaluru","status":"price_captured","date_ist":"2026-06-29"},
            {"platform":"blinkit","pincode":"560001","city":"Bengaluru","status":"price_captured","date_ist":"2026-06-29"},
            {"platform":"blinkit","pincode":"560002","city":"Bengaluru","status":"not_serviceable","date_ist":"2026-06-29"},
        ]
        cp = {"Bengaluru": {"560001","560002","560003"}}
        m = matrix(rows, cp)
        self.assertEqual(m["Bengaluru"]["blinkit"]["covered"], 1)
        self.assertEqual(m["Bengaluru"]["blinkit"]["attempted"], 2)

if __name__ == "__main__":
    unittest.main()
