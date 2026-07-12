import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "coordinate_preflight.py"
SPEC = importlib.util.spec_from_file_location("coordinate_preflight", SCRIPT)
PREFLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFLIGHT)


def test_accepts_local_city_clusters():
    rows = [
        {"city": "Delhi", "pincode": f"11000{i}", "lat": 28.60 + i / 100,
         "lon": 77.20 + i / 100}
        for i in range(5)
    ]
    assert PREFLIGHT.validate(rows)["ok"]


def test_rejects_swaps_and_wrong_city_outliers():
    rows = [
        {"city": "Delhi", "pincode": f"11000{i}", "lat": 28.60 + i / 100,
         "lon": 77.20 + i / 100}
        for i in range(5)
    ]
    rows.extend([
        {"city": "Delhi", "pincode": "110082", "lat": 77.119, "lon": 28.772},
        {"city": "Delhi", "pincode": "110084", "lat": 18.52, "lon": 73.85},
    ])
    result = PREFLIGHT.validate(rows)
    assert not result["ok"]
    codes = {item["code"] for item in result["issues"]}
    assert "coordinate_outside_india" in codes
    assert "city_coordinate_outliers" in codes
