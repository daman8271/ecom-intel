# W4 — Rebuild + caught-case verification (2026-06-09)

Rebuild of `Jivo-Price-Match-2026-06-09.xlsx` on the data fixed by **W1** (zepto full-seed
union 11→23 ids + lock-safe re-scrape/merge of ref pincodes 110095+560005) and confirmed
by **W3** (flipkart-minutes = REAL thin, no data fix).

**No code change** to `build_pricematch.py` — the rebuild is faithful-rendering only. The
sheet already auto-clears a false n/s the moment a real captured row lands (a missing seed
was the bug, in the data, not the renderer). `py_compile` clean; safety harness 11/0;
`master builder: byte-stable across two builds` (md5 identical on a repeat build);
`original sheets content-identical`; pm-history hook fired (904 rows).

## The owner's caught case — CANOLA 1+1L (zepto variant `50b56b7f`) @ 560005

| Sheet | Cell | BEFORE | AFTER |
|---|---|---|---|
| Amazon Core PM Check | Zepto @ 560005 | `·` (false n/s) | **₹485 in-stock** (green = above ref) |
| Amazon Core PM Check | Price match (same ₹) @ 560005 | `—` | `—` (485 ≠ Amazon Core 469) |
| Amazon Now PM Check | (whole row) | row absent (no competitor carried it) | **row now present**, Zepto @560005 = ₹485 |

**The false n/s is FIXED** — Zepto now shows the real captured in-stock price instead of the
quiet dot. **The ₹469 exact-match does NOT light up**, and that is the TRUTHFUL state: W1's
authoritative live-gateway probe (stable x3) returns SUPER_SAVER **₹485** / ULTRA_SAVER ₹461,
with **no ₹469 under any tier**. The owner's photo ₹469 (₹281 OFF / 37.5%) was a point-in-time
promo that ended (live now ₹265 OFF / 35% = ₹485) — a genuine intraday Zepto reprice, NOT a
scraper bug. We do not fabricate ₹469; we render what is live. (→ W5 owner answer.)

## Sweep of the 9 previously seed-missing zepto SKUs @ both ref pins (110095 / 560005)

After the seed fix, **all 9 now render real data (a price or OOS) at BOTH ref pins — zero
remaining `·` false n/s**:

| SKU | 110095 | 560005 | newly populated? |
|---|---|---|---|
| CANOLA 1+1L | OOS | **₹485** | yes — 560005 was `·` |
| EXTRA LIGHT 1L | ₹499 | ₹499 | (already present) |
| EXTRA LIGHT 2L | **₹1135** | **₹1135** | yes — both were `·` (now ⚡ Blinkit=Zepto @1135 on the exact col) |
| GROUNDNUT 1L | ₹199 | ₹199 | (already present) |
| JIVO POMACE 1L | ₹379 | ₹379 | (already present) |
| JIVO POMACE 1L + 1L | ₹758 | **OOS** | yes — 560005 was `·`, now authoritative OOS |
| JIVO POMACE 2L | **₹961** | **OOS** | yes — 110095 OOS→priced, 560005 `·`→OOS |
| MUSTARD 1L | ₹180 | ₹181 | (already present) |
| SUNFLOWER 1L | ₹192 | ₹192 | (already present) |

Authoritative absence (PDP says OOS/not-carried) renders as OOS / quiet `·`; a captured price
renders as the price. The rendering is faithful to the now-complete data.

## Exact-match column delta
Amazon Core PM Check exact cross-platform price-match SKUs **6 → 7** (the new one =
EXTRA LIGHT 2L, ⚡ Blinkit = Zepto @ ₹1,135 at 110095). CANOLA 1+1L is NOT among them
(485 ≠ 469) — correct.

## 5 original sheets unchanged
Sheet set identical (7 sheets). Ecom Head / Matrix / Above reference / Coverage & pending =
identical dimensions. Violations +3 rows = the 3 newly-captured in-stock zepto ref-pin rows
(CANOLA 1+1L @560005 485<529; EXTRA LIGHT 2L @560005 & @110095 1135<1229) + the count-label
text (2832→2835 store rows). red=undercut / green=above polarity, quiet-dot n/s, removed
comments, the ⚡ exact-match column, byte-stability, fail-safe, pm-history hook — all intact.

## What's still open (→ W5)
- Owner's specific ₹469==₹469 exact-match is no longer LIVE (promo ended; zepto now ₹485).
  The underlying complaint — "we showed it absent when it was live" — is FIXED.
- W2's wider false-n/s audit (`false_ns_audit.md`): amazon-now (31) + amazon-fresh (36)
  560005 coverage holes are UNOWNED data fixes (560005 added to amazon-fresh sweep set for
  tomorrow per LEAD); not in W4 scope (sheet renders them faithfully as `·`/pending).
