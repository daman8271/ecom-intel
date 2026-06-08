# W2 — Cluster column verify: `Price-Match active (±₹5)`

**Verdict: PASS (all 4 checks).** Adversarial, independent recompute vs W1's committed
`build_pricematch.py sheet_matrix` (commit `df9b95fb`). Zero mismatches.

## Headline (for the owner)
> **24 SKUs are price-matching within ₹5 today** — i.e. 2+ platforms list them within a
> ₹5 band of each other. Those 24 SKUs span **76 platform listings** locked into a
> ₹5 cluster. (Amazon edition, scoped to amazon + fresh + now: **19 SKUs**.)

Regime: BAU · date 2026-06-08 · band `PM_CLUSTER_BAND = 5.0`.

---

## Check 1 — Cluster correctness (independent recompute): **PASS**
- Independent engine recompute: `tools/pricematch/tests/cluster_recompute.py` reads ONLY
  `pricematch_core.py --json`, with NO knowledge of W1's code. It collects per-SKU live
  `live_modal` prices for priced statuses `{BELOW, ABOVE, MATCH, NO_REF}` (OOS / NOT_LISTED /
  PENDING_REVIEW / retired never counted), sorts, and greedily groups so each group's
  `max − min ≤ 5`, keeping groups of ≥2.
- **Membership: 0 mismatches** across all SKUs (W1 = 24, recompute = 24).
- **Band prices: 0 mismatches** — every ₹ low/high shown in W1's cell matches the recomputed
  cluster min/max.
- **Algorithm-robustness:** checked single-linkage (consecutive-gap) vs complete-linkage
  (group-spread). They produce identical clusters on *every* SKU today, so the result does
  not depend on the grouping nuance. W1 uses complete-linkage (`price − group[0] > BAND`),
  matching my recompute exactly.

### Boundary (hard ±₹5 check): **PASS**
Exactly-₹5 pairs → IN; ₹6 pairs → OUT, confirmed on the real data:
| SKU | Pair | Gap | Expected | In workbook |
|---|---|---|---|---|
| CANOLA 5L | Amazon ₹1,249 · Flipkart ₹1,254 | **5.00** | IN | clustered ✓ |
| COCONUT 1L | Flipkart ₹534 · Amazon ₹539 | **5.00** | IN | clustered ✓ |
| GROUNDNUT 5L | Amazon Now ₹1,074 · Amazon ₹1,079 | **5.00** | IN | clustered ✓ |
| SO OLIVE 5L | Flipkart ₹1,364 · Amazon ₹1,369 | **5.00** | IN | clustered ✓ |
| EXTRA LIGHT 2L | Flipkart ₹1,004 · Amazon ₹1,010 | **6.00** | OUT | excluded ✓ |
| GROUNDNUT 1L | Amazon Now ₹193 · Zepto ₹199 | **6.00** | OUT | Zepto excluded ✓ |
| MUSTARD 1L | Bigbasket ₹202 · Amazon Fresh ₹209 | 6.91 | OUT | excluded ✓ |

## Check 2 — Display: **PASS**
- **Canonical display names** (`xlsx_dash.PLATFORM_DISPLAY`): "Amazon Fresh", "Amazon Now",
  "Flipkart Minutes", etc. — verified in every cell.
- **Price band shown:** `@ ₹lo–hi` (single `@ ₹x` when flat).
- **Multiple clusters separated** by `  |  ` — 3 SKUs today: CANOLA 5L, MUSTARD 1L,
  SUNFLOWER 1L (e.g. `⚡ Blinkit · Zepto @ ₹190–192  |  Amazon · Amazon Fresh @ ₹207`).
- **No-cluster rows blank:** `—` (muted, centered); retired rows blank (`None`) + grey.
- **Highlight fill is NOT red/green:** cluster fill = `BRAND_SOFT` D6F0E0 — distinct from the
  compliance RED `FFC7CE` and GREEN `C6EFCE`. It sits in the brand-green family, but is
  unambiguous in context: a dedicated last column titled "Price-Match active (±₹5)", `⚡`
  prefix, bold brand text, and platform-name content (never a ₹ price) — red/green fills only
  ever land on price cells in the platform columns. *(Observation, not a defect: the tint is
  close to the green compliance fill; the legend + column header + ⚡ + content carry the
  disambiguation.)*
- **Legend explains the column** (frozen top row, row 2): `⚡ Price-Match active = 2+ platforms
  within ₹5 of each other (last col)`. Each cell also carries a hover comment with the cluster
  count.

## Check 3 — No regression: **PASS**
Cell-level diff (value, fill, font color, hyperlink, number-format, comment, freeze panes) of
the pre-change build (HEAD `0789b3fd`) vs the after build:
- **Ecom Head / Violations / Above reference / Coverage & pending: 0 diffs** (byte-identical).
- **Matrix:** the only diffs are (a) the new column (col 12, expected) and (b) one new legend
  cell at R2C9 — the ⚡ legend entry that explains the column. Existing platform cells, colors,
  links, the RED/GREEN compliance fills, freeze (`B3`), gridlines, and retired rows are all
  unchanged.
- **Amazon edition** builds clean and the cluster column (col 7) spans **only**
  amazon + amazon-fresh + amazon-now — 0 foreign-platform leaks, 0 membership mismatches vs the
  scoped recompute (19 SKUs).

## Check 4 — Rebuild for delivery: **PASS**
Rebuilt both deliverables (deterministic, byte-stable) into `tools/pricematch/`:
- `Jivo-Price-Match-2026-06-08.xlsx` — zip-ok, 5 sheets, cluster col present + populated (24 SKUs).
- `Jivo-Price-Match-Amazon-2026-06-08.xlsx` — zip-ok, 5 sheets, scoped cluster col (19 SKUs).
Both reproduce byte-identically on rebuild (md5 stable).

---

## 10-SKU sample of the new column (master)
| SKU | Price-Match active (±₹5) |
|---|---|
| CANOLA 1+1L | ⚡ Flipkart · Flipkart Minutes @ ₹572–575 |
| CANOLA 1L | ⚡ Amazon · Amazon Fresh · Amazon Now · Flipkart Minutes · Blinkit @ ₹255–260 |
| CANOLA 5L | ⚡ Zepto · Amazon Fresh · Amazon Now · Blinkit @ ₹1,193  \|  Amazon · Flipkart @ ₹1,249–1,254 |
| COCONUT 1L | ⚡ Flipkart · Amazon · Amazon Now @ ₹534–539 |
| COCONUT 500ML | ⚡ Amazon · Amazon Fresh @ ₹279 |
| EXTRA LIGHT 1L | ⚡ Zepto · Amazon · Amazon Fresh · Amazon Now @ ₹499 |
| EXTRA LIGHT 2L | ⚡ Zepto · Amazon Fresh · Amazon Now · Blinkit @ ₹1,135–1,139 |
| EXTRA VIRGIN 1L | ⚡ Amazon · Amazon Fresh · Amazon Now @ ₹789 |
| GOLD 5L | ⚡ Amazon Fresh · Amazon Now @ ₹909 |
| GROUNDNUT 1L | ⚡ Amazon · Amazon Now @ ₹193 |

## Reproduce
```
python3 tools/pricematch/tests/cluster_recompute.py --date 2026-06-08          # independent truth
python3 tools/pricematch/build_pricematch.py --date 2026-06-08                  # master
python3 tools/pricematch/build_pricematch.py --date 2026-06-08 \
        --platforms amazon,amazon-fresh,amazon-now --label Amazon               # Amazon edition
```
