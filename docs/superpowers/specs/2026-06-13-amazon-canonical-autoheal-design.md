# Amazon canonical-collision auto-heal — design spec

**Date:** 2026-06-13
**Status:** Approved (design) — pending spec review
**Owner:** Daman
**Scope motto:** "Issue comes → Claude sees → Claude analyzes → keeps things in order → fixes it." Amazon only. Nothing else.

---

## 1. Problem (one paragraph)

Amazon's product titles sometimes render short/partial for a handful of pincode cards. Our
canonicaliser builds the product's ID (`canonical_sku`) from whatever title text it gets, so the
same physical product occasionally lands under **two IDs**: a full one
(`…canola-…-cooking-oil-for-daily-use-…-1l`) and a truncated stub (`…canola-…-cooking-o-1l`, or a
`…-na` volume stub). The two IDs carry the **identical** (sale, mrp) because they are the same
listing. The deterministic `shared_price_dup` check reads "two distinct products, same exact price"
as *possible fabrication* → verdict **SUSPECT** → the whole Amazon report is **held** from the
batch. It recurs essentially every run (seen 06-08, 06-09, 06-13 on amazon-now). The in-loop LLM
judge already votes "OK — real Jivo oils", but its vote is overruled because the gate holds on *any*
failing check. The duplicate IDs also silently **inflate the unique-SKU count** (e.g. 27 vs ~23).

## 2. What we are building (Approach A — reactive agent)

A single reactive step: when an **Amazon** report is about to be held **solely** because of the
`shared_price_dup` canonical-collision class, **Claude wakes**, looks at the flagged colliding rows,
and decides — per colliding pair — one of three things, then acts:

| Claude's call | Meaning | Action (identity-only) |
|---|---|---|
| **SAME** | Two IDs are one product (stub ↔ full). | Merge the stub `canonical_sku` into the full one in this run's data. |
| **DISTINCT** | Genuinely different products that happen to share a price. | Leave data as-is. The shared price is real. |
| **SUSPECT** | Looks like actual contamination/fabrication. | Change nothing. Report stays held. |

After acting, re-run the review on the (possibly repaired) data. If the collision is resolved →
verdict flips to OK and the report flows out the normal path. Otherwise it stays held, exactly like
today. Either way, Claude's decision is **final and unattended**, and the user gets one Telegram
note describing what happened.

This also fixes the inflated SKU count as a side effect, because the merge removes the phantom stub
SKUs from the data — not just the verdict.

## 3. Autonomy & the hard line (non-negotiable guardrails)

- **Full autonomy on the decision.** No human approval gate. Telegram is a *notification*, not an ask.
- **Identity-only. Never prices.** The agent may only merge/rename `canonical_sku` values (and drop
  rows that become exact duplicates of an existing row after a merge). It may **never** invent or
  alter `price`, `mrp`, or `discount_pct`. A wrong number reaching the owner is the one
  unrecoverable failure; this boundary makes it structurally impossible.
- **Hard-fails always override.** If the run also tripped any hard-fail check (captcha/block markers,
  zero/near-zero rows, price-out-of-band, BROKEN verdict, geo span), the agent does **not** run and
  the report stays held. The agent only activates when the failing-check set ⊆ the
  `shared_price_dup` canonical-collision class.
- **Reversible.** Before any change, snapshot the affected rows to a `.heal-snapshot`. Every action
  is appended to `logs/autoheal.log` (what collided, Claude's per-pair verdict, what was merged).
- **Bounded.** Activate only within the SUSPECT band, never the BROKEN band: if collisions exceed
  the BROKEN thresholds already in `review.py` (≥ 5 canonicals on a single pair, or ≥ 25% of priced
  rows in shared pairs) the agent does **not** heal — it escalates (keep held + Telegram). Within
  band, one bounded `claude -p` call per held report; no fan-out (respects Max rate-limits); no
  retry loop.
- **Fail safe.** If Claude is unreachable / rate-limited / returns an unparseable verdict → default
  to **keep held** (current behaviour). The agent can only ever *release* after a successful
  adjudication; it can never release by timing out.

## 4. Trigger & integration (altitude — exact wiring goes in the plan)

- **Where:** the existing guardian heal path. `run_all.sh` already calls `guardian.py`
  verdict-gated with a bounded `--heal` retry; today a SUSPECT/`shared_price_dup` outcome is merely
  recorded and the report held (`selfheal.sh` only auto-reruns on BROKEN). The agent slots in as the
  heal action for the `shared_price_dup`-only SUSPECT case on Amazon platforms.
- **Trigger condition (all must hold):**
  1. platform ∈ Amazon family (`amazon-now`, and `amazon`/`amazon-fresh` if it ever appears there);
  2. combined verdict = SUSPECT (not BROKEN);
  3. the *only* failing reason(s) belong to the `shared_price_dup` canonical-collision class;
  4. no hard-fail check tripped.
- **Re-review:** after repair, force a fresh `review.py` so the verdict + rolling baseline reflect
  the cleaned data, then let the normal verdict-gated send proceed.

## 5. Claude's input / output contract

- **Input:** for each colliding `(sale, mrp)` pair — the competing `canonical_sku` values, their row
  counts, the raw titles/sku_raw behind them, and per-pincode price agreement. (Identity evidence
  only; no instruction to evaluate price correctness.)
- **Output (structured):** per pair → `SAME` | `DISTINCT` | `SUSPECT`, with a one-line reason. When
  `SAME`, which `canonical_sku` is the canonical survivor (the fuller/longer ID) and which folds in.
- **Model:** Fable 5 (default, Max-included). One-line config switch to Opus for heavier judgment.

## 6. Out of scope (explicitly NOT building)

- Non-Amazon platforms (zepto coverage drops, flipkart, etc.) — stay on today's alert-only path.
- Any failure type other than the `shared_price_dup` canonical-collision class.
- Price / MRP correction of any kind.
- A deterministic pre-filter (Approach C) — rejected; Claude does the recognising directly.
- Fixing the upstream canonicaliser so stubs never form. (Worth doing later; not this change. This
  change heals the symptom reactively, as requested.)

## 7. Success criteria

- A run that today would be held on `shared_price_dup` alone (e.g. amazon-now `…mustard-d-na`
  colliding with `…mustard-daily-…-1l`) is auto-resolved: stubs merged, verdict OK, report
  delivered in-batch, with a Telegram note.
- Unique-SKU count for that run reflects the merged identities (no phantom stubs).
- A genuinely distinct shared-price collision is released **without** a wrong merge.
- A fabricated/contaminated case is **kept held**.
- Claude-unreachable → report stays held; nothing auto-released blindly.
- Prices in the delivered report are byte-identical to the scraped values (never touched).
