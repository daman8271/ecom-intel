# SESSION MEMORY — JIVO data-bank build (handoff for the next session)

> Full record of the 2026-06-27/28 session so a fresh Claude can continue seamlessly. Owner: Daman.
> Companion to the canonical record `/opt/ecom-intel/docs/jivo-databank/BUILD-JOURNAL.md`.

## THE GOAL (unchanged)
Build a unified JIVO **data bank = 3 vaults**: (1) ECOM-Intel scraper (`/opt/ecom-intel`, repo
daman8271/ecom-intel) standalone; (2) JIVO-app vault (`/root/jivo-intel`, repo daman8271/jivo-intel)
standalone; (3) a **COMBINED** vault (lives in the ecom-intel repo) where each product is ONE Obsidian node
carrying BOTH its app-internal data AND its competitor price, connected (product↔tier↔category↔platform↔
vendor↔location↔month) for pattern analysis. **Connections are the deliverable, not raw extraction.**

## WHAT'S DONE (≈65–70% of the goal — the foundations)
1. **App fully extracted** → `/root/jivo-intel`: lossless SSOT (`store/versioned/`, 1,312,518 rows, 41 tables
   100%) + Obsidian vault (`vault/`, 34,749 notes). Verified lossless (4 gates + adversarial PASS).
2. **SKU bridge** → 170/178 products matched (price-match `sku_map.json`/`history.csv` = the Rosetta Stone;
   8 are bulk pack-size gaps, 1 cola = confirmed same). Artifacts in `docs/sku-bridge/`.
3. **App learned** → `docs/app-model/` (4 MD + `JIVO-App-Model.html`). Value chain: Wellness 811,616@₹180 →
   JM Primary 672,739@₹192.6 → Primary 484,975@₹210.3 → Secondary 560,048@₹218.2 (Jun-2026). PREMIUM/
   COMMODITY/OTHER axis. 13 pages. Drill-down Category→Subcat→Platform→SKU.
4. **Target sheets** → cracked the historical endpoint `GET /api/platform/{month-targets|primary-month-targets}/dashboard?month=&year=`
   (Bearer auth; the CLI's `month-targets` ignores dates). Full 2024→2026 history in `docs/app-model/
   target-history.csv`. Targets only set from **Apr-2026** (older months = actuals only). Graph:
   `targets-over-years.html`.
5. **2026 deep-dive** → `/opt/ecom-intel/docs/jivo-databank/deep-dive-2026/` (4 reports + `2026-DEEP-DIVE.md`).

## WHAT'S NEXT (the remaining ≈30–35%)
**Build the COMBINED vault** (the merge): for each bridged product, one node with app-internal (sales/
inventory/POs/targets/margins/premium-mix) + scraper competitor-price, connected. This is goal #4 steps 3–5.
Owner wants to start this next, together.

## ERRORS FOUND (owner's independent review at jivo-model-review-site.vercel.app) + ROOT CAUSE
Independent reviewer confirmed ~95% architecture + 13/16 anomalies + 41 tables + the join model — **core is
sound, not hallucinated.** But found:
- **REAL #1:** "OTHER ≈26,271 L residual" in the Primary value chain was **WRONG** — verified OTHER=0;
  premium+commodity=484,975 exactly. The 26,271 was a gap between two *different* Primary metrics
  (stale `primary-po-litres` 458,703 vs the Primary card 484,975), mislabeled as an OTHER bucket.
- **REAL #2 (suspect):** Marketing "₹25.3M→₹354M = 14× ROAS" likely **conflates platform scopes**
  (Amazon-only is ₹4.78M→₹52.5M = 11×). Treat as unreliable until re-derived per-scope.
- **Everything else flagged = STALENESS** (my 06-27 snapshot vs reviewer's ~06-28 live; 3–6% drift:
  premium/commodity split, secondary 560k→554k, YoY +78%→+87%, Amazon fill 42→44%, master_po union was
  EXACT at my snapshot 44,081=44,081 but drifts, soh-doh was zeroed then & app has since fixed it).
- **ROOT CAUSE / LESSON:** the numbers agents READ were right; some CAUSAL STORIES they wrapped around them
  weren't. → (a) verify any agent's causal claim ("gap = OTHER") against raw data before relaying;
  (b) reconcile SCOPE before aggregating (all-platform vs single-platform); (c) **date-stamp every figure
  "as of <date>"** — live drifts, a snapshot is not live.
- **TODO (corrections to apply to the docs):** fix the OTHER-26,271 mislabel in app-model + the 2026 deep-dive;
  re-derive the marketing ROAS per-scope or mark unreliable; tighten "citymall/zomato empty" →
  "empty on secondary+inventory only (they have live POs)".

## OWNER STANDING RULES (also in memory `jivo-workflow-prefs.md`)
- Publish HTML **only via Vercel**. Every GitHub push **clean/formatted**. **3 vaults**, kept distinct.
- App auth: token ~24h, refresh `auth login` (creds owner-side, never stored; GA/FB cookies don't auth).
  Current token (dp605702@jivo.in) expires ~2026-06-29 00:57 IST.

## GITHUB / PUSH STATUS (classifier blocks Claude from pushing — OWNER runs these)
- Repo **daman8271/jivo-intel** CREATED (private), everything committed + LFS-migrated (whale files).
  NOT pushed: `! cd /root/jivo-intel && git push -u origin master`
- Repo **daman8271/ecom-intel** — `docs/jivo-databank/` committed (several commits ahead). NOT pushed:
  `! cd /opt/ecom-intel && git push origin main`
- ⚠️ LFS note: after a fresh clone/migrate, run `git lfs checkout` in jivo-intel or the whale files are pointers.

## WHERE EVERYTHING LIVES
- `/root/jivo-intel/` (app project: SSOT, vault, bin/, docs/app-model, docs/sku-bridge).
- `/opt/ecom-intel/docs/jivo-databank/` = THE ONE PLACE (BUILD-JOURNAL.md, app-model/, sku-bridge/, deep-dive-2026/).
- Memory: `/root/.claude/projects/-root/memory/` (jivo-intel-megabrain, jivo-app-model, jivo-workflow-prefs, this handoff).
- Goals: `~/.claude/goals/goals.json` (#4 = the merge, the live one).
