import os, unittest
from universe25 import build_universe
from gen_full_configs import gen_config, load_centroids

CSV = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv")

class TestGen(unittest.TestCase):
    def test_one_entry_per_pincode_in_universe(self):
        cp, pc = build_universe(CSV)
        cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents)
        self.assertEqual(len(cfg), 1885)
        pins = {e["pincode"] for e in cfg}
        self.assertEqual(len(pins), 1885)
        self.assertTrue(all(e["represents"] == 1 for e in cfg))
        self.assertTrue(all(e["pincodes"] == [e["pincode"]] for e in cfg))
        self.assertTrue(all(e["city"] in cp for e in cfg))
    def test_zero_cities_present(self):
        cp, pc = build_universe(CSV); cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents, cities=["Kochi","Nashik","Vijayawada"])
        self.assertGreater(len([e for e in cfg if e["city"]=="Kochi"]), 0)

if __name__ == "__main__":
    unittest.main()
