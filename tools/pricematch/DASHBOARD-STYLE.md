# DASHBOARD-STYLE — the ecom-intel workbook look (1 page)

Owner order 2026-06-06: "make the dashboards more beautiful." This is the house style every
team-facing workbook follows — platform Leadership Views, pricematch dailies, the Ecom Head
master. **Render everything through `tools/xlsx_dash.py`** (pure openpyxl, round-trip
durable; `python3 tools/xlsx_dash.py --selftest` proves the contract).

## Palette (ink + sage — one accent hue + neutrals)
| Role | Hex | Use |
|---|---|---|
| `JIVO_GREEN` = `BRAND` | `008B3A` | **the ONE brand green** (fresh-eyes 2026-06-06): header bars, section titles, data bars, tab color |
| `BRAND_SOFT` | `D6F0E0` | soft emphasis fills, chips |
| `INK` / `MUTED` | `111827` / `6B7280` | primary text / labels, subs, footnotes |
| `RULE` / `CANVAS` | `E5E7EB` / `F9FAFB` | hairlines + card borders / zebra stripe |
| `POS` / `WARN` / `NEG` | `047857` / `B45309` / `B91C1C` | semantic text colors — **reserved**: green=good, red=bad, never decorative |
| `BAD_PAIR` / `GOOD_PAIR` / `AMBER_PAIR` | `FFC7CE`/`9C0006` · `C6EFCE`/`006100` · `FFEB9C`/`9C6500` | **the ONLY compliance (fill, text) pairs** — no `F4CCCC`/`CC0000` drift. Amber = "overpriced — sales risk", never green |

## Type scale (Calibri everywhere — ships with every Excel)
20pt bold INK title → 12pt bold white-on-BRAND section bars → **22pt bold toned KPI values**
→ 11pt INK body → 9pt bold MUTED caps labels → 9pt italic MUTED footnotes.

## Layout grid
- 10 uniform columns × width 16 (`col_grid`); KPI cards span 2 cols × 4 rows and tile across.
- `no_gridlines(ws)` on every dashboard sheet — the single biggest visual upgrade.
- Whitespace separates sections, not boxes: blank gap rows + a 3pt `hairline` under the title.
- `title_block` → KPI card strip → `section_title` + `banded_table` blocks → `footnote`
  (generated-at + data source). `freeze(ws)` headers; `fit_to_width(ws)` — executives print.
- Numbers **right-aligned** with explicit formats: `FMT_INR` (₹ lakh/crore grouping —
  `12345678 → ₹1,23,45,678`), `FMT_PCT`. Caveat: negatives render unsigned in `FMT_INR`
  (2-condition format) — use it for prices/counts, not deltas.

## Language & naming (fresh-eyes 2026-06-06)
- **No unexplained jargon**: expand each `GLOSSARY` term ONCE per sheet at first use via
  `gloss("SVD")` → "SVD — Special Value Days (Fri–Sun agreed price list)"; use the plain term
  (`regime`→"price plan", `modal`→"most-common price", `exposure`→"₹ gap below agreed price",
  `dark store`→"delivery store") everywhere else.
- **One platform name set**: `platform_name(key)` ("Amazon Now", "Flipkart Minutes");
  `short=True` only for genuinely narrow columns.
- **No engineering residue** in stakeholder cells: no script paths, file names
  (`regime.json`), URL params (`almBrandId`), or scrape durations. ONE capture timestamp
  per workbook.
- **Legends at the frozen TOP** (`legend()`, self-demonstrating, all states covered —
  red/green/blue/OOS/?) — never below the data. Scoped editions carry `edition_badge()`
  on the cover.

## Do
- KPI cards: merged cells + hairline border + big toned value (`kpi_card`); tone carries the
  verdict (good/warn/bad) so the number reads before the label.
- Proportions/trends in shared sheets: **conditional formats** — `data_bar` (BRAND),
  `color_scale` (red→white→green), `icon_set` — plus unicode `spark`/`meter` text visuals.
  All survive openpyxl load+save (verified on 3.1.5, twice over).
- Manual zebra striping (`banded_table`, CANVAS/white) — durable and never fights CF rules.
- `note()` cell comments for drill-down provenance (pincode counts, sweep id).
- CF colors as 8-digit ARGB (`FF…`) — the helpers do this for you.

## Don't
- **NO native charts except in the LAST stage that touches a workbook** — and know that
  even then they render BLANK in preview viewers (Quick Look, Drive, Office mobile):
  openpyxl charts carry no cached values, the 2026-06-06 empty-Leadership-View root cause.
  Durable dashboards are cells + CF (report_dashboard.py). openpyxl load+save also destroys
  Excel-AUTHORED charts/images/shapes; our own openpyxl-drawn charts survive a re-save,
  but the rule stays absolute so ordering never matters.
- If drawing charts in that last stage: call `xlsx_dash.excel_app_workaround()` first —
  openpyxl ≥3.1.4 stamps `Application: …Openpyxl…` and Excel then mis-renders its charts.
- No native Excel Tables on executive sheets (header filter dropdowns can't be suppressed).
- No x14 CF extensions (solid/bordered/negative data bars, custom icon mixes) — openpyxl
  can't write them; base-spec rules only.
- No saturated default-Excel colors, no red/green for decoration, no more than the one
  brand hue + neutrals per sheet.

## Sources (patterns only; no-license repos = ideas, zero code copied)
openpyxl docs — [formatting/CF](https://openpyxl.readthedocs.io/en/3.1/formatting.html) ·
[styles & merged-cell borders](https://openpyxl.readthedocs.io/en/3.1/styles.html) ·
[tables](https://openpyxl.readthedocs.io/en/3.1/worksheet_tables.html) ·
[comments](https://openpyxl.readthedocs.io/en/stable/comments.html) ·
[chart/image loss warning](https://openpyxl.readthedocs.io/en/3.0/usage.html) ·
[Application-stamp chart bug](https://groups.google.com/g/openpyxl-users/c/khC6BTqaH3Y) ·
[xlsxwriter CF catalogue](https://xlsxwriter.readthedocs.io/working_with_conditional_formats.html)
(what x14 adds that we must avoid) ·
[Xelplus dashboard design tips](https://www.xelplus.com/5-design-tips-for-excel-dashboards-reports/)
(contrast hierarchy, semantic red/green, whitespace) ·
[lakh/crore format string](https://learn.microsoft.com/en-us/answers/questions/5301771/how-to-format-numbers-in-to-crores-lakhs-thousands)
(+ [gist](https://gist.github.com/yaneshtyagi/de1b2e65a7d247137a748fdb4455ac6f)) ·
[openpyxl dashboard walkthrough](https://medium.com/@umaraj_datascientist/automating-excel-dashboard-creation-9c60acb1ba0c)
(banner + grid-anchored layout) ·
[INWTlab/python-excel-report](https://github.com/INWTlab/python-excel-report)
(config-first architecture; **no license** — pattern only).
