#!/usr/bin/env python3
"""
combined_backbone.py — build the bridge/hub layer for the COMBINED vault and
auto-inject cross-vault wikilinks.

Reads:
  - bridge   : docs/jivo-databank/sku-bridge/bridge_result.json (core + new_confirmed)
  - matches  : docs/jivo-databank/sku-bridge/core_matches.json  (name -> {platform: canonical})
  - jivo_skus: docs/jivo-databank/sku-bridge/jivo_skus.json     (SAP -> name)
  - pricematch: data/pricematch/history.csv                     (competitor-price lens)
  - target-history: /root/jivo-intel/docs/app-model/target-history.csv (tier-level JIVO lens)

Writes into /opt/ecom-intel/combined-vault/:
  - products/<Product>.md   per matched product (identity + competitor lens + JIVO lens + Connections)
  - hubs/Category - *.md, hubs/Platform - *.md, hubs/Tier - *.md
  - Home.md  (MOC)
  - '## Related' sections appended (idempotently) into every jivo+ecom source note
    that clearly references a known SKU/canonical/product/platform/category.

Vault copies (jivo/, ecom/) already exist under combined-vault/.
Read-only on the source databanks; only the combined-vault is written. Does NOT commit.
"""
import os, re, json, csv, sys, collections, hashlib
from datetime import datetime, timezone
import yaml

ROOT       = "/opt/ecom-intel/combined-vault"
JIVO_DIR   = os.path.join(ROOT, "jivo")
ECOM_DIR   = os.path.join(ROOT, "ecom")
PROD_DIR   = os.path.join(ROOT, "products")
HUB_DIR    = os.path.join(ROOT, "hubs")

BRIDGE_F   = "/opt/ecom-intel/docs/jivo-databank/sku-bridge/bridge_result.json"
MATCH_F    = "/opt/ecom-intel/docs/jivo-databank/sku-bridge/core_matches.json"
JSKU_F     = "/opt/ecom-intel/docs/jivo-databank/sku-bridge/jivo_skus.json"
PRICEM_F   = "/opt/ecom-intel/data/pricematch/history.csv"
TARGET_F   = "/root/jivo-intel/docs/app-model/target-history.csv"

MARKER = "<!-- combined-backbone -->"

# ---- 10 canonical platform hubs (per task) -----------------------------------
HUB_PLATFORMS = ["amazon", "swiggy", "blinkit", "zepto", "flipkart",
                 "flipkart_grocery", "jiomart", "bigbasket", "citymall", "zomato"]

def hub_platform(p):
    """Map any platform label (ecom slug / target-history name) to one of the 10 hubs."""
    if not p:
        return None
    k = str(p).strip().lower().replace(" ", "_").replace("-", "_")
    table = {
        "amazon": "amazon", "amazon_mp": "amazon", "amazon_now": "amazon",
        "amazon_fresh": "amazon",
        "flipkart": "flipkart", "flipkart_mp": "flipkart", "flipkart_minutes": "flipkart",
        "flipkart_grocery": "flipkart_grocery",
        "bigbasket": "bigbasket", "blinkit": "blinkit", "zepto": "zepto",
        "swiggy": "swiggy", "citymall": "citymall", "zomato": "zomato",
        "jiomart": "jiomart",
    }
    return table.get(k)  # dealshare / unknown -> None

# Known raw platform slugs that may appear in filenames (longest-first for prefix match)
RAW_SLUGS = ["flipkart_grocery", "flipkart-minutes", "amazon-fresh", "amazon-now",
             "flipkart", "bigbasket", "blinkit", "zepto", "swiggy", "citymall",
             "zomato", "jiomart", "dealshare", "amazon"]

# ---- TIER classifier (per task spec; name-token derived + category override) -
def tier_of(name, category=None):
    n = " " + name.lower() + " "
    # SEEDS (edible snack seeds) are never an oil tier. Evaluate BEFORE the
    # sunflower / oil token rules so "SUNFLOWER SEEDS" does not fall into COMMODITY.
    if category == "SEEDS" or "seeds" in n:
        return "OTHER"
    # OLIVE category is always premium. Catches SANO CLASSIC, whose name carries
    # no olive / extra-light token but whose JIVO category is OLIVE.
    if category == "OLIVE":
        return "PREMIUM"
    if "yellow mustard" in n:
        return "PREMIUM"
    premium = ["canola", "groundnut", "pomace", "extra light", "extra-light",
               "extra virgin", "virgin", "olive", "sesame", "coconut", "ghee"]
    if any(t in n for t in premium):
        return "PREMIUM"
    commodity = ["mustard kacchi ghani", "mustard kachi ghani", "kacchi ghani",
                 "kachi ghani", "mustard", "sunflower", "soyabean", "rice bran", "gold"]
    if any(t in n for t in commodity):
        return "COMMODITY"
    return "OTHER"

TIER_TITLE = {"PREMIUM": "Premium", "COMMODITY": "Commodity", "OTHER": "Other"}

