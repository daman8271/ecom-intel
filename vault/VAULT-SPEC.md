---
title: Vault Spec
aliases:
  - VAULT-SPEC
  - Memory Vault Design
tags:
  - meta/spec
  - moc
created: 2026-05-21
---

# Memory Vault — Design Spec & Obsidian Conventions

> The single source of truth for **how** the `vault/` Markdown memory works, **which**
> Obsidian conventions we adopt, and **why**. Read this before touching
> `tools/vault_note.py` or `tools/vault_rollup.py`.

This vault is the **human-readable + machine-readable memory** of the ecom-intel
price scraper. Every cron run leaves a permanent, linked note here. The notes form
an Obsidian knowledge graph (browse history, spot trends); the parallel
`data/<platform>/history.csv` is the flat, tidy table a future price-intelligence
ML model trains on.

---

## 1. How Obsidian works (research summary)

Researched from the official Obsidian help, the Obsidian forum, and community
PKM guides (sources at the bottom). The five primitives that matter for us:

### 1.1 `[[Wikilinks]]` — the edges of the graph
- Syntax `[[Note Name]]`. Obsidian resolves a wikilink **by basename, ignoring
  folder path and the `.md` extension** — so `[[2026-05-21]]` finds
  `vault/daily/2026-05-21.md` no matter where the linking note lives.
- **This is the single most important fact for our design:** because resolution is
  by basename, every note basename in the vault must be **globally unique**.
- `[[Note|display text]]` shows custom text but links to `Note`.
- `[[Note#Heading]]` and `[[Note#^block-id]]` link to a section / block.
- Linking to a note that does not exist yet creates an **unresolved ("placeholder")
  link** — it still shows in the graph as a faint node. This lets a run note link
  to its weekly rollup *before* the weekly note is generated; the graph stays
  connected and the placeholder fills in later.

### 1.2 The graph view derives edges from **body links only**
- Official help: *"Lines represent internal links between two nodes."* Nodes =
  notes; an edge = one note containing a `[[wikilink]]` to another. The more
  notes that point at a node, the **bigger** that node renders — so our hubs
  (platform pages, dailies) naturally become large, central nodes.
- **Tags do NOT create edges** between notes in the core graph (they show as a
  separate, optional node class). Frontmatter *property* links (e.g.
  `up: "[[blinkit]]"`) render as edges only in recent Obsidian and only when the
  property is a Link type — version-dependent and fragile.
- **Decision:** every structural relationship we want in the graph is written as
  a plain `[[wikilink]] in the note BODY`. Frontmatter is used for metadata/query
  only, never as the sole carrier of a graph edge. This makes the graph correct on
  every Obsidian version with zero plugins.

### 1.3 YAML frontmatter / properties — metadata, not edges
- A `---` fenced YAML block at the very top of the file. `key: value` pairs.
- Types: text, number, checkbox, date, list, and "links" (a quoted wikilink).
- Used by search, Dataview/Bases queries, and (later) by our ML feature pipeline
  to slice notes (`verdict: SUSPECT`, `platform: blinkit`). We keep frontmatter
  **flat and machine-parseable** so a script can read a note without Markdown
  parsing.

### 1.4 `tags` — faceted classification
- `#tag` or `#nested/tag`; or a `tags:` list in frontmatter (equivalent).
- Tags are for *cross-cutting facets* you filter on (e.g. `#verdict/OK`,
  `#platform/blinkit`, `#shape/per-pincode`), **not** for the primary hierarchy —
  that is what links + folders do.

### 1.5 `aliases` — alternate names a wikilink can resolve to
- `aliases:` list in frontmatter. `[[alias]]` resolves to the note even though the
  filename differs.
- **We exploit this heavily.** The interface contract asks run notes to link
  `[[<platform> (platform hub)]]` and `[[<date> (daily)]]`. Rather than name files
  with those awkward strings, we name files cleanly (`blinkit.md`,
  `2026-05-21.md`) and add the contract names as **aliases**, so both
  `[[blinkit]]` and `[[blinkit (platform hub)]]` resolve to the same hub.

### 1.6 Folders vs. links, and Maps of Content (MOC)
- A note lives in exactly **one folder**, but can be linked from **many** notes.
  Folders give us a tidy filesystem (`runs/`, `daily/`, …); **links give the
  graph its meaning.** We use both: folders for storage, links for relationships.
- A **MOC (Map of Content)** is a note whose job is to *link to other notes* — an
  index/hub for a topic. Hierarchy of MOCs: an **Index/Home MOC** (entry point) →
  **topic/section MOCs**. We adopt this directly:
  - `index.md` = Home MOC (vault entry point).
  - `platforms/<platform>.md` = a per-platform MOC/hub (links every run + describes
    the platform).
  - `daily / weekly / monthly` notes = time-based rollup MOCs.

---

## 2. Conventions we adopt (and why)

