#!/usr/bin/env python3
"""
combined_identity.py — mint and stamp OUR OWN stable internal product IDs (JIDs)
onto the JIVO Data Bank, plus detect duplicate-identity conflicts.

Runs AFTER combined_backbone.py + factory_pillar.py, BEFORE verify_databank.py.

WHY THIS EXISTS
  A single physical product wears a different name in price-match, a different
  name in the ecom app, and a different SAP code in the factory master. No upstream
  key survives those drifts. This assigns ONE opaque serial (JID-####) per product
  and records the full crosswalk  JID <-> {SAP codes, ecom canonical listings,
  platforms, category, tier}. The JID is OURS: append-only and immutable. Once a
  product has a JID it never changes or gets reused — even if its display name or
  an upstream code changes, and even when the daily pipeline regenerates every page.

STABILITY (survives the daily REPLACE rebuild)
  * Authoritative registry: <bin>/jid_registry.json — lives in the generator dir,
    NOT in the vault that daily_rebuild.sh wipes, so JIDs persist across rebuilds.
  * Each run, every product page is matched to its existing JID by, in order:
      shared SAP code  ->  shared ecom canonical  ->  normalized name.
    Only a genuinely new product mints the next serial. Products that disappear
    (e.g. merged) keep their JID, flagged "retired" — never deleted, never reissued.

WRITES (into the combined vault → rsynced into the repo)
  * products/*.md       : `jid: JID-####` in frontmatter + an "Internal ID (JID)"
                          row at the TOP of the Identity table.
  * identity/REGISTRY.md : human-readable crosswalk + an Identity-Conflicts review
                          list (canonicals attached to >1 product).
  * identity/registry.json : published machine copy of the registry.

Idempotent. Read-only on jivo/ ecom/ factory/ source notes. Never commits.
Exit 0 on success.
"""
import os, re, json, glob, sys, collections
from datetime import datetime, timezone

BIN      = os.path.dirname(os.path.abspath(__file__))
COMBINED = os.environ.get("JDB_COMBINED", "/opt/ecom-intel/combined-vault")
PROD_DIR = os.path.join(COMBINED, "products")
ID_DIR   = os.path.join(COMBINED, "identity")
REGISTRY = os.environ.get("JDB_JID_REGISTRY", os.path.join(BIN, "jid_registry.json"))
PREFIX   = "JID-"
PAD      = 4


# normalize_key MUST mirror combined_backbone.normalize_key so our "same product"
# test matches the generator's grouping identity exactly.
def normalize_key(name):
    s = name.upper()
    s = re.sub(r"(\d)\s*GMS?\b", r"\1G", s)
    s = re.sub(r"(\d)\s*MLS\b", r"\1ML", s)
    s = re.sub(r"(\d)\s*(?:LTR|LITRES?|LITER)\b", r"\1L", s)
    s = re.sub(r"(\d)\s*KGS?\b", r"\1KG", s)
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"(\d)L\+", r"\1+", s)
    if "GHEE" in s:
        s = re.sub(r"(\d)ML", r"\1G", s)
    return s


def jid_str(n):
    return f"{PREFIX}{n:0{PAD}d}"


def parse_product(path):
    txt = open(path, encoding="utf-8").read()
    name = os.path.basename(path)[:-3]
    fm = txt.split("---", 2)[1] if txt.startswith("---") else ""
    saps = re.findall(r"\b((?:FG|SL)\d{6,8})\b", fm)
    m = re.search(r"\|\s*canonical_sku\(s\)\s*\|(.+?)\|", txt)
    canons = re.findall(r"`([^`]+)`", m.group(1)) if m else []
    catm = re.search(r'^category:\s*"?([^"\n]+?)"?\s*$', fm, re.M)
    tierm = re.search(r'^tier:\s*(\S+)', fm, re.M)
    return {"name": name, "path": path, "txt": txt,
            "saps": list(dict.fromkeys(saps)),
            "canons": list(dict.fromkeys(canons)),
            "category": catm.group(1).strip() if catm else "",
            "tier": tierm.group(1).strip() if tierm else "",
            "norm": normalize_key(name)}


def load_registry():
    if os.path.exists(REGISTRY):
        try:
            r = json.load(open(REGISTRY))
            if isinstance(r, dict) and "entries" in r:
                return r
        except Exception as e:
            print(f"[identity] WARN unreadable registry ({e}); starting fresh", file=sys.stderr)
    return {"prefix": PREFIX, "next_serial": 1, "entries": {}}


