#!/usr/bin/env python3
"""Guard against the Amazon "same default data" clobber bug.

amazon-fresh (acct 259) and amazon-now (acct 520) are independent surfaces with very
different reach (Fresh ~973 serviceable, Now ~132). If they ever start returning the
SAME serviceable set + SAME prices, an account-location clobber has regressed and both
are reading one store. This compares the two latest result.json files and flags it.

  exit 0  -> healthy (clearly distinct surfaces)
  exit 3  -> CLOBBER SUSPECT (caller should alert + NOT trust the data)

usage: python3 amazon_clobber_check.py [fresh_result.json] [now_result.json]
"""
import json, os, sys

BASE = "/opt/ecom-intel/platforms"

def served(path):
    """{pincode: (sku_count, lead_price)} for serviceable pincodes."""
    d = {}
    for x in json.load(open(path)).get("perPin", []):
        if not x.get("serviceable"):
            continue
        pin = str(x.get("pincode", "")).strip()
        rows = x.get("rows") or []
        price = ""
        for r in rows:
            v = str(r.get("sale") or r.get("price") or "").strip()
            if v:
                price = v; break
        d[pin] = (len(rows), price)
    return d

def main():
    fp = sys.argv[1] if len(sys.argv) > 1 else f"{BASE}/amazon-fresh/result.json"
    np = sys.argv[2] if len(sys.argv) > 2 else f"{BASE}/amazon-now/result.json"
    F, N = served(fp), served(np)
    nf, nn = len(F), len(N)
    shared = set(F) & set(N)
    union = set(F) | set(N)
    jac = len(shared) / len(union) if union else 0.0
    ident = sum(1 for p in shared if F[p] == N[p])
    ident_frac = ident / len(shared) if shared else 0.0

    print(f"[clobber-check] fresh serviceable={nf}  now serviceable={nn}")
    print(f"[clobber-check] serviceable-set Jaccard(fresh,now)={jac:.2f}  "
          f"shared={len(shared)}  identical sku+price on shared={ident_frac:.0%}")

    # Healthy: Now is a small subset of Fresh (jaccard low), prices mostly differ.
    # Clobber: near-identical serviceable sets OR Now balloons to Fresh-like size.
    suspect = (jac > 0.85) or (nn > 400 and nf > 0) or (len(shared) > 30 and ident_frac > 0.95)
    if suspect:
        print("[clobber-check] 🔴 CLOBBER SUSPECT — Fresh & Now look like the SAME store. "
              "Do not trust; check account locations (secrets cookies / glow).")
        sys.exit(3)
    print("[clobber-check] 🟢 healthy — Fresh & Now are clearly distinct surfaces.")
    sys.exit(0)

if __name__ == "__main__":
    main()