# ---- category derivation fallback (when no jivo note category) ---------------
def derive_category(name):
    n = name.lower()
    pairs = [
        ("rice bran", "RICE BRAN"), ("canola", "CANOLA"), ("coconut", "COCONUT"),
        ("groundnut", "GROUNDNUT"), ("sesame", "SESAME OIL"), ("soyabean", "SOYABEAN"),
        ("sunflower oil", "SUNFLOWER"),
        ("pomace", "OLIVE"), ("extra light", "OLIVE"), ("extra virgin", "OLIVE"),
        ("so olive", "OLIVE"), ("olive", "OLIVE"),
        ("gold", "BLENDED"),
        ("yellow mustard", "MUSTARD"), ("mustard", "MUSTARD"),
        ("ghee", "GHEE"),
        ("basil", "SEEDS"), ("chia", "SEEDS"), ("flax", "SEEDS"), ("pumpkin", "SEEDS"),
        ("quinoa", "SEEDS"), ("sunflower seeds", "SEEDS"), ("seeds", "SEEDS"),
        ("pepper", "SPICES"), ("cardamom", "SPICES"), ("clove", "SPICES"),
        ("cumin", "SPICES"), ("cinnamon", "SPICES"), ("saffron", "SPICES"),
        ("rosemary", "SPICES"), ("jeera", "SPICES"),
        ("water", "DRINKS"), ("soda", "DRINKS"), ("shikanji", "DRINKS"),
        ("juice", "DRINKS"), ("cola", "DRINKS"), ("tonic", "DRINKS"),
        ("ginger ale", "DRINKS"), ("coffee", "DRINKS"),
        ("sliced olive", "SLICED OLIVE"), ("black olive", "SLICED OLIVE"),
        ("sunflower", "SUNFLOWER"),
    ]
    for tok, cat in pairs:
        if tok in n:
            return cat
    return "OTHER"

def parse_pack(name):
    m = re.findall(r"\d+\s*(?:\+\s*\d+\s*)*(?:l\b|ltr|litre|ml\b|mls\b|gms\b|gm\b|g\b|kg\b)",
                   name, flags=re.I)
    return ", ".join(x.strip() for x in m) if m else "—"

def normalize_key(name):
    """Pack-spelling-invariant identity key so spelling twins collapse to ONE node.

    Collapses: '200 GM'/'200GM'/'150 GMS' -> grams; '500 MLS' -> '500ML';
    '1 LTR'/'1 LITRE' -> '1L'; combo '1L + 1L'/'1L+1L' -> '1+1L'; 'CHIASEEDS'
    vs 'CHIA SEEDS' (all whitespace removed); case; and ghee ecom '500ML' that
    means weight '500G'. Used only to GROUP product display-names — never alters
    the displayed name or any source note.
    """
    s = name.upper()
    s = re.sub(r"(\d)\s*GMS?\b", r"\1G", s)                   # 200 GM / 200GM / 150 GMS
    s = re.sub(r"(\d)\s*MLS\b", r"\1ML", s)                   # 500 MLS -> 500ML
    s = re.sub(r"(\d)\s*(?:LTR|LITRES?|LITER)\b", r"\1L", s)  # 1 LTR / 1 LITRE -> 1L
    s = re.sub(r"(\d)\s*KGS?\b", r"\1KG", s)                  # 1 KG / 1KGS -> 1KG
    s = re.sub(r"\s+", "", s)                                 # remove all whitespace
    s = re.sub(r"(\d)L\+", r"\1+", s)                         # combo: 1L+1L -> 1+1L
    if "GHEE" in s:                                           # ghee ecom mislabels weight as ml
        s = re.sub(r"(\d)ML", r"\1G", s)
    return s

def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None

def fmt_l(x):
    return f"{x:,.0f}" if x else "0"

def read_frontmatter(text):
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    try:
        fm = yaml.safe_load(parts[1])
        return fm if isinstance(fm, dict) else {}
    except Exception:
        return {}

def slug_link(s):
    # sanitize a wikilink target basename
    return s.replace("/", "-").replace("[", "(").replace("]", ")").replace("|", "-")

# =============================================================================
# LOAD INPUTS
# =============================================================================
bridge = json.load(open(BRIDGE_F))
core_list = bridge["core"]
new_confirmed = bridge["new_confirmed"]
core_matches = json.load(open(MATCH_F))          # name -> {platform: canonical}
jivo_skus = json.load(open(JSKU_F))              # SAP -> name

# ---- curated identity-correction layer (OUR authority over upstream name errors) ----
# Applied BEFORE grouping so a renamed product collapses into the correct node via the
# EXISTING twin-merge (union of SAP codes + canonical listings). Fixes upstream SAP-master
# typos / ecom listing-name drift we cannot fix at the source. See name_overrides.json.
# Fully reversible: remove an entry and rebuild. Pure name->name.
_OVR_F = os.path.join(os.path.dirname(os.path.abspath(__file__)), "name_overrides.json")
RENAME = {}
if os.path.exists(_OVR_F):
    try:
        _ovr = json.load(open(_OVR_F))
        RENAME = {k: v["to"] for k, v in _ovr.get("rename", {}).items()
                  if isinstance(v, dict) and v.get("to")}
    except Exception as _e:                       # never let a bad override file break the build
        print(f"[override] WARN could not load {_OVR_F}: {_e}", file=sys.stderr)

def _ren(nm):
    return RENAME.get(nm, nm)

def _rename_keys(d, mergefn):
    """Rename dict keys via RENAME, merging values when two keys collide post-rename."""
    out = {}
    for k, v in d.items():
        nk = _ren(k)
        out[nk] = v if nk not in out else mergefn(out[nk], v)
    return out

if RENAME:
    jivo_skus = {sap: _ren(nm) for sap, nm in jivo_skus.items()}
    core_list = [_ren(n) for n in core_list]
    core_matches = _rename_keys(core_matches, lambda a, b: {**a, **b})              # name->{plat:canon}
    new_confirmed = _rename_keys(new_confirmed,
                                 lambda a, b: list(dict.fromkeys(list(a) + list(b))))  # name->[canon]
    print(f"[override] applied {len(RENAME)} rename(s): "
          + "; ".join(f"{k} -> {v}" for k, v in RENAME.items()), file=sys.stderr)

name2saps = collections.defaultdict(list)
for sap, nm in jivo_skus.items():
    name2saps[nm].append(sap)
