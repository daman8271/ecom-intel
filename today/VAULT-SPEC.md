---
title: Vault Spec
aliases:
  - VAULT-SPEC
tags:
  - meta/spec
  - moc
created: 2026-05-21
updated: 2026-05-29
version: 2
---

# Memory Vault — Design Spec & Obsidian Conventions (v2)

> Single source of truth for **how** the `vault/` Markdown memory works and **which** Obsidian
> conventions we follow — and **why**. Read this before touching `tools/vault_build.py`.

This vault is the **human-readable + machine-readable memory** of the ecom-intel Jivo price
scraper. The complete, append-only observation history lives in `data/<platform>/history.csv`
(one row per `run × SKU × location`); the vault is the **fully-linked Obsidian knowledge graph
view of that same data**. Every note is regenerated deterministically from the CSV, so the graph
and the table never drift.

> **v2 changes (2026-05-29):** the vault now stores **complete** data (every observation, not
> summaries), adds **per-SKU / per-city / per-pincode** entity nodes, and uses **real-basename
> links** instead of alias links (v1 relied on aliases, which Obsidian does **not** resolve — see
> §2.2, the most important correction in this version). One generator, `tools/vault_build.py`,
> rebuilds the whole graph from the CSV. All illustrative links below are written in `code` so
> they don't pollute the graph as placeholder nodes.

---

## 1. Obsidian mechanics that drive the design (verified)

Verified against the official Help (`obsidian.md/help`), the changelog, and forum staff posts
(sources at the bottom). The facts that shape every decision below:

1. **Wikilinks resolve by _basename_** — folder path and the `.md` extension are ignored, and
   matching is **case-insensitive**. So **every note basename must be globally unique**; a
   duplicate basename silently mis-resolves (Obsidian picks one, no warning). The build asserts
   uniqueness and aborts on any collision.
2. **Aliases do NOT resolve a bare link.** A hand-written `[[some alias]]` does **not** point to
   the note that declares that alias — Obsidian only ever inserts the `[[RealName|alias]]` form
   via autocomplete. **Therefore links must target the real basename.** (v1's `[[blinkit (platform
   hub)]]`-style links were dead placeholders on import — fixed in v2.)
3. **Graph edges come from _body_ wikilinks only.** Frontmatter "Link"-type properties do **not**
   create graph edges in core Obsidian; **tags do not create edges** between notes either. So
   every structural relationship is a plain `[[wikilink]]` in the note **body**; frontmatter is
   metadata/query only.
4. **Large rendered tables freeze Obsidian** (staff-reproduced jank starts in the low hundreds of
   rows). A vault of thousands of notes + tens of thousands of links is fine, but a single big
   rendered table is not. **Complete data therefore lives in fenced ` ```csv ` code blocks**
   (cheap to render at any size); rendered Markdown tables are kept short (summaries only).
5. **Tags** allow letters/digits/`_`/`-`/`/` but **must contain a non-numeric char** — a bare
   `#110001` is invalid, so numeric facets are prefixed (`#pin/110001`).
6. **Filename/link-safe characters:** `[ ] # ^ |` (and `/ \ :`) break filenames and links; spaces
   and numbers are fine. Basenames are normalized accordingly.
7. **Zero plugins required.** Body links, graph, properties and tags are all core; nothing here
   needs Dataview/Bases. A minimal `.obsidian/graph.json` (color groups by note-type/platform) is
   shipped so the graph is legible on first open.
8. **YAML:** spaces (never tabs), `---` on line 1, UTF-8 (no BOM), no wikilinks inside
   frontmatter, scalars with `: # | [ ]` quoted.

---

## 2. Conventions we adopt

### 2.1 Globally-unique, clean basenames
Resolution is by basename, so every basename is unique across the whole vault. Run notes are
platform-prefixed (the bare run-id would collide between platforms in the same window). Entity
nodes use their natural identifier; the build normalizes away unsafe characters and verifies
uniqueness.

### 2.2 Links target the REAL basename (no alias reliance)
Because a bare `[[alias]]` does not resolve, the generator emits the **real basename** as the
link target (optionally `[[basename|display]]` for nicer display). Frontmatter `aliases:` may
still be present for human search/autocomplete, but the graph never depends on it.

### 2.3 Body links carry the graph; frontmatter is metadata
Every structural edge is a `[[wikilink]]` in the body (nav lines, "SKUs seen", "Cities covered",
hub link-lists). Frontmatter holds flat, machine-parseable metadata + facet `tags:` only.

### 2.4 Complete data in code blocks, summaries in tables
Each note's full record is a fenced ` ```csv ` block (every relevant row). Short rendered tables
(run index, cheapest-observed) are summaries for humans; they never carry the full dataset.

### 2.5 Canonical link-name map (real basenames)

