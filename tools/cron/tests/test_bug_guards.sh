#!/usr/bin/env bash
# test_bug_guards.sh — locks the 3 Codex-flagged bug-class guards so a code regression is
# caught, not shipped (goal #61, 2026-07-04). All hermetic: no scraping, no production writes.
#   Bug 1  Excel percent-inflation scanner (check_layout.check_percent_inflation)
#   Bug 2  BigBasket pincode under-coverage guard (ingest.sh, anchored to last-good)
#   Bug 3  BigBasket QC-API path refuses by default (run_pincode.sh)
set -uo pipefail
cd "$(cd "$(dirname "$0")/../../.." && pwd)"   # -> repo root
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1"; fail=$((fail+1)); }

# ---- Bug 3: the paid QuickCommerce-API path must refuse unless explicitly allowed ----
out=$(cd platforms/bigbasket && ./run_pincode.sh 2>&1); rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -qi "retired"; then
  ok "bug3: QC-API run_pincode.sh refuses by default (rc=2, 'retired')"
else
  no "bug3: QC-API path did NOT refuse (rc=$rc): $out"
fi

# ---- Bug 2: ingest guard predicate — anchored to last-good, refuses a partial pull ----
# Mirrors the guard in platforms/bigbasket/ingest.sh (keep in sync).
python3 - <<'PY' && ok "bug2: under-coverage guard refuses <75%-of-last-good, accepts full" || no "bug2: guard predicate wrong"
import math
def accept(new_pins, lg_pins, declared_min=0):
    anchored = math.ceil(0.75 * lg_pins) if lg_pins else 0
    required = max(declared_min, anchored, 20)
    return new_pins >= required
assert accept(207, 207) is True,  "full pull must pass"
assert accept(160, 207) is True,  "160/207 (>75%) must pass"
assert accept(50,  207) is False, "50-pin partial must be refused"
assert accept(1,   207) is False, "Bengaluru-only 1-pin collapse must be refused"
assert accept(30,  0, declared_min=0) is True,  "no last-good -> absolute floor 20 only"
assert accept(10,  0) is False, "below absolute floor 20 refused even w/o last-good"
PY
# and assert the real ingest.sh actually carries the last-good anchor (not just the predicate)
if grep -q "result.last-good.json" platforms/bigbasket/ingest.sh \
   && grep -q "0.75 \* lg_pins" platforms/bigbasket/ingest.sh; then
  ok "bug2: ingest.sh carries the last-good-anchored guard"
else
  no "bug2: ingest.sh missing the last-good anchor"
fi

# ---- Bug 1: percent scanner flags inflation, ignores legitimate large percentages ----
python3 - <<'PY' && ok "bug1: scanner flags raw%/quoted-%, ignores legit fractions" || no "bug1: scanner wrong"
import sys, os, tempfile
sys.path.insert(0, "tools/cron")
import check_layout as cl
from openpyxl import Workbook
d = tempfile.mkdtemp()
# clean book: a fraction 0.363 -> "36.3%" and a legit 161% gap 1.61 -> both fine
wb = Workbook(); ws = wb.active
ws["A1"] = 0.363; ws["A1"].number_format = "0.0%"
ws["A2"] = 1.61;  ws["A2"].number_format = "0.0%"     # 161% gap — legitimate
wb.save(os.path.join(d, "Clean-2099-01-01.xlsx"))
assert cl.check_percent_inflation("2099-01-01", d) == [], "clean book must not flag"
# dirty book: raw 36.3 with real % format (-> 3630%) and a quoted-% format
wb = Workbook(); ws = wb.active
ws["A1"] = 36.3; ws["A1"].number_format = "0.0%"      # raw percent -> inflation
ws["B1"] = 24.3; ws["B1"].number_format = '0.0"%"'    # quoted-percent format (old bug)
wb.save(os.path.join(d, "Dirty-2099-01-02.xlsx"))
probs = cl.check_percent_inflation("2099-01-02", d)
assert len(probs) >= 2, f"dirty book must flag both, got {probs}"
PY

# ---- Bug 2b: NATIONAL floor — a rate-limited (429/303) near-empty national drop must be
# refused, not shipped as OK (2026-07-10 incident: session_ok=true, rows=2 sailed through).
# Mirrors the national guard in platforms/bigbasket/ingest.sh (keep in sync).
python3 - <<'PY' && ok "bug2b: national floor refuses collapsed drop, accepts full" || no "bug2b: national floor predicate wrong"
import math
def accept(new_rows, lg_rows):
    required = max(math.ceil(0.75 * lg_rows) if lg_rows else 0, 8)
    return new_rows >= required
assert accept(15, 15) is True,  "full national pull must pass"
assert accept(12, 15) is True,  "12/15 (=75%) must pass"
assert accept(2,  15) is False, "2026-07-10-style 2-row collapse must be refused"
assert accept(0,  15) is False, "empty must be refused"
assert accept(10, 0)  is True,  "no last-good -> absolute floor 8 only"
assert accept(5,  0)  is False, "below absolute floor 8 refused even w/o last-good"
PY
if grep -q "result.national.last-good.json" platforms/bigbasket/ingest.sh \
   && grep -q "0.75 \* lg_rows" platforms/bigbasket/ingest.sh; then
  ok "bug2b: ingest.sh carries the national last-good-anchored floor"
else
  no "bug2b: ingest.sh missing the national floor"
fi

echo "-----"
echo "bug-guard tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
