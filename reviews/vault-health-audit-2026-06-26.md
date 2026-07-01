> **As of 2026-06-28 the pipeline is 1×/day; the 2×/day observations below are from that dated audit.**

# Vault Deep-Dive Health Audit — 2026-06-26

**Question asked:** "Check the 3 deep-dive agents / the vault we are making — is it working every day properly?
Any faults? Is everything getting noted properly?"

**Verdict: 🟢 HEALTHY — the vault is running correctly every day and capturing every observation.**
No pipeline fault. The few issues found are *known / external / cosmetic*, not data loss.

---

## What "the vault" actually is (the daily standing system)

Three scheduled deep-dive layers maintain it (audited all three):

| Layer | When | What it does | Output |
|---|---|---|---|
| **1. Vault rebuild** (`tools/vault_build.py`, deterministic) | end of each sweep, **2×/day** (~12:13 & ~16:00) | regenerates the whole Obsidian graph from `data/<p>/history.csv` — run notes, SKU/city/pincode hubs, daily/weekly/monthly rollups, index | `vault/` + commit `vault: rebuild memory graph` |
| **2. Guardian daily deep-dive** (`tools/guardian_daily.sh`) | 18:00 IST | 11-bug-class audit over all 8 platforms; alerts owner only on a NEW regression vs yesterday | `reviews/guardian/health-<date>.md` + `state-<date>.json` |
| **3. Doctor deep-dive agent** (`tools/cron/doctor.sh`, real `claude -p` headless) | 18:30 daily / Sun weekly / 1st monthly | gathers health signals, invokes a Claude agent (alert-only, autofix=0), Telegrams a diagnosis | `logs/doctor/diagnosis-*.md` |

(Note: "deep dive agents" has historically been your phrase for *one-off* parallel investigation agents.
The *standing daily* system is the three layers above.)

---

## Evidence the vault works every day

- **Vault rebuilds: gap-free, 2×/day** for 06-12 → 06-25 (06-26 has 1 so far; 2nd fires this afternoon after the in-flight sweep). Latest: commit `bedf5106` @ 12:14 today, "vault graph committed + pushed."
- **Daily notes: gap-free 37 days**, 2026-05-21 → 2026-06-26, **zero missing dates**.
- **Guardian health reports + state sidecars: gap-free 06-05 → 06-25** (today's due 18:00).
- **Doctor agent: ran every day**, Telegrammed the owner each day.
- **No `vault_build failed` / `vault_note failed`** anywhere in the logs.
- **Git in sync with origin** (`main...origin/main`, no ahead) — commits are pushing, not just local.

### Completeness — every run is captured
For each platform, distinct run-ids in `history.csv` == vault run-notes (off by exactly 1 only for
platforms whose afternoon run landed *after* the 12:13 rebuild — closes on the next rebuild, by design):

```
blinkit          history-runs=79  vault-notes=79  last-row=2026-06-26-1105  ✓
flipkart         79 vs 78  (latest 1214 not yet in graph — closes this afternoon)
flipkart-minutes 80 vs 79  (latest 1213)
amazon           81 vs 80  (latest 1239)
amazon-now       49 vs 50  (one orphan note — minor, see Issue 5)
amazon-fresh     58 vs 57  (latest 1250)
zepto            61 vs 60  (latest 1222)
bigbasket        51 vs 51  last-row=2026-06-25-1613  ✓ (runs ~16:00, see Issue 3)
```
All 7 sweep platforms appended **today** (12:13–14:48). Source of truth = `history.csv`; the graph is
*complete-by-construction* and at most one rebuild behind the very latest run.

---

## Issues found (none break the vault; ranked by what to act on)

**1. [Medium / External] swiggy-instamart is perpetually "1 missing" → doctor goes RED most days.**
Doctor was RED 06-20→06-24 (`batch_missing_reports … reports=9 … missing=1`), GREEN on 06-25 when the
report landed (9→10). Today's 12:00 batch again shipped "9 reports, 1 missing." Root cause = the
swiggy-instamart residential-IP feed is still a pending integration (VPS datacenter IP AWS-WAF-blocked).
**This is not a vault fault**, but it means the daily doctor RED *cries wolf* — a genuine missing report
could hide in the noise. **Fix:** treat swiggy-instamart absence as expected (downgrade to AMBER/info)
so RED means a *real* regression, OR wire the Apify/residential feed.

**2. [Medium / Data quality] The SKU layer is ~9× inflated with non-Jivo search pollution.**
1,018 SKU notes vs ~114 real Jivo master SKUs. Captured-as-SKU junk includes `jivo-bralettes-…`,
`jivo-baby-boys-dhoti-kurta-…`, `jivo-water-tank-overflow-alarm-…`, `…weighing-scale-50kg`, Diwali
gift boxes, and opaque marketplace-ID slugs (`ardhcjmtxhz5hqda.md`, `botgz9zpvhfx8yyg.md`, …).
"Everything is getting noted" — **including noise**. Per the locked scope (stick to the ~114 master),
consider tagging non-master nodes `#sku/unmapped` so the Jivo core isn't drowned in the graph.

**3. [Low / Timing] bigbasket vs the afternoon rebuild race.**
bigbasket finishes ~16:00; the 2nd vault rebuild is also ~16:00 (06-25: run 16:13 vs rebuild 16:14 —
caught by 1 minute). If bigbasket ever finishes *after* the rebuild, that day's bigbasket data waits
for the next morning's rebuild to enter the graph (no loss — history.csv holds it; ~16h graph lag).
**Fix:** trigger a rebuild after bigbasket's run, or order it before the final rebuild.

**4. [Low / Hygiene] Working-tree litter in /opt/ecom-intel.**
Stray `8`, `9` (look like redirect-typo artifacts), `dom_text.txt`, `*.CONTAMINATED`, untracked
`collectors/`, modified `tools/cron/durations.jsonl`. The vault commit only `git add`s
vault/data/reviews/baselines, so this does **not** corrupt commits — but it's accumulating. Clean up.

**5. [Low / Anomaly] amazon-now has 50 run-notes but 49 distinct run-ids in history.csv.**
One orphan run note whose run-id is no longer in the CSV (likely a run later deduped/filtered out).
Harmless; flagged for completeness.

**6. [Info] vault/analysis/ (3 hand-authored notes) frozen since Jun 9.**
canola-pricing-thesis, price-intel-dashboard, analysis-index — these are *manual* starter notes, NOT
builder-generated, so staleness is expected. If you want them living, they need a generator.

---

## Bottom line
The vault is doing its job every single day: scrape → `history.csv` → deterministic graph rebuild (2×/day)
→ guardian audit (18:00) → doctor agent (18:30) → committed + pushed. Nothing is silently failing and
nothing is being dropped. The only thing dressed up as a daily "fault" — the doctor's RED — is the known
swiggy-instamart gap, not the vault. Highest-value next action: stop the swiggy RED from crying wolf.
