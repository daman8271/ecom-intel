#!/usr/bin/env python3
"""Generate data.js for the JIVO Availability Console (ecom-availability-app.vercel.app).

Reproduces the exact schema window.JIVO_AVAILABILITY_DATA expects (see app.js):
  summary{pincodes,platforms,states,skus,sourceObservationRows,latestAvailabilityRows}
  states[] platforms[] skus[]  pincodes{pin:{pincode,city,state}}
  coverage[{state,platform,pincodes[]}]
  records[{p,pl,s,c,st,price,mrp,disc,stock,date,run[,skuCount]}]
  meta{runs{platform:{run_id,date}}, skuLevel{platform:bool}}

Serviceability = each platform's full census; prices/stock = freshest history row.
Deterministic, stdlib only, no LLM. index.html + app.js are NOT touched (layout).
"""
import os, sys, json, datetime, collections
sys.path.insert(0, os.path.dirname(__file__))
import sitelib as S

OUT = os.environ.get(
    "CONSOLE_DIR",
    "/root/pa-clients/jivo-data-bank/reports/ecom-availability-app")
PLATFORMS = sorted(S.QC_PLATFORMS + S.AMAZON_PLATFORMS)  # alpha order, matches live


def build(today=None):
    today = today or datetime.date.today().isoformat()
    ledger = S.load_ledger()
    pin_city = S.pin_city_map(ledger)

    coverage = []                 # {state, platform, pincodes[]}
    records = []                  # availability rows
    pincodes = {}                 # pin -> {pincode, city, state}
    runs = {}                     # platform -> {run_id, date}
    latest_obs = ""

    for p in PLATFORMS:
        date, run_id, crows = S.census(ledger, p)
        if date is None:
            continue
        runs[p] = {"run_id": run_id, "date": date}
        latest_obs = max(latest_obs, date)

        # status per pincode in the footprint
        status, skucount, priceseen, cityof = {}, {}, {}, {}
        for r in crows:
            pin = r["pincode"]
            status[pin] = r["status"]
            skucount[pin] = S._num(r.get("sku_count")) or 0
            priceseen[pin] = S._num(r.get("price_seen"))
            cityof[pin] = (r.get("city") or pin_city.get(pin, "")).strip()

        serv = [pin for pin in status if status[pin] in S.SERVICEABLE]

        # coverage rows grouped by state
        by_state = collections.defaultdict(list)
        for pin in serv:
            city = cityof[pin]
            st = S.state_of(city)
            if not st:
                continue
            by_state[st].append(pin)
            pincodes[pin] = {"pincode": pin, "city": city, "state": st}
        for st in sorted(by_state):
            coverage.append({"state": st, "platform": p,
                             "pincodes": sorted(by_state[st])})

        serv_set = set(serv)
        if S.SKU_LEVEL[p]:
            # per-SKU records from freshest history, restricted to served pincodes
            fh = S.freshest_history(p)
            for (pin, sku), v in fh.items():
                if pin not in serv_set:
                    continue
                # honesty: never show a (pin,sku) last seen BEFORE the current census as
                # "live" — those are delisted / frozen clusters (freshness_guard rule).
                if v["date"] < date:
                    continue
                city = cityof.get(pin) or v.get("city") or pin_city.get(pin, "")
                st = S.state_of(city)
                if not st:
                    continue
                records.append({"p": pin, "pl": p, "s": sku, "c": city, "st": st,
                                "price": v["price"], "mrp": v["mrp"], "disc": v["disc"],
                                "stock": v["stock"], "date": v["date"], "run": v["run"]})
        else:
            # Amazon: one coverage record per served pincode (representative price + sku count)
            for pin in serv:
                city = cityof[pin]
                st = S.state_of(city)
                if not st:
                    continue
                priced = status[pin] == "price_captured"
                records.append({"p": pin, "pl": p, "s": "__coverage__", "c": city, "st": st,
                                "price": priceseen[pin] if priced else None,
                                "mrp": None, "disc": None,
                                "stock": 1 if priced else 0,
                                "date": date, "run": run_id,
                                "skuCount": skucount[pin] if priced else 0})

    states = sorted({v["state"] for v in pincodes.values()})
    skus = sorted({r["s"] for r in records if r["s"] != "__coverage__"})

    data = {
        "generatedFrom": "/opt/ecom-intel/data/coverage/ledger.csv + data/<platform>/history.csv",
        "generatedAt": today,
        "latestObservationDate": f"{latest_obs} (coverage runs)",
        "summary": {
            "pincodes": len(pincodes), "platforms": len(runs),
            "states": len(states), "skus": len(skus),
            "sourceObservationRows": len(records), "latestAvailabilityRows": len(records),
        },
        "states": states,
        "platforms": [p for p in PLATFORMS if p in runs],
        "skus": skus,
        "pincodes": dict(sorted(pincodes.items())),
        "coverage": coverage,
        "records": records,
        "meta": {"runs": runs, "skuLevel": {p: S.SKU_LEVEL[p] for p in runs}},
    }
    return data


def main():
    data = build()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "data.js")
    with open(path, "w") as f:
        f.write("window.JIVO_AVAILABILITY_DATA = ")
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")
    s = data["summary"]
    print(f"[console] wrote {path}")
    print(f"  generatedAt={data['generatedAt']} latestObs={data['latestObservationDate']}")
    print(f"  pincodes={s['pincodes']} platforms={s['platforms']} states={s['states']} "
          f"skus={s['skus']} records={s['sourceObservationRows']} coverage_rows={len(data['coverage'])}")
    print(f"  runs={ {p: r['date'] for p, r in data['meta']['runs'].items()} }")


if __name__ == "__main__":
    main()
