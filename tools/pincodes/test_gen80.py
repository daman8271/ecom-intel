import copy
import gen80


def _mini_universe():
    pins = [f"1100{i:02d}" for i in range(10)]
    meta = {p: {"lat": 28.6 + i * 0.01, "lon": 77.2, "locality": f"O{i}",
                "urban": i < 8} for i, p in enumerate(pins)}
    # one pin with no coords -> must still be listed (neighbor fallback)
    meta["110009"]["lat"] = meta["110009"]["lon"] = None
    return {"Delhi": {"pins": set(pins), "meta": meta}}


def test_expand_plain_refreshes_existing_coords_and_keeps_full_coverage():
    uni = _mini_universe()
    existing = [{"city": "Delhi", "pincode": "110005", "tier": 1, "represents": 1,
                 "pincodes": ["110005"], "lat": 1.0, "lon": 2.0, "locality": "X"}]
    targets = {"Delhi": sorted(uni["Delhi"]["pins"])}
    out = gen80.expand_plain(copy.deepcopy(existing), targets, uni)
    assert out[0]["pincode"] == existing[0]["pincode"]  # existing entries stay first
    assert out[0]["lat"] == uni["Delhi"]["meta"]["110005"]["lat"]
    assert out[0]["lon"] == uni["Delhi"]["meta"]["110005"]["lon"]
    got = {e["pincode"] for e in out}
    assert got >= uni["Delhi"]["pins"]              # FULL coverage incl. coordless pin
    assert len(out) == len(got)                     # no duplicate pins
    e9 = next(e for e in out if e["pincode"] == "110009")
    assert e9["lat"] is not None                    # neighbor-fallback coordinate


def test_amazon_tail_excludes_core():
    uni = _mini_universe()
    core = [{"city": "Delhi", "pincode": "110000", "tier": 1, "represents": 1,
             "pincodes": ["110000"], "lat": 1, "lon": 2, "locality": "X"}]
    tail = gen80.amazon_tail(core, {"Delhi": ["110000", "110001"]}, uni)
    assert {e["pincode"] for e in tail} == {"110001"}


def test_reviewed_override_beats_contaminated_source_coordinate():
    uni = {"Noida": {"pins": {"201301"}, "meta": {
        "201301": {"lat": 26.54872, "lon": 78.54897, "locality": "Noida HO",
                   "urban": True}
    }}}
    assert gen80._coord("Noida", "201301", uni) == gen80.OVERRIDE_COORDS["201301"]


def test_instamart_anchors_cover_all_targets():
    uni = _mini_universe()
    targets = {"Delhi": sorted(uni["Delhi"]["pins"])}
    anchors = gen80.expand_instamart([], targets, uni)
    covered = {p for a in anchors for p in a["pincodes"]}
    assert covered >= uni["Delhi"]["pins"]
    assert all(a["city"] == "Delhi" for a in anchors)


if __name__ == "__main__":
    test_expand_plain_refreshes_existing_coords_and_keeps_full_coverage()
    test_amazon_tail_excludes_core()
    test_reviewed_override_beats_contaminated_source_coordinate()
    test_instamart_anchors_cover_all_targets()
    print("OK")
