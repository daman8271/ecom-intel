#!/usr/bin/env python3
"""
combined_migrate.py — LOSSLESS migration of two Obsidian vaults into a single
combined vault, with a checksum proof of zero data loss.

Source A (jivo): /root/jivo-intel/vault   -> /opt/ecom-intel/combined-vault/jivo/
Source B (ecom): /opt/ecom-intel/vault    -> /opt/ecom-intel/combined-vault/ecom/

Strategy
--------
1. Copy the FULL tree of each source with shutil.copytree(..., dirs_exist_ok=True),
   preserving structure + metadata (copy2) for every file (.md + attachments).
2. Build a per-vault fingerprint = { relpath -> sha256(content) } for the source,
   then independently for the freshly-copied dest tree.
3. For each vault compute:
       count   = number of regular files
       bytes   = sum of file sizes
       agg     = sha256 over the SORTED list of per-file sha256 hex digests
   (exactly: sha256("\n".join(sorted(file_hashes)))).
4. Assert dest == source for count, bytes, AND agg hash, for BOTH vaults.
   Additionally assert the full {relpath -> hash} maps are identical, which
   guarantees structure is preserved too (stronger than the three scalars).
5. lossless_ok = True only if every check passes for both vaults.
6. Write /opt/ecom-intel/combined-vault/.manifest.json.
"""

import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone

SOURCES = {
    "jivo": "/root/jivo-intel/vault",
    "ecom": "/opt/ecom-intel/vault",
}
COMBINED = "/opt/ecom-intel/combined-vault"
DESTS = {
    "jivo": os.path.join(COMBINED, "jivo"),
    "ecom": os.path.join(COMBINED, "ecom"),
}
MANIFEST = os.path.join(COMBINED, ".manifest.json")

CHUNK = 1024 * 1024


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def scan_tree(root):
    """Walk root, return (file_map, count, total_bytes).

    file_map: { relative_posix_path : sha256_hex }
    Only regular files are included; symlinks would be flagged (none expected).
    Deterministic walk.
    """
    file_map = {}
    total_bytes = 0
    symlinks = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                symlinks.append(os.path.relpath(full, root))
                continue
            if not os.path.isfile(full):
                # skip anything that is not a regular file (sockets/fifos etc.)
                continue
            rel = os.path.relpath(full, root)
            rel = rel.replace(os.sep, "/")
            file_map[rel] = sha256_file(full)
            total_bytes += os.path.getsize(full)
    if symlinks:
        raise RuntimeError(
            "Symlinks encountered (not handled losslessly here): %s" % symlinks[:10]
        )
    return file_map, len(file_map), total_bytes


def aggregate_hash(file_map):
    """sha256 over the SORTED list of per-file sha256 hex digests."""
    h = hashlib.sha256()
    h.update("\n".join(sorted(file_map.values())).encode("utf-8"))
    return h.hexdigest()


def fingerprint(file_map):
    """Path-aware fingerprint: sha256 over sorted 'relpath\\0hash' lines.

    This is stronger than aggregate_hash because it also pins structure/paths.
    """
    h = hashlib.sha256()
    for rel in sorted(file_map):
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        h.update(file_map[rel].encode("utf-8"))
        h.update(b"\n")
    return h.hexdigest()


def main():
    # Pre-flight: sources must exist.
    for name, src in SOURCES.items():
        if not os.path.isdir(src):
            print("FATAL: source %s missing: %s" % (name, src), file=sys.stderr)
            sys.exit(2)

    os.makedirs(COMBINED, exist_ok=True)

    per_vault = {}
    all_ok = True

    for name, src in SOURCES.items():
        dst = DESTS[name]
        print("[%s] copytree %s -> %s" % (name, src, dst), file=sys.stderr)
        # FULL tree copy, preserve structure + metadata, every file.
        shutil.copytree(src, dst, dirs_exist_ok=True, symlinks=False)

        print("[%s] scanning source ..." % name, file=sys.stderr)
        src_map, src_count, src_bytes = scan_tree(src)
        print("[%s] scanning dest ..." % name, file=sys.stderr)
        dst_map, dst_count, dst_bytes = scan_tree(dst)

        src_agg = aggregate_hash(src_map)
        dst_agg = aggregate_hash(dst_map)
        src_fp = fingerprint(src_map)
        dst_fp = fingerprint(dst_map)

        count_ok = src_count == dst_count
        bytes_ok = src_bytes == dst_bytes
        agg_ok = src_agg == dst_agg
        fp_ok = src_fp == dst_fp  # path-aware, includes structure
        maps_identical = src_map == dst_map

        vault_ok = count_ok and bytes_ok and agg_ok and fp_ok and maps_identical
        all_ok = all_ok and vault_ok

        # Diagnostics if mismatch.
        missing_in_dst = sorted(set(src_map) - set(dst_map))
        extra_in_dst = sorted(set(dst_map) - set(src_map))
        content_diffs = sorted(
            r for r in (set(src_map) & set(dst_map)) if src_map[r] != dst_map[r]
        )

        per_vault[name] = {
            "source_path": src,
            "dest_path": dst,
            "source": {
                "count": src_count,
                "bytes": src_bytes,
                "aggregate_sha256": src_agg,
                "path_aware_fingerprint": src_fp,
            },
            "dest": {
                "count": dst_count,
                "bytes": dst_bytes,
                "aggregate_sha256": dst_agg,
                "path_aware_fingerprint": dst_fp,
            },
            "checks": {
                "count_match": count_ok,
                "bytes_match": bytes_ok,
                "aggregate_hash_match": agg_ok,
                "path_aware_fingerprint_match": fp_ok,
                "file_maps_identical": maps_identical,
            },
            "diff": {
                "missing_in_dest": missing_in_dst[:50],
                "extra_in_dest": extra_in_dst[:50],
                "content_mismatch": content_diffs[:50],
            },
            "lossless_ok": vault_ok,
        }
        print(
            "[%s] count %d==%d:%s bytes %d==%d:%s agg:%s fp:%s -> %s"
            % (
                name,
                src_count,
                dst_count,
                count_ok,
                src_bytes,
                dst_bytes,
                bytes_ok,
                agg_ok,
                fp_ok,
                "OK" if vault_ok else "FAIL",
            ),
            file=sys.stderr,
        )

    combined_count = sum(v["dest"]["count"] for v in per_vault.values())
    combined_bytes = sum(v["dest"]["bytes"] for v in per_vault.values())

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "tool": "/opt/ecom-intel/bin/combined_migrate.py",
        "combined_vault": COMBINED,
        "aggregate_hash_method": "sha256 over sorted list of per-file sha256 hex digests",
        "vaults": per_vault,
        "summary": {
            "jivo_notes": per_vault["jivo"]["dest"]["count"],
            "ecom_notes": per_vault["ecom"]["dest"]["count"],
            "combined_notes": combined_count,
            "total_bytes": combined_bytes,
            "lossless_ok": all_ok,
        },
    }

    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")

    print("MANIFEST: %s" % MANIFEST, file=sys.stderr)
    print(json.dumps(manifest["summary"], indent=2))

    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