def stamp_page(p, jid):
    """Idempotently write `jid:` into frontmatter and an Internal-ID row into the
    Identity table. Returns the new text (also written to disk)."""
    txt = p["txt"]
    if not txt.startswith("---"):
        return txt
    head, fm, body = txt.split("---", 2)
    # frontmatter: drop any old jid line, then add after `type: product`
    lines = [l for l in fm.split("\n") if not re.match(r"\s*jid:\s*JID-", l)]
    out, done = [], False
    for l in lines:
        out.append(l)
        if not done and re.match(r"\s*type:\s*product\b", l):
            out.append(f"jid: {jid}")
            done = True
    if not done:
        out = ["", f"jid: {jid}"] + out[1:] if out and out[0] == "" else [f"jid: {jid}"] + out
    fm = "\n".join(out)
    # body: drop any old Internal-ID row, then add as the FIRST Identity data row
    body = re.sub(r"\n\|\s*Internal ID \(JID\)\s*\|[^\n]*\|", "", body)
    body, n = re.subn(r"(## Identity\n\| Field \| Value \|\n\|---\|---\|)",
                      r"\1\n| Internal ID (JID) | `" + jid + "` |", body, count=1)
    new = head + "---" + fm + "---" + body
    with open(p["path"], "w", encoding="utf-8") as fh:
        fh.write(new)
    return new


def cluster_hint(names):
    """Heuristic so the reviewer isn't told to merge things that must not merge."""
    has_combo = any("+" in n for n in names)
    has_single = any("+" not in n for n in names)
    if has_combo and has_single:
        return "combo-vs-single pack — likely DO NOT MERGE (distinct SKUs; a canonical is mis-attached)"
    return "name variant — likely same product, review then add to name_overrides.json"


