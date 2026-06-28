import os, tempfile, unittest
from ledger import record, read_ledger, STATUSES

class TestLedger(unittest.TestCase):
    def test_record_appends_row(self):
        fd, path = tempfile.mkstemp(suffix=".csv"); os.close(fd); os.remove(path)
        record("blinkit","560001","Bengaluru","price_captured","r1","2026-06-29",sku_count=12,price_seen="199",path=path)
        record("blinkit","560002","Bengaluru","not_serviceable","r1","2026-06-29",path=path)
        rows = read_ledger(path)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["status"], "price_captured")
        self.assertEqual(rows[0]["sku_count"], "12")
        self.assertEqual(rows[1]["status"], "not_serviceable")
        os.remove(path)
    def test_invalid_status_raises(self):
        with self.assertRaises(ValueError):
            record("blinkit","560001","Bengaluru","bogus","r1","2026-06-29",path="/tmp/x.csv")

if __name__ == "__main__":
    unittest.main()
