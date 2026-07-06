import os, unittest
from universe25 import build_universe
from gen_full_configs import gen_config, is_india_coordinate, is_plausible_pincode_coordinate, load_centroids

CSV = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "pincodes", "drr_pincode.csv")

class TestGen(unittest.TestCase):
    def test_india_bbox_rejects_coordinate_anomalies(self):
        self.assertTrue(is_india_coordinate(28.5381667, 77.2150278))
        self.assertTrue(is_india_coordinate(18.52047, 73.300211))
        self.assertFalse(is_india_coordinate(38.278, 67.503))
        self.assertFalse(is_india_coordinate(18.599, 64.390))
        self.assertFalse(is_india_coordinate(77.307889, 28.503718))
        self.assertFalse(is_plausible_pincode_coordinate("110010", 77.13, 28.48))
        self.assertTrue(is_plausible_pincode_coordinate("110010", 28.5957222, 77.1364444))

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
        self.assertTrue(all(is_india_coordinate(e["lat"], e["lon"]) for e in cfg if e["lat"] and e["lon"]))

    def test_known_bad_pins_use_filtered_centroids(self):
        cp, pc = build_universe(CSV)
        cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents, cities=["Delhi", "Pune"])
        by_pin = {e["pincode"]: e for e in cfg}

        delhi = by_pin["110044"]
        self.assertEqual(delhi["city"], "Delhi")
        self.assertGreater(delhi["lat"], 28.0)
        self.assertLess(delhi["lat"], 29.0)
        self.assertGreater(delhi["lon"], 77.0)
        self.assertLess(delhi["lon"], 78.0)

        cantt = by_pin["110010"]
        self.assertGreater(cantt["lat"], 28.0)
        self.assertLess(cantt["lat"], 29.0)
        self.assertGreater(cantt["lon"], 77.0)
        self.assertLess(cantt["lon"], 78.0)

        pune = by_pin["410401"]
        self.assertEqual(pune["city"], "Pune")
        self.assertGreater(pune["lat"], 18.0)
        self.assertLess(pune["lat"], 19.0)
        self.assertGreater(pune["lon"], 73.0)
        self.assertLess(pune["lon"], 74.0)

    def test_zero_cities_present(self):
        cp, pc = build_universe(CSV); cents = load_centroids(CSV)
        cfg = gen_config(cp, pc, cents, cities=["Kochi","Nashik","Vijayawada"])
        self.assertGreater(len([e for e in cfg if e["city"]=="Kochi"]), 0)

if __name__ == "__main__":
    unittest.main()
