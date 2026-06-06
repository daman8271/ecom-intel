# verify-v2 — W3 adversarial verification report (2026-06-06)

Gate for the owner's team shipment of `Jivo-SKU-Master-Map-2026-06-06.xlsx`.
Verifier: W3 (read-only outside this file). Method: independent ground truth captured
BEFORE W1/W2 finished (pre-W1 sku_map snapshot md5 `b8c6ae117f77766db0d97d2c6a933e7e`,
team-sheet parse, daddea68 fold diff, raw `result.json` evidence pools), then exhaustive
programmatic audit of W1's map (`extend_map.py @ dc45a45d`) and W2's workbook.

## VERDICT: **PASS — ship it.**

W1 (113-SKU map extension, commit dc45a45d): PASS on all 4 items.
W2 (Jivo-SKU-Master-Map-2026-06-06.xlsx, commit 1bf3ea97): PASS on all 4 items.
One justified deviation, zero blockers — details below.

---

## Part A — W1 (master v2 ingest + 113-SKU map extension): **PASS**

### A1. Master v2 ingest — PASS
| Check | Result | Evidence |
|---|---|---|
| master_v2.json = 113 entries | PASS | 113/113 |
| ALL price fields == sheet | PASS | mrp/asp/svd/bau/art compared cell-for-cell for **all 113** (task floor was a 15-row sample) — 0 mismatches |
| sku_map regimes == sheet | PASS | all 113 active entries, 0 mismatches; spot-anchor: CANOLA 1+1L regimes moved {bau509,svd489,art469}→{svd509,bau529,art489} exactly as sheet |
| Rename BLACK PAPER→BLACK PEPPER 100G | PASS | ASIN B0D8L8NR8Q identical old↔new; old key gone, no duplicate row; platform sub-tree **byte-identical** to old entry |
| Rename ROSEMARY LEAVES 150G→150 GMS | PASS | ASIN B0DGTNDH9L; the sheet cell carries a **trailing space** (`'B0DGTNDH9L '`) — W1 strips it correctly (verified all 113 ASINs stripped & == sheet) |
| RICE 1KG retired-not-deleted | PASS | `retired: true`, platform mapping byte-identical to pre-W1; map = 114 keys (113 sheet + retired) |

### A2. New-SKU mappings (30 platform mappings over 20 new/renamed) — PASS
Composition proof pulled independently from `platforms/*/result.json` + frozen fragments
for **every** mapped combo:

- **amazon (18× ID-ASIN)**: identity-grade join on the sheet's own ASIN. 14/18 ASINs present
  in the 314-ASIN scrape with same-oil titles ("Pack of 2", "1 Litre each", "1+1 Litre Pack");
  4 (RICE BRAN/SESAME/SO OLIVE/YELLOW MUSTARD combos) not in the scrape set — mapped on sheet
  identity only, correctly carrying no fabricated price data.
- **flipkart (4× ID-CATALOG)**: EXTRA LIGHT 1+1L (QWRGGC46UKQKVCES), EXTRA VIRGIN 1L + 1L
  (QWRGEMNS9ZPZGWJH, mrp 2998==sheet), GOLD 1+1 (EDOGYJ7SYY4H2MDH, mrp 450==sheet),
  SO OLIVE 1L + 1L (EDOHBH2URWDMHPXC, mrp 650==sheet), SOYABEAN 1L + 1L (EDOGGPFZ2FCJ6UWS).
  Join = exact match on Jivo's own internal catalog name with `combo=True` — identity-grade.
  My title heuristic initially flagged GOLD/SO OLIVE/SOYABEAN ("title doesn't shout 2-pack" /
  "names rice bran"): **resolved as false positives** — GOLD and SO OLIVE are themselves blend
  *products* (Gold = rice-bran+sunflower; So Olive = rice-bran+olive), the titles name their own
  constituents, no foreign oil appears, and the catalog name carries the 1+1L composition.
- **zepto (1× anchored)**: JIVO POMACE 1L + 1L → pvid 3d955a07…: composition proven **three
  ways** — raw zepto row `pack: "1 L X 2"`, `vol_ml: 2000`, and MRP arithmetic 2098 = 2×1049
  (POMACE 1L sheet MRP), plus sheet-MRP anchor 2098==2098.
