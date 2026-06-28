import os, unittest
from universe25 import build_universe

CSV = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv")

class TestUniverse(unittest.TestCase):
    def setUp(self):
        self.city_pins, self.pin_city = build_universe(CSV)
    def test_total_universe_is_1885(self):
        allpins = set().union(*self.city_pins.values())
        self.assertEqual(len(allpins), 1885)
    def test_known_city_counts(self):
        self.assertEqual(len(self.city_pins["Delhi"]), 97)
        self.assertEqual(len(self.city_pins["Bengaluru"]), 117)
        self.assertEqual(len(self.city_pins["Vijayawada"]), 59)
        self.assertEqual(len(self.city_pins["Kochi"]), 143)
    def test_25_cities(self):
        self.assertEqual(len(self.city_pins), 25)

if __name__ == "__main__":
    unittest.main()