def write_registry_md(reg, prods, assigned, clusters, jid2names):
    os.makedirs(ID_DIR, exist_ok=True)
    active = [(assigned[p["name"]], p) for p in sorted(prods, key=lambda x: assigned[x["name"]])]
    retired = [(j, e) for j, e in sorted(reg["entries"].items()) if e.get("status") == "retired"]
    L = []
    L.append("---")
    L.append("type: identity-registry")
    L.append("tags:\n  - type/identity-registry")
    L.append("---")
    L.append("")
    L.append("# JIVO Data Bank — Internal Product ID Registry (JID)")
    L.append("")
    L.append("Up: [[Home]]")
    L.append("")
    L.append("> **Our own serial identity.** Every physical product gets ONE opaque, immutable "
             "internal ID (`JID-####`) that we control — independent of the names it wears in "
             "price-match, the ecom app, or the factory SAP master. Match a product across any of "
             "those systems via its SAP code(s) or ecom canonical listing(s) below. Source of truth: "
             "`bin/jid_registry.json` (append-only). Stamped onto every product page's frontmatter "
             "(`jid:`) and Identity table.")
    L.append("")
    L.append(f"- **Active products:** {len(active)}")
    L.append(f"- **Retired/merged JIDs (kept, never reused):** {len(retired)}")
    L.append(f"- **Highest serial minted:** {jid_str(reg['next_serial']-1) if reg['next_serial']>1 else '—'}")
    L.append(f"- **Identity conflicts to review:** {len(clusters)}")
    L.append(f"- **Generated:** {datetime.now(timezone.utc).isoformat()}")
    L.append("")
    L.append("## Registry — JID ↔ product ↔ external keys")
    L.append("| JID | Product (our canonical) | SAP code(s) — app/factory | Ecom canonical listing(s) | Category | Tier |")
    L.append("|---|---|---|---|---|---|")
    for jid, p in active:
        saps = ", ".join(f"`{s}`" for s in p["saps"]) or "—"
        canons = (", ".join(f"`{c}`" for c in p["canons"][:3]) +
                  (f" … +{len(p['canons'])-3}" if len(p["canons"]) > 3 else "")) or "—"
        L.append(f"| `{jid}` | [[{p['name']}]] | {saps} | {canons} | {p['category']} | {p['tier']} |")
    L.append("")
    if clusters:
        L.append("## ⚠ Identity Conflicts (same ecom listing on >1 product — needs human call)")
        L.append("")
        L.append("Each cluster below shares one or more ecom canonical listings across different product "
                 "nodes. Some are true duplicates (fold together via `name_overrides.json`); some are "
                 "combo-vs-single packs that must stay separate (the shared canonical is mis-attached "
                 "and should be removed from one side). **Not auto-resolved — your call.**")
        L.append("")
        for key in sorted(clusters, key=lambda k: tuple(k)):
            names = [jid2names[j] for j in key]
            L.append(f"- **{' ⟷ '.join('`'+j+'`' for j in key)}** — "
                     f"{' · '.join('[['+n+']]' for n in names)}")
            L.append(f"  - _hint:_ {cluster_hint(names)}")
            shared = sorted(clusters[key])
            L.append(f"  - _shared listing(s):_ {', '.join('`'+c+'`' for c in shared[:4])}"
                     + (f" … +{len(shared)-4}" if len(shared) > 4 else ""))
        L.append("")
    if retired:
        L.append("## Retired / merged JIDs (immutable — kept, never reissued)")
        for j, e in retired:
            L.append(f"- `{j}` — was “{e.get('name','?')}” (saps {e.get('saps') or '—'})")
        L.append("")
    with open(os.path.join(ID_DIR, "REGISTRY.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))


def main():
    prods = [parse_product(p) for p in sorted(glob.glob(os.path.join(PROD_DIR, "*.md")))]
    if not prods:
        print("FATAL: no product pages found", file=sys.stderr)
        sys.exit(2)
    reg = load_registry()
    entries = reg["entries"]

    sap2jid, norm2jid = {}, {}
    for jid, e in entries.items():
        for s in e.get("saps", []):
            sap2jid.setdefault(s, jid)
        if e.get("norm"):
            norm2jid.setdefault(e["norm"], jid)

    def match(p):
        # Match a product NODE to its prior JID by STABLE identity: SAP set first
        # (SAP codes are disjoint across nodes), else the normalized name (the unique
        # grouping key — one node per norm). Canonical listings are DELIBERATELY not a
        # match key: colliding canonicals across combo/single packs must NOT collapse
        # two nodes onto one JID — they are surfaced as conflicts instead. Returns the
        # lowest matching JID for determinism (handles a future approved merge cleanly).
        cands = set()
        for s in p["saps"]:
            if s in sap2jid:
                cands.add(sap2jid[s])
        if not cands and p["norm"] in norm2jid:
            cands.add(norm2jid[p["norm"]])
        return min(cands) if cands else None

    def sortkey(p):                       # deterministic first-time minting order
        return (0 if p["saps"] else 1, p["saps"][0] if p["saps"] else "", p["norm"])

    next_serial = reg.get("next_serial", 1)
    assigned = {}
    for p in sorted(prods, key=sortkey):
        jid = match(p)
        if jid is None:
            jid = jid_str(next_serial)
            next_serial += 1
            entries[jid] = {}
        e = entries[jid]
        e.update({"name": p["name"], "saps": p["saps"], "canons": p["canons"],
                  "category": p["category"], "tier": p["tier"], "norm": p["norm"],
                  "status": "active"})
        for s in p["saps"]:
            sap2jid.setdefault(s, jid)
        norm2jid.setdefault(p["norm"], jid)
        assigned[p["name"]] = jid

    live = set(assigned.values())
    for jid, e in entries.items():
        if jid not in live and e.get("status") != "retired":
            e["status"] = "retired"

    reg["next_serial"] = next_serial
    reg["prefix"] = PREFIX
    reg["_doc"] = ("OUR own append-only internal product-ID registry for the JIVO Data Bank. "
                   "JID = opaque immutable serial per physical product, bridging price-match / "
                   "ecom-app / factory names via SAP code(s) and ecom canonical listing(s). "
                   "Managed by bin/combined_identity.py. Never hand-edit JIDs.")
    reg["updated_at"] = datetime.now(timezone.utc).isoformat()

    jid2names = {assigned[p["name"]]: p["name"] for p in prods}

    # collision scan: a canonical listing seen on >1 JID = duplicate identity
    canon_jids = collections.defaultdict(set)
    for p in prods:
        for c in p["canons"]:
            canon_jids[c].add(assigned[p["name"]])
    clusters = {}
    for c, jids in canon_jids.items():
        if len(jids) > 1:
            clusters.setdefault(tuple(sorted(jids)), set()).add(c)

    for p in prods:
        stamp_page(p, assigned[p["name"]])

    write_registry_md(reg, prods, assigned, clusters, jid2names)
    with open(os.path.join(ID_DIR, "registry.json"), "w") as fh:
        json.dump(reg, fh, indent=2, sort_keys=True)
        fh.write("\n")
    with open(REGISTRY, "w") as fh:                 # authoritative, persistent
        json.dump(reg, fh, indent=2, sort_keys=True)
        fh.write("\n")

    print(f"[identity] products={len(prods)} active_jids={len(live)} "
          f"retired={sum(1 for e in entries.values() if e.get('status')=='retired')} "
          f"next_serial={next_serial} conflicts={len(clusters)}", file=sys.stderr)
    print("IDENTITY_JSON " + json.dumps({
        "products": len(prods), "active_jids": len(live),
        "conflicts": len(clusters), "next_serial": next_serial}))
    sys.exit(0)


if __name__ == "__main__":
    main()
