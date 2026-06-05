#!/usr/bin/env python3
# Build ONE consolidated WhatsApp summary for a given date across all platforms,
# plus the list of Excel files to attach. Reuses the same headline logic as the
# Telegram delivery in run.sh (deterministic, no LLM), reading each platform's
# latest platforms/<dir>/result.json.
#
# Usage:  python3 build_group_summary.py <YYYY-MM-DD>
# Output: JSON on stdout -> {"date","summary","files":[{"path","caption","platform"}]}
import json, sys, os, datetime

ROOT = "/opt/ecom-intel"
OUT = os.path.join(ROOT, "output")
DATE = sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat()

# dir -> (display name, xlsx filename token)  — order = how they appear in the message
PLAT = [
    ("blinkit",          "Blinkit",          "Blinkit"),
    ("zepto",            "Zepto",            "Zepto"),
    ("flipkart-minutes", "Flipkart Minutes", "FlipkartMinutes"),
    ("flipkart",         "Flipkart",         "Flipkart"),
    ("bigbasket",        "BigBasket",        "Bigbasket"),
    ("amazon",           "Amazon",           "Amazon"),
    ("amazon-now",       "Amazon Now",       "AmazonNow"),
    ("amazon-fresh",     "Amazon Fresh",     "AmazonFresh"),
]

def clean(t):
    return str(t).replace("*", "").replace("_", "").replace("`", "").strip()

def headline(pdir):
    path = os.path.join(ROOT, "platforms", pdir, "result.json")
    if not os.path.exists(path):
        return None
    try:
        d = json.load(open(path))
    except Exception:
        return None
    s = d.get("summary", {})
    rows = d.get("allRows") or [r for p in d.get("perPin", []) for r in p.get("rows", [])]
    pin_with = s.get("pincodes_with_jivo", "?")
    pin_tot = s.get("pincodes_total", "?")
    skus = s.get("unique_skus") or len({r.get("canonical") for r in rows})
    nrows = s.get("total_rows") or len(rows)
    cheap = disc = None
    instock = [r for r in rows if r.get("in_stock") and (r.get("per_litre") or 0) > 0]
    if instock:
        c = min(instock, key=lambda r: r["per_litre"])
        cheap = (clean(c.get("sku_raw") or c.get("canonical") or "?"), int(round(c["per_litre"])), clean(c.get("city")))
    dd = [r for r in rows if (r.get("discount_pct") or 0) > 0]
    if dd:
        t = max(dd, key=lambda r: r["discount_pct"])
        disc = (clean(t.get("sku_raw") or t.get("canonical") or "?"), int(round(t["discount_pct"])), clean(t.get("city")))
    return dict(pin_with=pin_with, pin_tot=pin_tot, skus=skus, nrows=nrows, cheap=cheap, disc=disc)

blocks, files = [], []
for pdir, disp, token in PLAT:
    xlsx = os.path.join(OUT, f"Jivo-{token}-Live-Report-{DATE}.xlsx")
    if not os.path.exists(xlsx):
        continue
    h = headline(pdir)
    if not h:
        blocks.append(f"*{disp}* — report attached")
    else:
        line = f"*{disp}* — {h['pin_with']}/{h['pin_tot']} pincodes · {h['skus']} SKUs · {h['nrows']} rows"
        if h["cheap"]:
            line += f"\n   \U0001F4B0 {h['cheap'][0]} — ₹{h['cheap'][1]}/L ({h['cheap'][2]})"
        if h["disc"]:
            line += f"\n   \U0001F3F7️ {h['disc'][0]} — {h['disc'][1]}% off ({h['disc'][2]})"
        blocks.append(line)
    files.append({"path": xlsx, "caption": f"Jivo × {disp} · {DATE}", "platform": disp})

try:
    datedisp = datetime.date.fromisoformat(DATE).strftime("%-d %b %Y")
except Exception:
    datedisp = DATE

summary = (
    f"*Jivo · Ecom Price Intel*\n_{datedisp}_\n\n"
    + "\n\n".join(blocks)
    + f"\n\n\U0001F4CE {len(files)} platform reports attached below."
)
print(json.dumps({"date": DATE, "summary": summary, "files": files}, ensure_ascii=False))
