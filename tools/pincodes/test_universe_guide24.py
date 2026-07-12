import universe_guide24 as U

CSV = "/opt/ecom-intel/docs/pincodes/drr_pincode.csv"
# Ground truth = the live coverage-guide site (generated 2026-07-10)
EXPECT = {"Delhi": 97, "Mumbai": 89, "Pune": 145, "Nagpur": 63, "Nashik": 77,
          "Noida": 28, "Lucknow": 43, "Ghaziabad": 26, "Gurugram": 29,
          "Faridabad": 15, "Ludhiana": 73, "Amritsar": 36, "Jalandhar": 67,
          "Mohali": 22, "Bangalore": 117, "Mysore": 68, "Mangalore": 95,
          "Hyderabad": 60, "Kolkata": 74, "Howrah": 55, "Chandigarh": 25,
          "Chennai": 83, "Coimbatore": 107, "Madurai": 57}


def test_universe_counts():
    data = U.build(CSV)
    assert set(data) == set(EXPECT), sorted(set(data) ^ set(EXPECT))
    for c, n in EXPECT.items():
        assert len(data[c]["pins"]) == n, f"{c}: {len(data[c]['pins'])} != {n}"
    assert len(set().union(*(d["pins"] for d in data.values()))) == 1550


def test_select_targets_full_and_ordered():
    data = U.build(CSV)
    tracked = {"110001"}  # pretend one Delhi pin already tracked
    tg = U.select_targets(data, tracked, pct=1.0)
    for c, pins in tg.items():
        assert set(pins) == data[c]["pins"], f"{c}: not full universe"
    assert tg["Delhi"][0] == "110001"  # tracked pins rank first
    # after the tracked block, urban (HO/SO) pins come before rural: the
    # rural pins must form a contiguous suffix
    urb = [data["Delhi"]["meta"][p]["urban"] for p in tg["Delhi"][1:]]
    if False in urb:
        assert not any(urb[urb.index(False):]), "rural pins not a suffix"


def test_meta_coords_or_fallbackable():
    data = U.build(CSV)
    for c, d in data.items():
        with_geo = [p for p in d["pins"] if d["meta"][p]["lat"] is not None]
        assert with_geo, f"{c}: no pin has coordinates at all"


if __name__ == "__main__":
    test_universe_counts()
    test_select_targets_full_and_ordered()
    test_meta_coords_or_fallbackable()
    print("OK")
