# 🫒 Mac Worker Brief — Blinkit Olive-Oil Competitor Scrape (Goal #54)

**You are a Claude Code worker running on a Mac (residential IP).** A teammate ("VPS lead") is
scraping the other half of the work on a Linux VPS right now. Your job: scrape the **Blinkit**
olive-oil catalog for **your assigned pincode shard**, then hand the raw JSON back. When both
halves merge, we get full 9-state coverage.

**Why this exists (say it back to yourself so you don't drift):** competitor research for **JIVO**
(edible-oil brand). We are measuring, *per pincode*, which olive-oil **sellers/brands** Blinkit
lists **in stock** — Figaro, Borges, Del Monte, DiSano, Oleev, Leonardo, Bertolli, Jivo, and every
other brand — across Maharashtra, Karnataka, Tamil Nadu, Delhi, Gujarat, West Bengal, Telangana,
Uttar Pradesh, Haryana. Goal: a state-wise "who dominates olive oil on Blinkit, and where is Jivo
absent while rivals are present" picture. You handle **1,586 pincodes**; the VPS handles the other
1,586. **Disjoint halves — no overlap.**

---

## 🚫 Hard rules (do not violate)
1. **Blinkit only, authenticated.** Use the saved Blinkit auth state at
   `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`; do not print or copy
   token values. Anonymous Blinkit can produce false Out of Stock rows.
2. **CONCURRENCY = 2. Never higher.** Blinkit rate-limits per IP; at ≥3 pincodes stop resolving
   and you silently lose coverage. 2 is the accuracy-preserving max.
3. **No proxies, no anti-bot / WAF evasion, no fingerprint spoofing.** Owner boundary.
   Plain authenticated requests from your normal residential IP only.
4. **Stay isolated.** Work entirely under `~/olive-mac`. Do **not** modify or run the live
   ecom-intel pipeline (its cron, `result.json`, `tools/competitor/data/` live files, the mailer).
5. **One scraper process at a time.** You may use sub-agents for monitoring/QA, but only ONE
   `node scrape.js` may hit Blinkit at once (see rule 2).
6. Node 18+ is already installed. Good.

---

## Phase 0 — Get the bundle (from the shared repo)
The VPS lead committed everything you need under `tools/competitor/olive-research/`.

```bash
cd ~/ecom-intel        # your local clone of daman8271/ecom-intel  (adjust path if different)
git pull
ls tools/competitor/olive-research/
#   expect: scrape.js  package.json  competitor_brands.json  category_queries.json  universe.mac.json  MAC-BRIEF.md
```
Sanity-check your shard:
```bash
python3 -c "import json;d=json.load(open('tools/competitor/olive-research/universe.mac.json'));print(len(d),'pincodes; sample:',d[0])"
# -> 1586 pincodes
```

---

## Phase 1 — Build your isolated workspace `~/olive-mac`
```bash
BUNDLE=~/ecom-intel/tools/competitor/olive-research
LEAD=~/olive-mac
mkdir -p $LEAD/platforms/blinkit $LEAD/tools/competitor/data $LEAD/logs
cp $BUNDLE/scrape.js            $LEAD/platforms/blinkit/scrape.js     # fast-fail build (already patched)
cp $BUNDLE/package.json         $LEAD/platforms/blinkit/package.json
cp $BUNDLE/competitor_brands.json $LEAD/tools/competitor/competitor_brands.json   # OPEN olive brand gate
cp $BUNDLE/category_queries.json  $LEAD/tools/competitor/category_queries.json    # ["olive oil"] (+jivo auto)
cp $BUNDLE/universe.mac.json    $LEAD/universe.mac.json
```
**Playwright/Chromium** (the scraper needs it). Try to reuse your repo's install; else install fresh:
```bash
cd $LEAD/platforms/blinkit
if [ -d ~/ecom-intel/platforms/blinkit/node_modules/playwright ]; then
  ln -sfn ~/ecom-intel/platforms/blinkit/node_modules ./node_modules
else
  npm init -y >/dev/null 2>&1; npm i playwright && npx playwright install chromium
fi
node -e "require('playwright'); console.log('playwright OK')"
```

---

## Phase 2 — Create your run script
```bash
cat > ~/olive-mac/run_shard.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE=~/olive-mac; BASE=$(eval echo "$BASE")
PF="${1:?usage: run_shard.sh <pincodes_file> <date_tag> [conc]}"; TAG="${2:?}"; CONC="${3:-2}"
case "$PF" in /*) ;; *) PF="$BASE/$PF";; esac
cd "$BASE/platforms/blinkit"
LOG="$BASE/logs/scrape-$TAG.log"
N=$(python3 -c "import json;print(len(json.load(open('$PF'))))")
echo "[run_shard] $(date '+%F %T %Z') START tag=$TAG pincodes=$N conc=$CONC fast-fail" | tee -a "$LOG"
BLINKIT_REQUIRE_AUTH=1 BLINKIT_AUTH_STATE_FILE="/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json" \
  COMPETITOR_MODE=1 PINCODES_FILE="$PF" COMPETITOR_DATE="$TAG" CONCURRENCY="$CONC" \
  RESOLVE_ATTEMPTS=2 RESOLVE_POLLS=3 BLINKIT_BLOCK_RETRIES=2 \
  node scrape.js >> "$LOG" 2>&1
echo "[run_shard] $(date '+%F %T %Z') DONE tag=$TAG -> tools/competitor/data/blinkit_competitor_$TAG.json" | tee -a "$LOG"
SH
chmod +x ~/olive-mac/run_shard.sh
```

---

## Phase 3 — Smoke test (2 pins — MUST pass before the full run)
```bash
cat > ~/olive-mac/smoke2.json <<'JSON'
[{"city":"Mumbai","pincode":"400050","locality":"Bandra West","lat":19.0596,"lon":72.8295,"landmark":"Bandra West, Mumbai"},
 {"city":"Bengaluru","pincode":"560001","locality":"Bengaluru GPO","lat":12.9716,"lon":77.5946,"landmark":"Bengaluru GPO"}]
JSON
cd ~/olive-mac/platforms/blinkit
BLINKIT_REQUIRE_AUTH=1 BLINKIT_AUTH_STATE_FILE="/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json" \
  COMPETITOR_MODE=1 PINCODES_FILE=~/olive-mac/smoke2.json COMPETITOR_DATE=smoke-mac CONCURRENCY=2 \
  RESOLVE_ATTEMPTS=2 RESOLVE_POLLS=3 node scrape.js 2>&1 | grep -E "\[ok:comp\]|\[unresolved\]|\[blocked\]|SUMMARY"
python3 -c "import json;d=json.load(open('$HOME/olive-mac/tools/competitor/data/blinkit_competitor_smoke-mac.json'));r=d.get('allRows') or [];print('rows:',len(r),'| brands:',sorted(set((x.get('name') or '').split()[0] for x in r))[:12])"
```
**PASS = both pins resolve and you see ~15–30 olive rows with multiple brands (Borges/Figaro/Oleev/etc.).**
If you see `[blocked]` on both → your IP is being challenged; wait 10 min and retry once. If it
persists, STOP and tell the user (do not evade). Then clean up: `rm ~/olive-mac/tools/competitor/data/*smoke-mac* ~/olive-mac/tools/competitor/data/.progress*smoke-mac* ~/olive-mac/smoke2.json`

---

## Phase 4 — Run your full shard (detached, ~2.5–3 h)
```bash
cd ~/olive-mac
setsid bash ~/olive-mac/run_shard.sh universe.mac.json olive10-mac 2 </dev/null >/dev/null 2>&1 &
sleep 8; tail -3 ~/olive-mac/logs/scrape-olive10-mac.log
```
It is **resume-safe** — if it dies, just re-run the same command; it skips finished pincodes.

## Phase 5 — Monitor (every ~20–30 min)
```bash
python3 -c "import json,os;f=os.path.expanduser('~/olive-mac/tools/competitor/data/.progress.competitor.blinkit.olive10-mac.json');p=json.load(open(f));print(f'{len(p)}/1586 done, {sum(1 for v in p.values() if isinstance(v,dict) and v.get(\"resolved\"))} serviceable')"
pgrep -af 'node scrape.js' | head   # confirm still alive
```
Most pincodes are urban/serviceable (~15s each); rural ones fast-fail (~12s). Expect completion in
~2.5–3 h.

## Phase 6 — Deliver back to the lead
When Phase 5 shows `1586/1586`:
```bash
RES=~/olive-mac/tools/competitor/data/blinkit_competitor_olive10-mac.json
cp "$RES" ~/ecom-intel/tools/competitor/olive-research/results/blinkit_competitor_olive10-mac.json
cd ~/ecom-intel
git add tools/competitor/olive-research/results/blinkit_competitor_olive10-mac.json
git commit -m "olive #54: Mac shard result (1586 pins)"
git push
```
Then tell the user in one line: **"Mac half DONE — N/1586 pincodes, X serviceable, Y olive rows;
pushed to olive-research/results/."** The VPS lead pulls it and merges.

*(If `git push` fails/auth-blocked, instead zip the result and send it to the user to relay:
`cd ~/olive-mac/tools/competitor/data && zip mac-result.zip blinkit_competitor_olive10-mac.json`.)*

---

## 🧠 Optional — multi-agent orchestration (encouraged, but respect rule 2)
While the single scraper runs, you may spawn sub-agents to work in parallel on *non-Blinkit* things:
- a **watchdog** agent that checks Phase-5 progress every 20 min and alerts if it stalls >15 min or hits repeated `[blocked]`;
- a **QA** agent that, once done, validates the output schema (every row has `pincode, name, brand, in_stock, sale, pack`) and reports the serviceable-rate + brand histogram;
- a **spot-check** agent that re-scrapes 3 random serviceable pincodes and confirms they match.
Do **not** spawn multiple scraper processes — that breaks the IP rate limit and corrupts data.

## Row schema you're producing (per olive SKU per pincode)
`platform, city, pincode, store_id, brand, name, canonical, category, sub_grade, pack, vol_ml,
per_litre, mrp, sale, discount_pct, in_stock (1/0), rank, is_ad, captured_at`.
`brand`/`sub_grade` are rough at scrape time — the lead re-derives clean brand + grade
(Pomace / Extra-Light / Extra-Virgin / Pure) from `name` in post-processing. Your job is just
faithful capture. **Ping the user the moment the smoke test passes and again when the shard is done.**
