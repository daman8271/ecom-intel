from cluster import cluster

PTS = [{"pincode": f"5600{i:02d}", "lat": 13.0 + i * 0.01, "lon": 77.5,
        "locality": f"L{i}"} for i in range(7)]


def test_all_assigned_once():
    anchors = cluster(PTS, density=3)
    got = [p for a in anchors for p in a["pincodes"]]
    assert sorted(got) == sorted(x["pincode"] for x in PTS)


def test_deterministic_and_schema():
    a1, a2 = cluster(PTS, 3), cluster(PTS, 3)
    assert a1 == a2
    for a in a1:
        assert a["pincode"] in a["pincodes"]
        assert a["represents"] == len(a["pincodes"])
        assert set(a) >= {"pincode", "tier", "represents", "pincodes",
                          "lat", "lon", "locality"}


if __name__ == "__main__":
    test_all_assigned_once()
    test_deterministic_and_schema()
    print("OK")
