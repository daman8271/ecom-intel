#!/usr/bin/env python3
"""
factory_pillar.py — add the JIVO factory (Jivo Mart) vault as the 4th pillar of
the JIVO Data Bank. Runs AFTER combined_backbone.py, BEFORE verify_databank.py.

Additive + low-risk (does NOT touch jivo/ ecom/ products/ generation logic):
  1. Copy /root/jivo-factory-intel/vault -> COMBINED/factory/  VERBATIM (zero-loss).
  2. Merge factory's per-file prefix-preservation proof into .manifest.json,
     extending summary so combined_dest_notes == sum(all vault source counts)
     and zero_loss_ok stays honest across all pillars.
  3. Build the factory->product SAP bridge: append a '## Factory lens' section to
     every product node whose FG#### SAP code is referenced by factory records
     (manufacturing/supply lens), with resolvable [[wikilinks]] into factory/.
  4. Append a 'Factory pillar' pointer to Home.md.

Idempotent: re-running re-copies factory/, recomputes the manifest from the full
vault set, and skips product/Home appends that are already present.
"""
import os, json, shutil, hashlib, re, sys
from datetime import datetime, timezone

FACTORY_SRC = os.environ.get("JDB_FACTORY_SRC", "/root/jivo-factory-intel/vault")
COMBINED    = os.environ.get("JDB_COMBINED", "/opt/ecom-intel/combined-vault")
FACTORY_DST = os.path.join(COMBINED, "factory")
MANIFEST    = os.path.join(COMBINED, ".manifest.json")
PROD_DIR    = os.path.join(COMBINED, "products")
HOME        = os.path.join(COMBINED, "Home.md")
BRIDGE_JSON = os.path.join(FACTORY_SRC, "_bridge.json")
CHUNK = 1 << 20


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(CHUNK), b""):
            h.update(b)
    return h.hexdigest()


def scan(root):
    fmap, nbytes = {}, 0
    for dp, dns, fns in os.walk(root, followlinks=False):
        dns.sort()
        for n in sorted(fns):
            full = os.path.join(dp, n)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            fmap[rel] = full
            nbytes += os.path.getsize(full)
    return fmap, nbytes


def factory_manifest_entry():
    """Verbatim copy => prefix-preserved exactly (appended layer = 0)."""
    src_map, src_bytes = scan(FACTORY_SRC)
    dst_map, dst_bytes = scan(FACTORY_DST)
    missing = sorted(set(src_map) - set(dst_map))
    extra   = sorted(set(dst_map) - set(src_map))
    src_hashes, altered, truncated = [], [], []
    for rel in sorted(src_map):
        sp = src_map[rel]
        src_hashes.append(sha256_file(sp))
        dp = dst_map.get(rel)
        if not dp:
            continue
        ssz, dsz = os.path.getsize(sp), os.path.getsize(dp)
        if dsz < ssz:
            truncated.append(rel)
        else:
            with open(sp, "rb") as a, open(dp, "rb") as b:
                if b.read(ssz) != a.read():
                    altered.append(rel)
    agg = hashlib.sha256("\n".join(sorted(src_hashes)).encode("utf-8")).hexdigest()
    prefix_ok = not (altered or truncated or missing or extra)
    return prefix_ok, {
        "source_path": FACTORY_SRC,
        "dest_path": FACTORY_DST,
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


def merge_manifest(factory_entry):
    man = json.load(open(MANIFEST))
    man.setdefault("vaults", {})["factory"] = factory_entry
    vaults = man["vaults"]
    s = man["summary"]
    s["factory_source_notes"] = vaults["factory"]["source"]["count"]
    s["combined_dest_notes"] = sum(v["dest"]["count"] for v in vaults.values())
    s["source_bytes"] = sum(v["source"]["bytes"] for v in vaults.values())
    s["dest_bytes"] = sum(v["dest"]["bytes"] for v in vaults.values())
    s["appended_link_layer_bytes"] = sum(v["appended_link_layer_bytes"] for v in vaults.values())
    s["zero_loss_ok"] = all(v["lossless"]["original_prefix_preserved_all"] for v in vaults.values())
    s["pillars"] = sorted(vaults.keys())
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=2, sort_keys=True)
        f.write("\n")
    return s


def humanize(slug):
    return slug.split("__")[-1].replace("-", " ")