- **bigbasket (1× ID-EAN)**: WG MANGO JUICE 500ML → sku_id 40335340, ean 8905604001861 —
  both verified present in `platforms/bigbasket/result.json` raw row, mrp 100==sheet.
- **amazon-now (1× ID-ASIN)**: WG MANGO B0DM2G4YCC — 6 raw rows in amazon-now result.json,
  sale 100, in_stock 1, genuine ctnow surface.
- **flipkart-minutes (1× anchored)**: JIVO WATER 1L → census mrp 30==sheet, and the
  **orphaned 10th fold pid** WERH9M3VYW6X5KSX (proposed in daddea68 but unlandable then —
  WATER 1L wasn't a master SKU) is now correctly attached.

**MRP anchor**: every `confidence: anchored` match has listing mrp == sheet MRP (zepto 2098,
fkm 30). ID-joins with diverging live MRPs were NOT silently accepted: 4 new `mrp_drift`
entries (EXTRA LIGHT 1+1L 2998v2798, EXTRA VIRGIN 1L+1L 1998v2998, POMACE 1L+1L 1298v2098,
SOYABEAN 1L+1L 450v1100).

**Adversarial trap sweep** — I pre-extracted 13 trap candidates from the evidence pools before
W1 finished; ALL landed in review, none silently mapped:
mustard 3-way internal-name collision (510≠500), yellow-mustard exact-name 790≠750,
RICE BRAN catalog "2L" single-bottle @570==sheet-MRP (composition block held — single 2L ≠ 2×1L),
zepto EL combo 2998≠2798, SO OLIVE twin FSN @699, pomace twin FSN @1899, canola same-platform
collision (below), water/ginger-ale/shikanji case-pack MRPs, SUNFLOWER th=1 variant suspicion.
Mixed-oil decoys with coincidentally matching MRPs (Sunflower&Soyabean @500 == MUSTARD-combo
sheet MRP; Sunflower&Canola @650 == SO OLIVE sheet MRP) were NOT taken.

**Dual-canola trap**: sheet legitimately holds BOTH `CANOLA 1+1L` (old, B0152TWWSQ, 6 platforms)
and new `CANOLA 1L + 1L` (B0CZP26VVN, same prices). W1 did NOT duplicate or steal the old SKU's
flipkart/zepto/fkm listings — new SKU got amazon only + a review item for the flipkart collision.
Zero cross-SKU (platform,id) collisions across all 114 entries (programmatic sweep incl. alt lists).

### A3. Folded ids survived — PASS
All **15** daddea68 enrichments (9 fkm pids + 3 blinkit prids + 3 bigbasket EANs, exact
field-level diff captured pre-W1) present and unchanged in final sku_map.json.
(Note: daddea68's commit message says "10 fkm pids"; only 9 ever landed — the 10th,
`jivo-mineral-water-1l`, had no map entry then and is now W1's JIVO WATER 1L mapping. Resolved.)

### A4. Updated 96 — PASS
Platform sub-trees of all 96 pre-existing SKUs **byte-identical** to the pre-W1 snapshot
(renames keyed across, RICE 1KG included); only regimes/new top-level fields differ.
Bonus: `extend_map.py` re-run in an isolated sandbox → byte-identical sku_map.json +
master_v2.json (idempotence claim confirmed).

Minor, non-blocking: the zepto pomace entry's note says "sale not captured in the frozen
census", but `platforms/zepto/result.json` has sale 758 / in_stock 1 for that pvid —
available enrichment, not an error.

---

## Part B — W2 (Excel rebuild, final 113-SKU build @ 1bf3ea97): **PASS**

(The same harness was first calibrated on W2's 96-SKU proof build @ e6098b82 — all
invariants held there too: 259/259 linked, all 259 titles == raw.)

### B1. Hyperlink invariant — PASS
| Check | Result | Evidence |
|---|---|---|
| Every non-empty Master Map price cell hyperlinked | PASS | **286/286** (openpyxl re-count, independent of W2's own assertion) |
| Listing Details url column | PASS | 286/286 rows non-empty |
| ⚠ no-link markers | PASS | **zero** |
| Cell arithmetic cross-check | PASS | 259 (proof) + 27 new cells (18 amazon + 5 flipkart + 1 each zepto/bigbasket/amazon-now/fkm) = 286 exactly |

**Justified deviation (not a no-link marker):** 10 cells carry
"⚠ title not captured (listing not yet scraped)" — 4 in Listing Details (E201/E230/E237/E286)
+ 6 mirrored in Review. These are exactly the 4 sheet-asserted, never-scraped combo ASINs
(RICE BRAN/SESAME/SO OLIVE/YELLOW MUSTARD 1L+1L). Pre-justified on the bus ([W2] 16:19:08),
their Master Map cells render "listed" (hyperlinked to the correct `/dp/<ASIN>?th=1`,
verified per-cell; in_stock shown "?", not false-OOS), and **no internal name is ever
presented as a platform title** — the honest treatment under the owner's exact-title order.

### B2. EXACT titles — PASS
- **Exhaustive, not sampled**: all 286 Listing-Details rows checked against the platform's own
  raw `result.json` text (task floor was 20). 282/282 rows with raw evidence match **exactly**;
  the remaining 4 are the justified ⚠ rows above. 0 mismatches.
- flipkart: `fk_name` independently confirmed as the on-page listing field (sku_raw/item/
  product_name are all internal variants — e.g. fsn EDOGDVWEUPPWVGED: internal "MUSTARD 5L" vs
  on-page "JIVO Cold Pressed Pure Cooking Mustard Oil Can"). Zero internal-name-shaped titles
  in any flipkart row (regex sweep over all flipkart rows).
- No truncation: longest title = 204 chars (amazon B0B2RW9N9F) — byte-identical to raw;
  zero ellipsis-terminated titles anywhere.
- Caveat for the record: flipkart renders pack size as a separate page element, so `fk_name`
  (without the "(5 L)" suffix) is the strongest offline-verifiable on-page name.

### B3. New SKUs present — PASS
18/18 new SKUs appear as Master Map rows; per-row platform cells == the sku_map platform
sets for all 18 (programmatic diff); the 12 combos show their amazon (+flipkart/zepto where
mapped) cells; WG MANGO JUICE 500ML shows its bigbasket cell (the only beverage with a bb
mapping — correct: bigbasket has no ginger-ale/water/shikanji listing in evidence).
RICE 1KG present as "RICE 1KG (retired)", grey font (888888), mappings kept and hyperlinked.

### B4. Sanity — PASS
File opens clean; exactly 5 sheets (Master Map / Listing Details / Review / MRP integrity /
Unpriced); freeze panes on every sheet (B5 + 4×A2); fills meaningful — green exact (D9EAD3,
244 cells), yellow anchored (FFF2CC, 42), Jivo green header (008B3A).

---

## Scorecard

| # | Item | Verdict |
|---|---|---|
| W1.1 | Master v2 ingest (113, renames, RICE 1KG, regimes) | PASS |
| W1.2 | New-SKU mappings (composition, MRP anchor, EAN evidence) | PASS |
| W1.3 | Folded-15 survived | PASS |
| W1.4 | Updated 96 mappings unchanged | PASS |
| W2.1 | Hyperlink invariant | PASS |
| W2.2 | Exact full titles | PASS |
| W2.3 | New SKUs present | PASS |
| W2.4 | Workbook sanity | PASS |

**W3 sign-off: PASS. The LEAD may send `Jivo-SKU-Master-Map-2026-06-06.xlsx` to the team.**

---

## Addendum — PUNKIRAT-CHECKS (e-com dept feedback via owner, added post-sign-off)

Four checks over the title cells of ALL 5 sheets (Punkirat Singh's screenshot complaints:
internal names / URL-slugs / `(blessed)`-style annotations posing as titles in the OLD xlsx).

Counts per sheet (title cells scanned → violations):

| Sheet | title cells | (1) internal-shape | (2) slug | (3) annotation | (4) real-title where evidence exists |
|---|---|---|---|---|---|
| Master Map | 0 (no title col) | 0 | 0 | 0 | n/a |
| Listing Details | 286 | 0 | 0 | 0 | 282/282 exact (4 justified ⚠) |
| Review (confirm these) | 45 | 0 | 0 | **1 — D14** | 30/30 exact |
| MRP integrity | 0 (no title col) | 0 | 0 | 0 | n/a |
| Unpriced (no master row) | 368 | 0* | 0 | 0 | 334/334 exact |

\* 16 col-A internal-shaped strings are **family-header rows** (no listing id — census
"add to master" suggestions, the family name IS the content, by design). The 5 flipkart
listings with NO on-page title anywhere (`fk_name` empty in result.json — disclosed on bus
16:10:42) render `<internal name> ⚠ internal name (listing not scraped)` — explicitly
marked, never posing as a title, and check 4 is satisfied (result.json has nothing).

**The one violation — Review!D14** (`EXTRA LIGHT 3L` / flipkart, pid unresolvable offline):
the "exact listing title" cell reads
`jivo-extra-light-3-litre-cooking-oil-olive-plastic-bottle (owner sheet URL)` —
a URL-slug posing as a title PLUS a parenthetical annotation, i.e. Punkirat's classes (b)+(c)
in one cell. Inconsistent with W2's own (correct) idiom for the 4 never-scraped amazon ASINs
("⚠ title not captured"). Fix = render that cell as
`⚠ title not captured (owner-sheet URL carries no pid)` and keep the slug/URL in the
url/reason columns. One-cell builder fix + rebuild requested from W2 on the bus;
re-verified result will be appended below.

### Re-verify after W2's title-hygiene rebuild (commit f41a35a4) — **PASS**

Full harness re-run on the rebuilt file: **FAIL=0** (286/286 hyperlinked, titles exact,
18/18 new SKUs, sanity all green — no regression). PUNKIRAT counts per sheet, final:

| Sheet | title cells | internal | slug | annotation | real-title where evidence exists |
|---|---|---|---|---|---|
| Master Map | 0 (no title col) | 0 | 0 | 0 | n/a |
| Listing Details | 282 | 0 | 0 | 0 | 229/229 (bigbasket = brand-prefixed live API desc, verified) |
| Review (confirm these) | 32 | 0 | 0 | 0 | 30/30 |
| MRP integrity | 0 (no title col) | 0 | 0 | 0 | n/a |
| Unpriced (no master row) | 368 | 0 | 0 | 0 | 334/334 |

- **Review!D14 fixed**: slug + `(owner sheet URL)` gone. The title cell now carries the
  e-com master sheet's own title for EXTRA LIGHT 3L, with provenance disclosed in the
  reason column ("title from e-com master sheet (listing not resolvable offline)") — the
  chartered master-sheet fallback, annotations where the owner ordered them. I traced the
  string: it is the master/amazon family title (B097ZZTW5C), NOT a fabrication.
  *Residual judgment note for the LEAD*: it is a cross-platform title on a flipkart row —
  the on-page flipkart name may differ when the owner clicks through; the reason column
  says so, and no offline source can do better (URL carries no pid).
- The 4 never-scraped amazon combos: title cells now **empty** with a disclosing note
  ("identity from team master sheet v2; ASIN not in the 314-ASIN targeted scrape") —
  honest, nothing posing as a title; Master Map cells unchanged ("listed", linked).
- The 5 fk_name-less Unpriced rows now read "(title not captured)" — status, not a fake title.
- MRP integrity r2 (COCONUT 500ML) + r6 (SANO POMACE 5L): "blessed" jargon reworded to
  "owner-verified" — team-facing language, living in the evidence column where it belongs.

**PUNKIRAT-CHECKS final verdict: PASS — 0 violations across all 5 sheets. Overall PASS stands.**

Non-blocking follow-ups (no action required before shipping):
1. zepto pomace-combo sale 758 / in_stock 1 exists in `platforms/zepto/result.json` but not in
   the map entry (W1 used the frozen census) — available enrichment.
2. The 4 never-scraped combo ASINs should enter the amazon scrape list so their titles/prices
   land on the next sweep (clears the 4 justified ⚠ rows).
3. EXTRA LIGHT 1+1L sheet MRP 2798 is contradicted by two independent live sources @2998
   (amazon ID-anchored + zepto census) — strongest stale-sheet candidate; flag to the e-com team.
