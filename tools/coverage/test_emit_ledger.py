# tools/coverage/test_emit_ledger.py
import os, json, csv, tempfile, unittest
from emit_ledger_from_history import emit_for_run

class TestEmit(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.cfg = os.path.join(self.d, "cfg.json")
        json.dump([{"city":"Bengaluru","pincode":"560001","pincodes":["560001"]},
                   {"city":"Bengaluru","pincode":"560002","pincodes":["560002"]},
                   {"city":"Bengaluru","pincode":"560003","pincodes":["560003"]}], open(self.cfg,"w"))
        self.hist = os.path.join(self.d, "history.csv")
        with open(self.hist,"w",newline="") as f:
            w=csv.writer(f); w.writerow(["run_id","date_ist","platform","canonical_sku","city","pincode","price","mrp","discount_pct","in_stock"])
            w.writerow(["r1","2026-06-29","blinkit","jivo-canola","Bengaluru","560001","199","250","20","true"])  # price_captured
            w.writerow(["r1","2026-06-29","blinkit","jivo-mustard","Bengaluru","560002","","","","false"])         # serviceable_no_jivo
        self.led = os.path.join(self.d, "ledger.csv")
    def test_classifies_every_configured_pincode(self):
        n = emit_for_run("blinkit","r1","2026-06-29",self.hist,self.cfg,self.led)
        self.assertEqual(n, 3)
        rows = list(csv.DictReader(open(self.led)))
        by = {r["pincode"]: r["status"] for r in rows}
        self.assertEqual(by["560001"], "price_captured")
        self.assertEqual(by["560002"], "serviceable_no_jivo")
        self.assertEqual(by["560003"], "not_serviceable")   # configured, no row

if __name__ == "__main__":
    unittest.main()