def build_bridge():
    """Append '## Factory lens' to product nodes whose FG codes appear in factory."""
    if not os.path.isfile(BRIDGE_JSON):
        return 0, 0
    bridge = json.load(open(BRIDGE_JSON))   # FG#### -> ["slug/noteid", ...]
    # group factory refs per FG by entity type
    per_fg = {}
    for fg, refs in bridge.items():
        g = {}
        for r in refs:
            slug, noteid = r.rsplit("/", 1)
            g.setdefault(slug, []).append(noteid)
        per_fg[fg] = g
    bridged_products, bridged_links = 0, 0
    for pf in sorted(os.listdir(PROD_DIR)):
        if not pf.endswith(".md"):
            continue
        path = os.path.join(PROD_DIR, pf)
        txt = open(path, encoding="utf-8").read()
        if "## Factory lens" in txt:
            continue  # idempotent
        fm = txt.split("---", 2)[1] if txt.startswith("---") else ""
        fgs = [c for c in re.findall(r"FG\d+", fm) if c in per_fg]
        if not fgs:
            continue
        lines = ["", "## Factory lens (Jivo Mart manufacturing / supply)",
                 "> Where this product's SAP item code(s) appear in the JIVO_MART factory "
                 "(`ji.jivo.in`) — gate, traceability, QC, dispatch. Source: `factory/`.", ""]
        for fg in sorted(set(fgs)):
            lines.append(f"**`{fg}`** — referenced by factory records:")
            groups = per_fg[fg]
            # oitm (SAP item master) first if present
            order = sorted(groups, key=lambda s: (0 if "oitm" in s else 1, -len(groups[s])))
            for slug in order:
                ids = groups[slug]
                label = humanize(slug)
                samples = " · ".join(f"[[{i}]]" for i in ids[:3])
                more = f" … +{len(ids)-3} more (tag `bridge/{fg}`)" if len(ids) > 3 else ""
                lines.append(f"- **{len(ids)} {label}:** {samples}{more}")
                bridged_links += min(len(ids), 3)
            lines.append("")
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        bridged_products += 1
    return bridged_products, bridged_links


def patch_home(summary):
    txt = open(HOME, encoding="utf-8").read() if os.path.isfile(HOME) else ""
    if "## Factory pillar" in txt:
        return
    fn = summary.get("factory_source_notes", 0)
    block = ["", "## Factory pillar — Jivo Mart (JIVO_MART)",
             f"The 4th data pillar: a lossless capture of the `ji.jivo.in` factory app for "
             f"**Jivo Mart** — gate, vehicles, quality control, GRPO, barcode traceability, "
             f"dispatch, and SAP item master ({fn:,} notes). Bridged to products above by SAP "
             f"item code (FG####) — see each product's **Factory lens**.",
             "", "- [[factory/_HOME|Factory — Home (Jivo Mart)]]", ""]
    with open(HOME, "a", encoding="utf-8") as f:
        f.write("\n".join(block) + "\n")


def main():
    if not os.path.isdir(FACTORY_SRC):
        print(f"FATAL: factory source missing: {FACTORY_SRC}", file=sys.stderr)
        sys.exit(2)
    print(f"[factory] copytree {FACTORY_SRC} -> {FACTORY_DST}", file=sys.stderr)
    if os.path.isdir(FACTORY_DST):
        shutil.rmtree(FACTORY_DST)
    shutil.copytree(FACTORY_SRC, FACTORY_DST, symlinks=False)

    prefix_ok, entry = factory_manifest_entry()
    summary = merge_manifest(entry)
    bp, bl = build_bridge()
    patch_home(summary)

    print(f"[factory] prefix_ok={prefix_ok} notes={entry['source']['count']} "
          f"bridged_products={bp} bridge_links={bl} "
          f"combined_dest_notes={summary['combined_dest_notes']} "
          f"zero_loss_ok={summary['zero_loss_ok']}", file=sys.stderr)
    print("FACTORY_PILLAR_JSON " + json.dumps({
        "prefix_ok": prefix_ok, "factory_notes": entry["source"]["count"],
        "bridged_products": bp, "bridge_links": bl,
        "zero_loss_ok": summary["zero_loss_ok"]}))
    sys.exit(0 if prefix_ok and summary["zero_loss_ok"] else 1)


if __name__ == "__main__":
    main()