for nm in name2saps:
    name2saps[nm].sort()

# matched products (core first, then new_confirmed; disjoint by inspection)
products = list(core_list) + [n for n in new_confirmed if n not in set(core_list)]

# ---- pricematch: latest row per (canonical_sku, platform) and (sku, platform)
pm_latest_canon = {}
pm_latest_name = {}
with open(PRICEM_F) as fh:
    for r in csv.DictReader(fh):
        kc = (r["canonical_sku"], r["platform"])
        kn = (r["sku"], r["platform"])
        if r["canonical_sku"] and (kc not in pm_latest_canon or r["date"] > pm_latest_canon[kc]["date"]):
            pm_latest_canon[kc] = r
        if kn not in pm_latest_name or r["date"] > pm_latest_name[kn]["date"]:
            pm_latest_name[kn] = r

# ---- target-history 2026 tier-level aggregates ------------------------------
# th[(tier, hubplat, source)] = liters ; also platform totals & tier totals
th = collections.defaultdict(float)
th_plat = collections.defaultdict(float)       # (hubplat, source) -> liters
th_tier = collections.defaultdict(float)       # (tier, source) -> liters
th_years = set()
with open(TARGET_F) as fh:
    for r in csv.DictReader(fh):
        if r["year"] != "2026":
            continue
        tier = r["item_head"].strip().upper()
        hp = hub_platform(r["platform"])
        src = r["source"]
        v = fnum(r["done_ltrs"]) or 0.0
        if hp:
            th[(tier, hp, src)] += v
            th_plat[(hp, src)] += v
        th_tier[(tier, src)] += v
        th_years.add(r["year"])

# =============================================================================
# BUILD PER-PRODUCT MODEL
# =============================================================================
def ecom_note_exists(canon):
    return os.path.exists(os.path.join(ECOM_DIR, "skus", canon + ".md"))

# same guard for JIVO sku notes: the app can delist a SKU (e.g. FG0000075/FG0000162 on
# 2026-07-08), removing jivo/skus/sku-<SAP>.md while the sku-bridge still carries the SAP.
# A dead [[sku-...]] wikilink fails verify_databank and aborts the whole daily fusion.
def jivo_sku_note_exists(sap):
    return os.path.exists(os.path.join(JIVO_DIR, "skus", f"sku-{sap}.md"))

# cache ecom note frontmatter platforms for new_confirmed canonicals
def ecom_note_platforms(canon):
    p = os.path.join(ECOM_DIR, "skus", canon + ".md")
    if not os.path.exists(p):
        return []
    fm = read_frontmatter(open(p, encoding="utf-8", errors="replace").read())
    pls = fm.get("platforms") or []
    return pls if isinstance(pls, list) else [pls]

# jivo note category for a product (via its SAPs)
def jivo_category(saps):
    for sap in saps:
        p = os.path.join(JIVO_DIR, "skus", f"sku-{sap}.md")
        if os.path.exists(p):
            fm = read_frontmatter(open(p, encoding="utf-8", errors="replace").read())
            if fm.get("category"):
                return str(fm["category"]).strip(), fm
    return None, {}

PRODUCT_MODEL = {}   # primary name -> dict
canon2product = {}   # canonical -> product name (for injection)
sap2product = {}     # SAP -> product name (for injection)

# ---- collapse spelling twins: group product names by normalized identity key --
# Pack-spelling variants ("200 GM"/"200G", "1L + 1L"/"1+1L", "CHIASEEDS"/"CHIA
# SEEDS", ghee "500ML"/"500G", case) fork ONE physical product into multiple
# bridge entries; here they merge into ONE node carrying BOTH the JIVO SKU(s) and
# the ecom links. NOTE: only display-names are grouped — no source note is touched.
groups = collections.defaultdict(list)
for name in products:
    groups[normalize_key(name)].append(name)

def primary_score(nm):
    """Choose the display name within a twin group: prefer a JIVO-master spelling
    (one that carries a SAP), then a clean '1+1L' over '1L + 1L', then the shorter
    spelling, then the one with more SAPs, then lexicographic — fully deterministic."""
    has_sap = 1 if name2saps.get(nm) else 0
    nsaps = len(name2saps.get(nm, []))
    spaced_plus = 1 if " + " in nm else 0
    return (-has_sap, spaced_plus, len(nm), -nsaps, nm)

twin_merges = []   # [(primary, [merged-away members])]