| Convention | Rule | Why |
|---|---|---|
| **Globally-unique basenames** | Run notes are `runs/<platform>/<platform>-<RUN_ID>.md`, e.g. `blinkit-2026-05-21-1600.md`. | Wikilinks resolve by basename; `<RUN_ID>` alone (`2026-05-21-1600`) would collide between platforms in the same run window. Prefixing with platform guarantees uniqueness. |
| **Body links carry the graph** | All structural relations are `[[wikilinks]]` in the body. | Graph edges come from body links on every Obsidian version, no plugins (§1.2). |
| **Clean filenames + contract aliases** | Hubs/dailies named cleanly; contract strings (`<platform> (platform hub)`, `<date> (daily)`) added as `aliases`. | Satisfies the interface contract's link names while keeping filenames sane (§1.5). |
| **Frontmatter = flat metadata** | One YAML block, scalar/list values, the exact keys the contract names. | Machine-readable for ML slicing + idempotent regeneration; not relied on for edges. |
| **Tags = facets** | `#platform/<p>`, `#verdict/<V>`, `#shape/<national\|per-pincode>`, `#run`, `#daily`, … | Faceted filtering without polluting the link hierarchy (§1.4). |
| **MOC hierarchy** | `index` → `platforms/<p>` (hub) and `index` → latest dailies. | Standard LYT/MOC pattern; gives the graph clear central hubs (§1.6). |
| **Time spine** | `run → daily → weekly → monthly`, each links *up* and the rollup links *down*. | Bidirectional links = strong, navigable trend backbone; placeholders keep it connected before rollups exist (§1.1). |
| **Idempotent generation** | Re-running a generator for the same RUN_ID/date fully **overwrites** that note and **de-dupes** the CSV by `(run_id, platform, canonical, pincode)`. | Cron retries / self-heal re-runs must not double-count. |
| **Deterministic, stdlib-only** | No LLM, no pip deps; same input → byte-identical output. | Cheap, runs in the cron loop, reproducible history. |

### 2.1 Canonical link-name map (use these exact spellings)

| Concept | File | Wikilink(s) that resolve to it |
|---|---|---|
| Home MOC | `vault/index.md` | `[[index]]`, `[[Jivo Price Intelligence — Index]]` |
| Platform hub | `vault/platforms/<p>.md` | `[[<p>]]`, `[[<p> (platform hub)]]` |
| Run note | `vault/runs/<p>/<p>-<RUN_ID>.md` | `[[<p>-<RUN_ID>]]` |
| Daily | `vault/daily/<YYYY-MM-DD>.md` | `[[<YYYY-MM-DD>]]`, `[[<YYYY-MM-DD> (daily)]]` |
| Weekly | `vault/weekly/<YYYY-Www>.md` | `[[<YYYY-Www>]]`, `[[<YYYY-Www> (weekly)]]` |
| Monthly | `vault/monthly/<YYYY-MM>.md` | `[[<YYYY-MM>]]`, `[[<YYYY-MM> (monthly)]]` |

> Week id is **ISO-8601 week** (`%G-W%V`), so the week a date belongs to is computed
> the same way everywhere (e.g. `2026-05-21` → `2026-W21`).

---

## 3. Graph topology this produces

```
                         [[index]]   (Home MOC)
                        /     |      \
        [[blinkit]]  [[amazon]] [[flipkart]] ...   (platform hubs / MOCs)
            |              |
   +--------+--------+     +----...
   |        |        |
[[blinkit-..-0900]] [[blinkit-..-1600]] ...        (run notes)
   |  \              |  \
   |   `--> [[blinkit-..-0900]] (prev run, back-edge)
   v
[[2026-05-21]] (daily) --> [[2026-W21]] (weekly) --> [[2026-05]] (monthly)
   ^                          ^                         ^
   |__ all of today's runs    |__ all of week's dailies |__ all of month's weeks
```

Result: platform hubs and dailies become the **large hub nodes**; runs cluster under
their platform and thread along the date spine — exactly what a price-history graph
should look like.

---

## 4. Machine-readable history (for the future ML model)

`data/<platform>/history.csv`, one row per `(run, sku, location)` observation:

```
run_id,date_ist,platform,canonical_sku,city,pincode,price,mrp,discount_pct,in_stock
```

- `price` = the row's `sale`. National-shape platforms emit `city="All India",
  pincode="-"`; per-pincode platforms emit the real city/pincode per observation.
- Append-only across runs, but **idempotent within a run**: re-running a RUN_ID
  rewrites only that run's rows (de-dup key = `run_id,platform,canonical_sku,pincode`).
- Header written once; stable column order; deterministic row sort so diffs are clean
  and git-friendly. This is the training table — the Markdown notes are the human view
  of the same data.

---

## 5. The two generators

- **`tools/vault_note.py <platform> <RUN_ID>`** — per-run. Reads
  `platforms/<platform>/result.json` (handles both `perPin` and `allRows` /
  national vs per-pincode shapes) and, if present,
  `reviews/<platform>-<RUN_ID>.json` (the verdict). Writes the run note, upserts the
  platform hub, upserts the daily note, and appends to `history.csv`. Idempotent.
- **`tools/vault_rollup.py <daily|weekly|monthly> [date]`** — (re)builds a
  time-rollup note from existing run notes / `history.csv`. Default date = today (IST).

Both: Python 3 stdlib only, deterministic, no LLM, safe to run inside the cron loop.

---

## Sources
- [Obsidian Help — Graph view](https://obsidian.md/help/Plugins/Graph+view)
- [Obsidian Help — Internal links & backlinks (DeepWiki mirror)](https://deepwiki.com/obsidianmd/obsidian-help/4.2-internal-links-and-graph-view)
- [Obsidian skills — Internal links & wikilinks](https://deepwiki.com/kepano/obsidian-skills/2.2-internal-links-and-wikilinks)
- [Obsidian skills — Frontmatter properties](https://instagit.com/kepano/obsidian-skills/what-are-obsidian-frontmatter-properties/)
- [Obsidian skills — Aliases](https://instagit.com/kepano/obsidian-skills/what-is-the-purpose-of-aliases-in-obsidian-frontmatter/)
- [Obsidian forum — Wikilinks in YAML frontmatter](https://forum.obsidian.md/t/wikilinks-in-yaml-front-matter/10052)
- [Obsidian Rocks — Maps of Content](https://obsidian.rocks/maps-of-content-effortless-organization-for-notes/)
- [dsebastien.net — Maps of Content (complete guide)](https://www.dsebastien.net/2022-05-15-maps-of-content/)