| Concept | File | Wikilink |
|---|---|---|
| Home MOC | `vault/index.md` | `[[index]]` |
| Platform hub | `vault/platforms/<p>.md` | `[[<p>]]` |
| Run note | `vault/runs/<p>/<p>-<RUN_ID>.md` | `[[<p>-<RUN_ID>]]` |
| SKU hub | `vault/skus/<slug>.md` | `[[<slug>]]` |
| SKU MOC | `vault/skus/skus-index.md` | `[[skus-index]]` |
| City hub | `vault/locations/<City>.md` | `[[<City>]]` |
| Pincode node | `vault/locations/pincodes/<pin>.md` | `[[<pin>]]` |
| Locations MOC | `vault/locations/locations-index.md` | `[[locations-index]]` |
| Daily | `vault/daily/<YYYY-MM-DD>.md` | `[[<YYYY-MM-DD>]]` |
| Weekly | `vault/weekly/<YYYY-Www>.md` | `[[<YYYY-Www>]]` (ISO `%G-W%V`) |
| Monthly | `vault/monthly/<YYYY-MM>.md` | `[[<YYYY-MM>]]` |

(The `[[…]]` entries above are written in code so they document the format without becoming graph nodes.)

### 2.6 Tags = facets (filter, color the graph)
`type/<run|sku-hub|city-hub|pincode|platform-hub|daily|weekly|monthly>`, `platform/<p>`,
`verdict/<V>`, `shape/<national|per-pincode>`, `pin/<pincode>`, plus `moc`/`home`.

---

## 3. Graph topology

```
                              index   (Home MOC)
              /        |          |            |          \
     platform hubs     |     skus-index   locations-index   time spine
        |              |        |                 |
   run note  ----------+-->  SKU hub          City hub --> pincode node
   (complete csv of    |    (price history    (its pincodes (its SKUs +
    every observation) |     + cities + runs)  + SKUs)        csv)
        |              |
        v              v
     daily   ----->  weekly  ----->  monthly      (linked both directions)
```

A run note links **up** to its platform hub, day/week/month, prev/next run, and **out** to every
SKU hub and city it observed. SKU hubs link to their platforms, cities and runs; city hubs link
their pincodes and SKUs; pincode nodes link up to their city. Daily↔weekly↔monthly link both
directions. The MOCs (`skus-index`, `locations-index`) are intentional high-degree hubs.

---

## 4. Machine-readable history (the source of truth)

`data/<platform>/history.csv`, one row per `(run, SKU, location)`:

```
run_id,date_ist,platform,canonical_sku,city,pincode,price,mrp,discount_pct,in_stock
```

Append-only across runs; national platforms emit `city="All India", pincode="-"`. The vault is
regenerated **from this file**, so historical notes are limited to these columns (display names,
pack, store, per-litre etc. exist only in the latest `platforms/<p>/result.json` and are used
as best-effort enrichment for SKU display names).

---

## 5. The generator & pipeline

- **`tools/vault_build.py`** — the single deterministic, stdlib-only rebuilder. Reads all
  `data/*/history.csv` (+ best-effort enrichment from `platforms/*/result.json` and verdicts from
  `reviews/*.json`) and regenerates the **entire** vault: run notes, SKU/city/pincode hubs, the
  two MOCs, platform hubs, daily/weekly/monthly rollups, `index.md`, and `.obsidian/`. Idempotent
  (identical CSVs → byte-identical vault); asserts globally-unique basenames; run with `--check`
  or plain (it always verifies uniqueness and exits non-zero on a collision).
- **Live pipeline:** `run.sh` (per platform, in parallel) scrapes and **appends the run's rows to
  `history.csv`**; `run_all.sh` then runs `tools/vault_build.py` **once** after the sweep + heal
  pass (single process, so the whole-graph rebuild never races the parallel platforms) and
  git-pushes. Cron: one deadline-aligned sweep landing 12:00 noon + 18:00 guardian.

`tools/vault_note.py` / `tools/vault_rollup.py` (v1) remain in `run.sh` as the per-run CSV-append +
provisional notes; `vault_build.py` is the authority and overwrites them with the complete,
connected graph at the end of every sweep.

---

## Sources
- Obsidian Help — [Internal links](https://obsidian.md/help/Linking+notes+and+files/Internal+links) · [Aliases](https://obsidian.md/help/aliases) · [Graph view](https://obsidian.md/help/plugins/graph) · [Tags](https://obsidian.md/help/tags) · [Properties](https://obsidian.md/help/properties)
- Forum — [aliases not honored in wikilink resolution](https://forum.obsidian.md/t/wikilink-resolution-does-not-honor-frontmatter-aliases/113902) · [large table slowness](https://forum.obsidian.md/t/large-markdown-table-causes-slowness/78593) · [forbidden filename characters](https://forum.obsidian.md/t/list-of-all-forbidden-filename-characters/103977)
- [Obsidian Rocks — Maps of Content](https://obsidian.rocks/maps-of-content-effortless-organization-for-notes/)
