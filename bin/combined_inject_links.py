#!/usr/bin/env python3
"""
combined_inject_links.py

Read every combined-vault/.links/domain-*.json and inject the discovered
cross-vault links into their 'from' notes as Obsidian wikilinks, under a
'## Related (discovered)' section.

Rules:
  * VALIDATE every link's target ('to') resolves to a real file under the
    combined vault (this also covers hubs/*.md). Links whose target file
    does not exist are SKIPPED and counted as broken_skipped.
  * Injection is IDEMPOTENT: a target that is already linked from the note
    (anywhere in the note, in either path or basename form) is never added
    again. Re-running the script makes no further changes.
  * Wikilinks are emitted in unambiguous vault-relative path form
    ([[dir/note|note]]) because a handful of basenames collide across the
    two source vaults.

Does NOT commit. Prints a JSON summary.
"""

import os
import re
import json
import glob
import sys

VAULT = "/opt/ecom-intel/combined-vault"
LINKS_DIR = os.path.join(VAULT, ".links")
SECTION = "## Related (discovered)"

# Matches [[target]], [[target|alias]], [[target#heading]], ![[embed]] ...
WIKILINK_RE = re.compile(r"!?\[\[([^\[\]]+?)\]\]")
HEADING_RE = re.compile(r"^#{1,6}\s")


def norm_target(raw):
    """Normalize a wikilink inner target to a comparable lowercase string."""
    t = raw.split("|", 1)[0]      # drop alias (handles '\|' table-escaped too)
    t = t.split("#", 1)[0]        # drop heading / block ref
    t = t.strip().rstrip("\\").strip()
    if t.startswith("./"):
        t = t[2:]
    if t.lower().endswith(".md"):
        t = t[:-3]
    return t


def colliding_basenames(vault):
    """Set of lowercased .md basenames that occur more than once in the vault."""
    counts = {}
    for dp, dns, fns in os.walk(vault):
        # skip dotted dirs like .links
        dns[:] = [d for d in dns if not d.startswith(".")]
        for fn in fns:
            if fn.endswith(".md"):
                b = fn[:-3].lower()
                counts[b] = counts.get(b, 0) + 1
    return {b for b, c in counts.items() if c > 1}


def existing_targets(content):
    """Return (full_set, base_set) of normalized lowercase wikilink targets."""
    full = set()
    for m in WIKILINK_RE.finditer(content):
        t = norm_target(m.group(1))
        if t:
            full.add(t.lower())
    base = {os.path.basename(t) for t in full}
    return full, base


def main():
    domain_files = sorted(glob.glob(os.path.join(LINKS_DIR, "domain-*.json")))
    if not domain_files:
        print(json.dumps({"error": "no domain-*.json found", "dir": LINKS_DIR}))
        return 1

    colliding = colliding_basenames(VAULT)

    # Group links by 'from'. Preserve order, dedup (from,to) per note.
    by_from = {}            # from_rel -> list of link dicts
    broken_skipped = 0
    from_missing = 0

    for df in domain_files:
        with open(df, "r", encoding="utf-8") as fh:
            links = json.load(fh)
        for it in links:
            frm = it.get("from", "")
            to = it.get("to", "")
            to_abs = os.path.join(VAULT, to)
            # VALIDATE target exists as a real file under the vault.
            if not (to and os.path.isfile(to_abs)):
                broken_skipped += 1
                continue
            by_from.setdefault(frm, []).append(it)

    links_added = 0
    notes_touched = 0

    for frm, links in by_from.items():
        from_abs = os.path.join(VAULT, frm)
        if not os.path.isfile(from_abs):
            from_missing += 1
            continue

        with open(from_abs, "r", encoding="utf-8") as fh:
            content = fh.read()

        full, base = existing_targets(content)

        new_lines = []
        seen_this_note = set()
        for it in links:
            to = it["to"]
            p_noext = to[:-3] if to.lower().endswith(".md") else to
            p_low = p_noext.lower()
            b = os.path.basename(p_noext)
            b_low = b.lower()

            if p_low in seen_this_note:
                continue

            # Already linked?
            present = p_low in full
            if not present and b_low not in colliding:
                if b_low in full or b_low in base:
                    present = True
            if present:
                seen_this_note.add(p_low)
                continue

            reason = (it.get("reason", "") or "").replace("\n", " ").strip()
            ltype = it.get("link_type", "")
            tag = f" _({ltype})_" if ltype else ""
            line = f"- [[{p_noext}|{b}]] — {reason}{tag}" if reason else f"- [[{p_noext}|{b}]]{tag}"
            new_lines.append(line)
            seen_this_note.add(p_low)
            # so a later identical basename in same note dedups
            full.add(p_low)
            base.add(b_low)

        if not new_lines:
            continue

        lines = content.split("\n")

        # Find existing section header
        hidx = None
        for i, l in enumerate(lines):
            if l.strip() == SECTION:
                hidx = i
                break

        if hidx is None:
            # Append a fresh section at end of file.
            while lines and lines[-1].strip() == "":
                lines.pop()
            lines.append("")
            lines.append(SECTION)
            lines.append("")
            lines.extend(new_lines)
        else:
            # Find end of section (next heading) and insert after existing items.
            end = len(lines)
            for j in range(hidx + 1, len(lines)):
                if HEADING_RE.match(lines[j]):
                    end = j
                    break
            insert_at = end
            while insert_at - 1 > hidx and lines[insert_at - 1].strip() == "":
                insert_at -= 1
            lines[insert_at:insert_at] = new_lines

        new_content = "\n".join(lines)
        if not new_content.endswith("\n"):
            new_content += "\n"

        with open(from_abs, "w", encoding="utf-8") as fh:
            fh.write(new_content)

        links_added += len(new_lines)
        notes_touched += 1

    summary = {
        "links_added": links_added,
        "notes_touched": notes_touched,
        "broken_skipped": broken_skipped,
        "from_missing": from_missing,
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