for key, members in groups.items():
    members = sorted(members, key=primary_score)
    name = members[0]                       # primary display name for the node
    if len(members) > 1:
        twin_merges.append((name, members[1:]))

    # union SAP codes across all members (JIVO-master spellings carry the SAP)
    saps = []
    for mem in members:
        for s in name2saps.get(mem, []):
            if s not in saps:
                saps.append(s)
    for s in saps:
        sap2product[s] = name

    # union platform -> canonical mapping (core_matches + new_confirmed) across members
    plat_canon = {}                      # raw platform slug -> canonical
    extra_canons = []
    for mem in members:
        if mem in core_matches:
            for plat, canon in core_matches[mem].items():
                plat_canon.setdefault(plat, canon)
        for canon in new_confirmed.get(mem, []):
            pls = ecom_note_platforms(canon)
            for pl in pls:
                plat_canon.setdefault(pl, canon)
            extra_canons.append(canon)

    # all canonicals (for ecom-note fusion + index)
    all_canons = list(dict.fromkeys(list(plat_canon.values()) + extra_canons))
    ecom_notes = [c for c in all_canons if ecom_note_exists(c)]
    for c in all_canons:
        canon2product.setdefault(c, name)

    cat, jfm = jivo_category(saps)
    if not cat:
        cat = derive_category(name)
    tier = tier_of(name, cat)
    per_unit = jfm.get("per_unit_value")
    sub_cat = jfm.get("sub_category")
    brand = jfm.get("brand")

    # competitor-price lens rows (name fallback tries every member spelling)
    lens = []
    for plat in sorted(plat_canon):
        canon = plat_canon[plat]
        row = pm_latest_canon.get((canon, plat))
        if not row:
            for mem in members:
                row = pm_latest_name.get((mem, plat))
                if row:
                    break
        if row:
            lens.append({
                "platform": plat, "canon": canon,
                "ref": row["ref_price"], "live": row["live_modal"],
                "diff_pct": row["diff_pct"], "status": row["status"],
                "date": row["date"], "regime": row["regime"],
            })
        else:
            lens.append({"platform": plat, "canon": canon, "ref": "", "live": "",
                         "diff_pct": "", "status": "—", "date": "", "regime": ""})

    PRODUCT_MODEL[name] = {
        "name": name, "saps": saps, "cat": cat, "sub_cat": sub_cat, "brand": brand,
        "tier": tier, "per_unit": per_unit, "pack": parse_pack(name),
        "plat_canon": plat_canon, "all_canons": all_canons,
        "ecom_notes": ecom_notes, "lens": lens,
        "is_core": any(mem in core_matches for mem in members),
    }

# distinct categories among matched products -> category hubs
CATEGORIES = sorted({m["cat"] for m in PRODUCT_MODEL.values()})

# product -> hub platform set
def product_hub_platforms(m):
    hubs = []
    for plat in m["plat_canon"]:
        hp = hub_platform(plat)
        if hp and hp not in hubs:
            hubs.append(hp)
    return hubs

# =============================================================================
# WRITE PRODUCT NOTES
# =============================================================================
os.makedirs(PROD_DIR, exist_ok=True)
os.makedirs(HUB_DIR, exist_ok=True)
# Idempotency: products/ and hubs/ are 100% generated by this tool. Clear stale
# *.md so renamed/merged nodes never leave orphaned twin files behind. (Source
# notes under jivo/ and ecom/ are NEVER touched here.)
for _d in (PROD_DIR, HUB_DIR):
    for _f in os.listdir(_d):
        if _f.endswith(".md"):
            os.remove(os.path.join(_d, _f))

STATUS_BADGE = {"BELOW": "🟢 BELOW", "MATCH": "🟦 MATCH", "ABOVE": "🔴 ABOVE",
                "OOS": "⚪ OOS", "NOT_LISTED": "⚫ NOT_LISTED",
                "PENDING_REVIEW": "🟡 PENDING", "—": "—"}

price_lens_coverage = 0
unfused = []

for name, m in PRODUCT_MODEL.items():
    safe = slug_link(name)
    L = []
    cat_link = f"Category - {m['cat']}"
    tier_link = f"Tier - {TIER_TITLE[m['tier']]}"
    hub_pls = product_hub_platforms(m)

    # frontmatter
    L.append("---")
    L.append("type: product")
    L.append(f"product: {json.dumps(name)}")
    if m["saps"]:
        L.append("sap_codes:")
        for s in m["saps"]:
            L.append(f"  - {s}")
    L.append(f"category: {json.dumps(m['cat'])}")
    L.append(f"tier: {m['tier']}")
    L.append("platforms:")
    for hp in hub_pls:
        L.append(f"  - {hp}")
    L.append("tags:")
    L.append("  - type/product")
    L.append(f"  - tier/{m['tier']}")
    L.append(f"  - category/{slug_link(m['cat']).replace(' ', '-')}")
    for hp in hub_pls:
        L.append(f"  - platform/{hp}")
    L.append("---")
    L.append("")
    L.append(f"# {name}")
    L.append("")
    L.append("Up: [[Home]]")
    L.append("")

    # identity
    L.append("## Identity")
    L.append("| Field | Value |")
    L.append("|---|---|")
    L.append(f"| Product | {name} |")
    L.append(f"| JIVO SKU / SAP code | {', '.join(f'`{s}`' for s in m['saps']) if m['saps'] else '—'} |")
    canon_cell = ", ".join(f"`{c}`" for c in m["all_canons"]) if m["all_canons"] else "—"
    L.append(f"| canonical_sku(s) | {canon_cell} |")
    L.append(f"| Category | [[{cat_link}\\|{m['cat']}]] |")
    if m["sub_cat"]:
        L.append(f"| Sub-category | {m['sub_cat']} |")
    if m["brand"]:
        L.append(f"| Brand | {m['brand']} |")
    L.append(f"| TIER | [[{tier_link}\\|{TIER_TITLE[m['tier']]}]] *(name-token derived)* |")
    L.append(f"| Pack(s) | {m['pack']} |")
    if m["per_unit"]:
        L.append(f"| Per-unit | {m['per_unit']} L |")
    L.append(f"| Bridge class | {'core (priced)' if m['is_core'] else 'new_confirmed'} |")
    L.append("")

    # competitor-price lens
    L.append("## Competitor-price lens")
    L.append(f"*Per platform — JIVO ref/floor vs latest live competitor price (pricematch, latest = {max([r['date'] for r in m['lens'] if r['date']], default='n/a')}).*")
    L.append("")
    has_data = any(r["date"] for r in m["lens"])
    if m["lens"]:
        L.append("| Platform | Ref/Floor ₹ | Live ₹ | Diff % | Violation | Regime | Latest |")
        L.append("|---|---|---|---|---|---|---|")
        for r in m["lens"]:
            badge = STATUS_BADGE.get(r["status"], r["status"])
            L.append(f"| [[Platform - {hub_platform(r['platform']) or r['platform']}\\|{r['platform']}]] "
                     f"| {r['ref'] or '—'} | {r['live'] or '—'} | {r['diff_pct'] or '—'} "
                     f"| {badge} | {r['regime'] or '—'} | {r['date'] or '—'} |")
        L.append("")
    else:
        L.append("_No platform mapping with pricematch coverage._")
        L.append("")
    if has_data:
        price_lens_coverage += 1

    # JIVO lens (tier-level)
    L.append("## JIVO lens")
    L.append(f"*TIER-LEVEL ({TIER_TITLE[m['tier']]}) 2026 sell-through from target-history — shared across all "
             f"{TIER_TITLE[m['tier']]} products, NOT product-specific (JIVO rows key on platform item_id, no canonical join).*")
    L.append("")
    if m["tier"] in ("PREMIUM", "COMMODITY"):
        L.append("| Platform (hub) | 2026 Secondary (L) | 2026 Primary (L) |")
        L.append("|---|---|---|")
        any_row = False
        for hp in HUB_PLATFORMS:
            sec = th.get((m["tier"], hp, "secondary"), 0.0)
            pri = th.get((m["tier"], hp, "primary"), 0.0)
            if sec or pri:
                any_row = True
                L.append(f"| [[Platform - {hp}]] | {fmt_l(sec)} | {fmt_l(pri)} |")
        if not any_row:
            L.append("| — | — | — |")
        tot_sec = th_tier.get((m["tier"], "secondary"), 0.0)
        tot_pri = th_tier.get((m["tier"], "primary"), 0.0)
        L.append(f"| **All platforms** | **{fmt_l(tot_sec)}** | **{fmt_l(tot_pri)}** |")
    else:
        L.append("_OTHER tier is not tracked in target-history (PREMIUM/COMMODITY only)._")
    L.append("")

    # Connections (cross-vault fusion)
    L.append("## Connections")
    L.append("Cross-vault fusion by name / SKU match:")
    jivo_links = [f"[[sku-{s}]]" if jivo_sku_note_exists(s) else f"`sku-{s}` *(delisted from app)*"
                  for s in m["saps"]]
    ecom_links = [f"[[{c}]]" for c in m["ecom_notes"]]
    L.append(f"- **JIVO source notes:** {' · '.join(jivo_links) if jivo_links else '_(none found)_'}")
    L.append(f"- **Ecom source notes:** {' · '.join(ecom_links) if ecom_links else '_(none found)_'}")
    L.append(f"- **Category:** [[{cat_link}]]")
    L.append(f"- **TIER:** [[{tier_link}]]")
    if hub_pls:
        L.append(f"- **Platforms:** {' · '.join(f'[[Platform - {hp}]]' for hp in hub_pls)}")
    L.append("")

    if not jivo_links and not ecom_links:
        unfused.append(name)

    with open(os.path.join(PROD_DIR, safe + ".md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))

# =============================================================================
# WRITE HUB NOTES
# =============================================================================
# group products
by_cat = collections.defaultdict(list)
by_tier = collections.defaultdict(list)
by_plat = collections.defaultdict(list)
for name, m in PRODUCT_MODEL.items():
    by_cat[m["cat"]].append(name)
    by_tier[m["tier"]].append(name)
    for hp in product_hub_platforms(m):
        by_plat[hp].append(name)

def plink(name):
    return f"[[{slug_link(name)}]]"

# tier of category (dominant) for category hub aggregate
def cat_dom_tier(cat):
    cnt = collections.Counter(PRODUCT_MODEL[n]["tier"] for n in by_cat[cat])
    return cnt.most_common(1)[0][0]

# ---- Category hubs ----
for cat in CATEGORIES:
    members = sorted(by_cat[cat])
    dt = cat_dom_tier(cat)
    L = ["---", "type: hub", "hub_kind: category", f"category: {json.dumps(cat)}",
         "tags:", "  - type/hub", "  - hub/category", "---", "",
         f"# Category - {cat}", "", "Up: [[Home]]", "",
         f"**{len(members)} matched products** · dominant tier "
         f"[[Tier - {TIER_TITLE[dt]}\\|{TIER_TITLE[dt]}]]", "",
         "## Member products"]
    for n in members:
        m = PRODUCT_MODEL[n]
        L.append(f"- {plink(n)} — {TIER_TITLE[m['tier']]} · {m['pack']}")
    L.append("")
    L.append("## 2026 aggregate (tier-level proxy)")
    L.append(f"*Category-level sales are not tracked; showing the dominant-tier "
             f"({TIER_TITLE[dt]}) 2026 sell-through. See [[Tier - {TIER_TITLE[dt]}]].*")
    L.append("")
    if dt in ("PREMIUM", "COMMODITY"):
        L.append(f"- Secondary (L): **{fmt_l(th_tier.get((dt,'secondary'),0))}**")
        L.append(f"- Primary (L): **{fmt_l(th_tier.get((dt,'primary'),0))}**")
    else:
        L.append("- _OTHER tier not tracked in target-history._")
    L.append("")
    with open(os.path.join(HUB_DIR, f"Category - {slug_link(cat)}.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))

# ---- Platform hubs (all 10) ----
for hp in HUB_PLATFORMS:
    members = sorted(by_plat.get(hp, []))
    L = ["---", "type: hub", "hub_kind: platform", f"platform: {hp}",
         "tags:", "  - type/hub", "  - hub/platform", f"  - platform/{hp}", "---", "",
         f"# Platform - {hp}", "", "Up: [[Home]]", "",
         f"**{len(members)} matched products listed here.**", ""]
    L.append("## 2026 aggregate (target-history)")
    sec = th_plat.get((hp, "secondary"), 0.0)
    pri = th_plat.get((hp, "primary"), 0.0)
    if sec or pri:
        L.append(f"- Secondary (L): **{fmt_l(sec)}**  ·  Primary (L): **{fmt_l(pri)}**")
        L.append("")
        L.append("| Tier | Secondary (L) | Primary (L) |")
        L.append("|---|---|---|")
        for t in ("PREMIUM", "COMMODITY"):
            s = th.get((t, hp, "secondary"), 0.0)
            p = th.get((t, hp, "primary"), 0.0)
            if s or p:
                L.append(f"| [[Tier - {TIER_TITLE[t]}\\|{TIER_TITLE[t]}]] | {fmt_l(s)} | {fmt_l(p)} |")
    else:
        L.append("- _No 2026 target-history rows for this platform._")
    L.append("")
    L.append("## Member products")
    if members:
        for n in members:
            m = PRODUCT_MODEL[n]
            lensrow = next((r for r in m["lens"] if hub_platform(r["platform"]) == hp and r["date"]), None)
            extra = ""
            if lensrow:
                extra = f" — ref ₹{lensrow['ref'] or '—'} / live ₹{lensrow['live'] or '—'} ({STATUS_BADGE.get(lensrow['status'], lensrow['status'])})"
            L.append(f"- {plink(n)}{extra}")
    else:
        L.append("_No matched products mapped to this platform hub._")
    L.append("")
    with open(os.path.join(HUB_DIR, f"Platform - {hp}.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))

# ---- Tier hubs (Premium / Commodity / Other) ----
for t in ("PREMIUM", "COMMODITY", "OTHER"):
    members = sorted(by_tier.get(t, []))
    title = TIER_TITLE[t]
    L = ["---", "type: hub", "hub_kind: tier", f"tier: {t}",
         "tags:", "  - type/hub", "  - hub/tier", f"  - tier/{t}", "---", "",
         f"# Tier - {title}", "", "Up: [[Home]]", "",
         f"**{len(members)} matched products** in the {title} tier.", ""]
    L.append("## 2026 aggregate (target-history)")
    if t in ("PREMIUM", "COMMODITY"):
        L.append(f"- Secondary (L): **{fmt_l(th_tier.get((t,'secondary'),0))}**  ·  "
                 f"Primary (L): **{fmt_l(th_tier.get((t,'primary'),0))}**")
        L.append("")
        L.append("| Platform | Secondary (L) | Primary (L) |")
        L.append("|---|---|---|")
        for hp in HUB_PLATFORMS:
            s = th.get((t, hp, "secondary"), 0.0)
            p = th.get((t, hp, "primary"), 0.0)
            if s or p:
                L.append(f"| [[Platform - {hp}]] | {fmt_l(s)} | {fmt_l(p)} |")
    else:
        L.append("- _OTHER tier not tracked in target-history (PREMIUM/COMMODITY only)._")
    L.append("")
    L.append("## Member products")
    for n in members:
        m = PRODUCT_MODEL[n]
        L.append(f"- {plink(n)} — [[Category - {m['cat']}\\|{m['cat']}]] · {m['pack']}")
    L.append("")
    with open(os.path.join(HUB_DIR, f"Tier - {title}.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))

# ---- Home MOC ----
L = ["---", "type: moc", "tags:", "  - type/moc", "---", "",
     "# Home — Combined JIVO × Ecom Backbone", "",
     "Cross-vault fusion layer linking JIVO app data (sell-through, SAP SKUs) with "
     "ecom competitor price intelligence (canonical listings) via the SKU bridge.", "",
     f"- **Matched products:** {len(PRODUCT_MODEL)}  ([[#Products]])",
     f"- **Category hubs:** {len(CATEGORIES)}",
     f"- **Platform hubs:** {len(HUB_PLATFORMS)}",
     "- **Tier hubs:** 3 (Premium / Commodity / Other)",
     "- **Source vaults:** `jivo/` (app data) · `ecom/` (price intel)", "",
     "## Tiers"]
for t in ("PREMIUM", "COMMODITY", "OTHER"):
    L.append(f"- [[Tier - {TIER_TITLE[t]}]] — {len(by_tier.get(t, []))} products")
L.append("")
L.append("## Platforms")
for hp in HUB_PLATFORMS:
    L.append(f"- [[Platform - {hp}]] — {len(by_plat.get(hp, []))} products")
L.append("")
L.append("## Categories")
for cat in CATEGORIES:
    L.append(f"- [[Category - {cat}]] — {len(by_cat[cat])} products")
L.append("")
L.append("## Products")
for n in sorted(PRODUCT_MODEL):
    L.append(f"- {plink(n)}")
L.append("")

# ---- Gaps / Unmatched (JIVO SKUs the bridge could NOT map to an ecom listing) -
no_ecom = bridge.get("no_ecom", [])
needs_help = bridge.get("needs_help", [])
L.append("## Gaps / Unmatched")
L.append(f"JIVO SKUs the bridge could **not** map to an ecom listing "
         f"({len(no_ecom) + len(needs_help)} total) — no product node is minted for these, "
         f"so they are surfaced here (not silently dropped). Source: `bridge_result.json`.")
L.append("")
L.append(f"**No ecom match ({len(no_ecom)}):**")
for nm in sorted(no_ecom):
    saps = name2saps.get(nm, [])
    cell = " · ".join(f"[[sku-{s}|{nm}]]" if jivo_sku_note_exists(s) else f"{nm} (`sku-{s}` delisted)"
                      for s in saps) if saps else nm
    L.append(f"- {cell}")
L.append("")
L.append(f"**Needs review ({len(needs_help)}):**")
for item in needs_help:
    nm = item.get("jivo", "")
    saps = name2saps.get(nm, [])
    cell = " · ".join(f"[[sku-{s}|{nm}]]" if jivo_sku_note_exists(s) else f"{nm} (`sku-{s}` delisted)"
                      for s in saps) if saps else nm
    reason = str(item.get("reason", "")).replace("[[", "").replace("]]", "")
    L.append(f"- {cell} — _{item.get('conf', '')} confidence_: {reason}")
L.append("")

# ---- Vault notes (link the otherwise-orphan JIVO session-memory scratch note) -
L.append("## Vault notes")
L.append("- [[SESSION-MEMORY]] — JIVO vault session / handoff memory")
L.append("")

with open(os.path.join(ROOT, "Home.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(L))

n_products = len(PRODUCT_MODEL)
n_hubs = len(CATEGORIES) + len(HUB_PLATFORMS) + 3
n_twin_members = sum(len(others) for _, others in twin_merges)
ecom_only = [n for n, m in PRODUCT_MODEL.items() if m["ecom_notes"] and not m["saps"]]
tier_counts = collections.Counter(m["tier"] for m in PRODUCT_MODEL.values())
print(f"[build] products={n_products} hubs={n_hubs} categories={len(CATEGORIES)} "
      f"price_lens_coverage={price_lens_coverage} unfused={len(unfused)} "
      f"twin_groups={len(twin_merges)} twin_members_merged={n_twin_members} "
      f"ecom_only_nodes={len(ecom_only)} "
      f"tiers=P{tier_counts['PREMIUM']}/C{tier_counts['COMMODITY']}/O{tier_counts['OTHER']}",
      flush=True)

# =============================================================================
# AUTO-INJECT '## Related' INTO SOURCE NOTES (jivo + ecom)
# =============================================================================
existing_categories = set(CATEGORIES)

SAP_RE = re.compile(r"\b((?:FG|SL)\d{6,8})\b")

def detect_platforms_from_name(fn):
    found = set()
    low = fn.lower()
    for slug in RAW_SLUGS:
        # match slug as a token boundary in filename
        if re.search(r"(?:^|[^a-z])" + re.escape(slug) + r"(?:[^a-z0-9]|$)", low):
            hp = hub_platform(slug)
            if hp:
                found.add(hp)
    return found

def related_for_note(path, fname, fm, parent):
    links = []  # ordered, deduped later

    def add(x):
        if x not in links:
            links.append(x)

    # ---- product links via SAP ----
    saps_here = set()
    for s in SAP_RE.findall(fname):
        saps_here.add(s)
    fmsap = fm.get("sku_sap_code")
    if fmsap:
        saps_here.add(str(fmsap))
    fmskus = fm.get("skus")
    if isinstance(fmskus, list):
        for s in fmskus:
            saps_here.add(str(s))
    for s in sorted(saps_here):
        if s in sap2product:
            add(f"[[{slug_link(sap2product[s])}]]")

    # ---- product links via canonical (ecom) ----
    stem = fname[:-3] if fname.endswith(".md") else fname
    if stem in canon2product:
        add(f"[[{slug_link(canon2product[stem])}]]")
    fmcanon = fm.get("canonical_sku")
    if fmcanon and fmcanon in canon2product:
        add(f"[[{slug_link(canon2product[fmcanon])}]]")

    # ---- platform hubs ----
    plats = set()
    fmpl = fm.get("platforms")
    if isinstance(fmpl, list):
        for p in fmpl:
            hp = hub_platform(p)
            if hp:
                plats.add(hp)
    elif isinstance(fmpl, str):
        hp = hub_platform(fmpl)
        if hp:
            plats.add(hp)
    plats |= detect_platforms_from_name(stem)
    if parent:  # ecom runs/<platform>/..., daily etc.
        hp = hub_platform(parent)
        if hp:
            plats.add(hp)
    for hp in sorted(plats):
        add(f"[[Platform - {hp}]]")

    # ---- category hubs ----
    cats = set()
    m = re.match(r"cat-(.+)$", stem)
    if m:
        c = m.group(1).replace("-", " ").upper()
        if c in existing_categories:
            cats.add(c)
    fmcat = fm.get("category")
    if fmcat and str(fmcat).strip().upper() in existing_categories:
        cats.add(str(fmcat).strip().upper())
    for c in sorted(cats):
        add(f"[[Category - {c}]]")

    # ---- tier hubs ----
    tiers = set()
    mt = re.match(r"tier-(PREMIUM|COMMODITY|OTHER)$", stem, re.I)
    if mt:
        tiers.add(mt.group(1).upper())
    fmih = fm.get("item_head")
    if fmih and str(fmih).strip().upper() in ("PREMIUM", "COMMODITY", "OTHER"):
        tiers.add(str(fmih).strip().upper())
    for t in sorted(tiers):
        add(f"[[Tier - {TIER_TITLE[t]}]]")

    return links

BLOCK_RE = re.compile(r"\n*## Related\n" + re.escape(MARKER) + r".*?(?=\n## |\Z)", re.S)

links_injected = 0
notes_touched = 0
scanned = 0

for base in (JIVO_DIR, ECOM_DIR):
    for dirpath, _dirs, files in os.walk(base):
        parent = os.path.basename(dirpath)
        for f in files:
            if not f.endswith(".md"):
                continue
            scanned += 1
            path = os.path.join(dirpath, f)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            fm = read_frontmatter(text)
            links = related_for_note(path, f, fm, parent)
            if not links:
                continue
            block = "\n\n## Related\n" + MARKER + "\n" + " · ".join(links) + "\n"
            new_text = BLOCK_RE.sub("", text)          # idempotent: strip old block
            new_text = new_text.rstrip("\n") + "\n" + block
            if new_text != text:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new_text)
                notes_touched += 1
                links_injected += len(links)
            if scanned % 5000 == 0:
                print(f"[inject] scanned={scanned} touched={notes_touched} links={links_injected}", flush=True)

print(f"[inject] DONE scanned={scanned} notes_touched={notes_touched} links_injected={links_injected}", flush=True)

# =============================================================================
# REGENERATE .manifest.json  (HONEST lossless proof of the link-injected vault)
# =============================================================================
def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def _scan(root):
    fmap = {}
    nbytes = 0
    for dp, _dn, fns in os.walk(root, followlinks=False):
        for fn in fns:
            full = os.path.join(dp, fn)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            fmap[rel] = full
            nbytes += os.path.getsize(full)
    return fmap, nbytes

def write_manifest():
    """Write an HONEST .manifest.json against the on-disk, link-injected combined
    vault. Records each vault's SOURCE count/bytes/aggregate-sha256 (proof the copy
    is faithful) and DEST count/bytes (larger, because a '## Related' link layer is
    APPENDED). Zero-loss is proven PER FILE: every source file's original bytes must
    be an EXACT BYTE-PREFIX of its combined-vault copy. 'bytes_match' is intentionally
    NOT asserted — dest exceeds source by the appended layer, by design."""
    pairs = {"jivo": ("/root/jivo-intel/vault", JIVO_DIR),
             "ecom": ("/opt/ecom-intel/vault", ECOM_DIR)}
    vaults = {}
    all_ok = True
    for vname, (src_root, dst_root) in pairs.items():
        src_map, src_bytes = _scan(src_root)
        dst_map, dst_bytes = _scan(dst_root)
        missing = sorted(set(src_map) - set(dst_map))
        extra = sorted(set(dst_map) - set(src_map))
        src_hashes, altered, truncated = [], [], []
        appended = 0
        for rel in sorted(src_map):
            sp = src_map[rel]
            src_hashes.append(_sha256_file(sp))
            dp = dst_map.get(rel)
            if not dp:
                continue
            ssz = os.path.getsize(sp)
            dsz = os.path.getsize(dp)
            if dsz < ssz:
                truncated.append(rel)
                continue
            with open(sp, "rb") as a, open(dp, "rb") as b:
                if b.read(ssz) != a.read():
                    altered.append(rel)
                else:
                    appended += (dsz - ssz)
        agg = hashlib.sha256("\n".join(sorted(src_hashes)).encode("utf-8")).hexdigest()
        prefix_ok = not (altered or truncated or missing or extra)
        all_ok = all_ok and prefix_ok
        vaults[vname] = {
            "source_path": src_root,
            "dest_path": dst_root,
            "source": {"count": len(src_map), "bytes": src_bytes, "aggregate_sha256": agg},
            "dest": {"count": len(dst_map), "bytes": dst_bytes},
            "appended_link_layer_bytes": dst_bytes - src_bytes,
            "lossless": {
                "original_prefix_preserved_all": prefix_ok,
                "n_altered": len(altered),
                "n_truncated": len(truncated),
                "missing_in_dest": missing[:50],
                "extra_in_dest": extra[:50],
                "files_altered": altered[:50],
                "files_truncated": truncated[:50],
            },
        }
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "tool": "/opt/ecom-intel/bin/combined_backbone.py",
        "combined_vault": ROOT,
        "design_note": (
            "Source vaults are copied verbatim, then a '## Related' wikilink layer is "
            "APPENDED to source notes that reference a known SKU/canonical/product/"
            "platform/category. Therefore DEST bytes EXCEED SOURCE bytes BY DESIGN. "
            "Zero-loss is proven per file: each source file's original bytes are preserved "
            "as an EXACT BYTE-PREFIX of its combined-vault copy (n_altered=n_truncated=0). "
            "'bytes_match' is intentionally NOT claimed; the honest signal is "
            "original_prefix_preserved_all."),
        "aggregate_hash_method": "sha256 over sorted list of per-file SOURCE sha256 hex digests",
        "vaults": vaults,
        "summary": {
            "jivo_source_notes": vaults["jivo"]["source"]["count"],
            "ecom_source_notes": vaults["ecom"]["source"]["count"],
            "combined_dest_notes": sum(v["dest"]["count"] for v in vaults.values()),
            "source_bytes": sum(v["source"]["bytes"] for v in vaults.values()),
            "dest_bytes": sum(v["dest"]["bytes"] for v in vaults.values()),
            "appended_link_layer_bytes": sum(v["appended_link_layer_bytes"] for v in vaults.values()),
            "zero_loss_ok": all_ok,
        },
    }
    with open(os.path.join(ROOT, ".manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"[manifest] zero_loss_ok={all_ok} "
          f"dest_bytes={manifest['summary']['dest_bytes']} "
          f"appended={manifest['summary']['appended_link_layer_bytes']}", flush=True)
    return all_ok

manifest_ok = write_manifest()

# emit machine-readable summary
summary = {
    "products": n_products,
    "hubs": n_hubs,
    "categories": len(CATEGORIES),
    "links_injected": links_injected,
    "notes_touched": notes_touched,
    "price_lens_coverage": price_lens_coverage,
    "unfused": unfused,
    "twin_groups": len(twin_merges),
    "twin_members_merged": n_twin_members,
    "twin_merges": [{"primary": p, "merged": o} for p, o in twin_merges],
    "ecom_only_nodes": ecom_only,
    "tier_counts": dict(tier_counts),
    "manifest_zero_loss_ok": manifest_ok,
}
print("SUMMARY_JSON " + json.dumps(summary))
