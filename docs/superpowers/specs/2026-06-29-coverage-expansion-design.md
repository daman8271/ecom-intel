# Design Spec — True Per-Pincode Coverage Expansion (ecom-intel)

**Date:** 2026-06-29
**Owner:** daman8271 / JIVO ecom
**Repo:** https://github.com/daman8271/ecom-intel.git
**Goal tracker:** `/goal` #12 (North-Star focus)
**Status:** Approved design → handing to `writing-plans`

---

## 1. One-line summary

Replace the anchor-cluster *extrapolation* model with **true per-pincode ground-truth scraping** for the 5 pincode-wise platforms across the 25 target cities (1,885 pincodes), gated by serviceability, with an honest coverage ledger, daily-full QC scraping that degrades gracefully, a staged city-by-city rollout that never breaks the live pipeline, and auto-push of data + all MD docs to GitHub.

## 2. Background — why (the honest current state)

Measured from the latest run (2026-06-28), against the 1,885-pincode universe of the 25 cities:

- **Only 234 / 1,885 pincodes (12.4%) are physically scraped** by any platform; the system is only *configured* to attempt 315 (17%).
- **3 of 8 live platforms have zero pincode granularity** — Flipkart-core, Amazon-core, BigBasket scrape a single *national* price (`pincode='-'`).
- **7 cities are at absolute zero:** Kochi, Bhubaneswar, Nashik, Vijayawada, Thiruvananthapuram (never configured — 0 anchors), Nagpur, Vadodara (1 anchor, returns no data).
- The dashboards headline **~1,200 "covered" pincodes**, but that is the **anchor extrapolation** (each scraped anchor *claims* ~80 nearby pincodes via `tools/pincodes/propagate.py`). Physically we scrape ~234. The big number is a model, not data.
- Even covered metros are thin: **Bengaluru 6/117 (5%)**; coverage **rotates daily** (Zepto 61→214 across two days).

The owner's directive: every pincode-wise platform must cover **its own** serviceable pincodes for real, with zero cities visibly closed, and nothing breaking.

## 3. Locked decisions (from brainstorming)

| Decision | Answer |
|---|---|
| Coverage model | **True per-pincode**, serviceability-gated ground truth (no extrapolation) |
| Platforms in scope | **5 pincode-wise**: Blinkit, Zepto, Flipkart-minutes (Wave 1) + Amazon-fresh, Amazon-now (Wave 2) |
| Out of scope | **3 national**: Flipkart-core, Amazon-core, BigBasket stay national-price (price genuinely has no pincode dimension) |
| Freshness | **Daily full push** on one IP; design degrades gracefully so a bad day = partial coverage logged, not a crash |
| Wave 1 (now) | Blinkit, Zepto, Flipkart-minutes → daily-full per-pincode |
| Wave 2 (later) | Amazon fresh+now on **2 dedicated accounts** (independent → parallel, removes the account-global serial bottleneck) once owner provides creds |
| City scope | **25 cities / 1,885 pincodes**; architecture extensible to all-India |
| Boundary | **No proxies / no WAF-evasion** (owner hard rule) — coverage capped by what one polite IP can do; we scrape politely + back off, never evade |
| Git | Auto-push data + **all MD docs** (README, REPORT, CLAUDE, coverage doc) to `daman8271/ecom-intel`; every push clean/formatted |

## 4. Success criteria (measurable)

1. For each Wave-1 platform, **every serviceable pincode** in all 25 cities is physically scraped and recorded in the coverage ledger, with `not_serviceable` explicitly recorded for the rest (no silent drops).
2. **Zero "never-configured" cities** remain — all 25 cities have a full per-pincode config for all 3 QC platforms.
3. The coverage report shows **real coverage %** (scraped ground truth), and the ~1,200 extrapolation headline is retired or explicitly relabeled "represented (modelled)".
4. The daily pipeline still completes and reports/mailer still ship (format unchanged: 9 xlsx as-is, never merged).
5. Data + README/REPORT/CLAUDE/coverage MD docs are committed and pushed to GitHub on every run, clean.
6. A bad scrape day (blocks, partial) **does not fail the batch** — it logs partial coverage and the guardian/doctor alerts.

## 5. Scope

**In scope:** Wave-1 QC platforms (Blinkit, Zepto, Flipkart-minutes) to true per-pincode daily-full across 25 cities; coverage ledger; serviceability sweep; scraper hardening; schedule restructure; reporting/dashboard honesty; QA scaling; git auto-push + MD doc sync. Wave-2 Amazon is designed but executed when creds arrive.

**Out of scope:** the 3 national platforms' pricing; all-India expansion beyond 25 cities (architecture stays extensible); any proxy/anti-bot evasion.

## 6. Architecture & components

The existing wiring we build on (verified, not assumed):

- **Config consumption:** each QC scraper reads `process.env.PINCODES_FILE || pincodes.json` (e.g. `platforms/blinkit/scrape.js:4`). Swapping the config is a supported mechanism; `pincodes.full.json` already exists as precedent.
- **Anchor pipeline:** `tools/pincodes/` (`cluster_anchors.py`, `gather_and_geocode.py`, `propagate.py`, `build_report.py`, `cities.json`) builds anchors and **propagates** anchor data to represented pincodes at report time. `history.csv` therefore holds real scraped anchors; extrapolation is a reporting-layer step.
- **Per-run schema:** `data/<platform>/history.csv` = `run_id,date_ist,platform,canonical_sku,city,pincode,price,mrp,discount_pct,in_stock`.
- **Orchestration:** `run.sh` (per-platform: scrape→excel→predict→review→vault→telegram→push) and `run_all.sh` / `tools/cron/deadline_sweep.sh` (the batch); QA via `tools/guardian_daily.sh` + `tools/cron/doctor.sh`.
- **Auto-push:** `run.sh:303-307` / `run_all.sh:362-366` do `git add vault data reviews baselines && git commit && git push` (pull --rebase --autostash fallback) under `.gitpush.lock`. **Configs, code, and root MD docs are NOT in this add-set today.**

### 6.1 Full per-pincode configs (replaces anchors)
New generator (extends `tools/pincodes/`) reads `docs/pincodes/drr_pincode.csv` + the 25-city district/division definitions (`docs/pincodes/compute_25_cities.py`) and emits, per platform, a **full per-pincode config** — one entry per pincode (`represents:1`), scoped to the 1,885 universe. Written as `platforms/<p>/pincodes.full25.json`; scrapers point at it via `PINCODES_FILE`. Anchor files preserved as `.bak`.

### 6.2 Coverage ledger (the honesty core)
New `data/coverage/ledger.csv` (or per-platform): `(platform, pincode, city, date_ist, run_id, status, sku_count, price_seen)` where `status ∈ {price_captured, serviceable_no_jivo, not_serviceable, error}`. This is the durable, queryable answer to "why 48 not 52" and the source of the real coverage %.

### 6.3 Serviceability discovery
A sweep (one-time, then weekly refresh) that, per platform × pincode, classifies serviceable / not + JIVO-listed, writing the ledger. Produces the **true denominator** per platform and the daily work-list (serviceable-first ordering). Daily runs still *attempt* the full universe (owner: daily-full) but use serviceability to order work and to record non-serviceable rather than silently skipping.

### 6.4 Scraper hardening — "nothing breaks"
Add to each QC scraper / its `run.sh` wrapper:
- **Checkpoint/resume** — per-pincode progress file so a crash mid-run resumes same-day instead of losing the batch.
- **Block-detection + polite backoff** — detect 403/429/Akamai/WAF signatures → exponential backoff, then pause + alert; never crash the batch.
- **Partial-run tolerance** — a platform that completes <100% logs partial coverage + a `partial` flag; the sweep continues and the guardian flags it.
- **Concurrency caps** — parallel across platforms (different domains, safe); polite serial-ish within a platform (no parallel hammering of one site from one IP).

### 6.5 Amazon Wave 2 (designed, executed later)
With **2 dedicated accounts** (one per platform), amazon-fresh and amazon-now drop the shared `.amazon-account.lock` serialization and run **independently in parallel**, each doing its own per-pincode location-set loop with checkpoint/resume. Prerequisite: owner provides 2 account creds → stored in `secrets.env` (0600, never in git, per cardinal rule).

### 6.6 Schedule / runtime restructure
Daily-full QC volume won't fit the single 04:00→noon window. Move to a **windowed schedule** (QC platforms start earlier / overnight, parallel across platforms), with the deadline predictor updated, reports still assembled by the morning deadline, mailer unchanged.

### 6.7 Reporting & dashboard honesty
- Per-platform report gains a **per-pincode coverage sheet** + rolling latest-price-per-pincode with a **freshness timestamp**.
- The live coverage report (`tools/pincodes/build_report.py` → Vercel) shows **real** coverage %; the modelled/represented number is relabeled, not presented as physical coverage.
- Mailer format unchanged (9 xlsx as-is, never merged — owner rule).

### 6.8 QA / monitoring at scale
Scale `guardian_daily.sh` + `doctor.sh` to the new volume; add **block-rate** and **coverage-drop** alerts to Telegram; a daily coverage-health one-liner.

### 6.9 Git auto-push + MD doc sync (owner requirement)
Extend the auto-commit add-set (`run.sh` / `run_all.sh`) to also keep in sync: `platforms/*/pincodes.full25.json`, `data/coverage/`, `docs/pincodes/`, and the root docs **README.md, REPORT.md, CLAUDE.md** + `docs/superpowers/specs/`. Build/code commits are formatted before commit. **Caveat:** the interactive auto-mode classifier blocks Claude's own `git push`; the **cron context auto-pushes fine** (it already does). Build-time code commits that can't auto-push are surfaced for the owner to push with `!`. Net: ongoing data + doc changes auto-push via cron; one-time build commits may need an owner `!`-push.

## 7. Data flow

`full per-pincode config → scraper (per pincode: serviceable? price?) → history.csv + coverage ledger → build_excel (per-pincode sheets + coverage %) → predict → review/guardian/doctor → vault → telegram (verdict-gated) → git add(data+docs) commit push`.

## 8. Phases & verification gates

| Phase | Deliverable | Gate (must pass before next) |
|---|---|---|
| **0 Foundation** | full per-pincode configs (1,885) per QC platform; coverage-ledger schema; anchor `.bak`; pipeline tagged `pre-coverage-expansion` rollback point | configs validate against the 1,885 universe; pipeline still runs unchanged with old config |
| **1 Serviceability sweep** | ledger filled per QC platform; true denominators | sweep covers 100% of 1,885 × 3; numbers sane vs platform footprints |
| **2 Scraper hardening** | checkpoint/resume, block-detect, backoff, partial-tolerance in 3 QC scrapers | fault-injection test: killed mid-run resumes; simulated 429 backs off, no crash |
| **3 Staged rollout** | (a) 5 zero-cities filled, (b) thin cities densified, (c) full 25-city universe — per platform | each step: coverage delta verified, guardian/doctor OK, committed; rollback = revert one config |
| **4 Schedule restructure** | windowed cron fits daily-full QC; deadline predictor updated | a full daily-full run completes within window; reports land on time |
| **5 Reporting/dashboard** | per-pincode coverage sheets, real coverage %, relabeled model number; MD docs updated | report renders; coverage % matches ledger; mailer still ships 9 xlsx |
| **6 QA/alerts at scale** | guardian/doctor scaled; block + coverage-drop Telegram alerts | alert fires on injected block/coverage-drop |
| **7 Git/doc sync** | extended auto-push set; README/REPORT/CLAUDE/coverage synced + pushed | a run pushes data + updated docs cleanly to GitHub |
| **Wave 2 Amazon** | 2-account parallel per-pincode for fresh+now | once creds arrive; same gates as QC |

## 9. Rollout & rollback

- **Stays live throughout:** the current pipeline keeps running on the old config until each platform/city is proven; rollout is per `(platform, city-batch)` behind `PINCODES_FILE`.
- **Rollback** at any step = point `PINCODES_FILE` back to the anchor `pincodes.json` (or revert the one config file) and re-run. Phase-0 git tag is the hard rollback point.
- **Order of value:** zero-cities first (visible gap), then thin metros (Bengaluru/Jaipur/Pune), then the long tail.

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Block/anti-bot from higher volume on one IP (no proxies) | polite serial-within-platform, exponential backoff, block-detect→pause+alert, daily-full as *attempt* with graceful partial; never evade |
| Daily-full doesn't fit the window | windowed schedule + parallel-across-platforms; serviceability-first ordering; partial-run tolerance so the deadline is never missed, only coverage% dips |
| Amazon account-global serial (12h×2) | deferred to Wave 2 with 2 accounts → independent + parallel |
| Classifier blocks Claude git push | cron auto-push works; build commits flagged for owner `!`-push |
| Report/mailer regression at scale | format frozen (9 xlsx as-is); coverage added as new sheets, not changes to existing ones; guardian gates |
| Extrapolation number misread as real | explicit relabel in report + dashboard |

## 11. Testing / verification

- **Unit:** config generator output validated against `compute_25_cities.py` city sets (every config pincode ∈ universe; counts match).
- **Fault-injection:** kill mid-run (resume), simulated 429/403 (backoff, no crash), empty result (partial flag).
- **Coverage reconciliation:** ledger coverage % == distinct scraped pincodes / serviceable per city (independent recount, like the audit that produced this spec).
- **End-to-end:** one full daily-full QC run → reports render → mailer ships → GitHub shows pushed data + updated docs.

## 12. Fleet execution mapping

The `/fleet` orchestration parallelizes **build & rollout** (safe — different files/cities), not live hammering of one site:
- One worker per **phase-0 config generation** per platform (3 parallel).
- One worker per **scraper-hardening** per platform (3 parallel), each with fault-injection verify.
- Rollout workers sharded by **city-batch** with an adversarial verify worker per batch (coverage delta + ledger reconciliation) before commit.
- A synthesis/verify worker reconciles totals and updates MD docs.

## 13. Wave-2 prerequisites (owner action)

- Provide **2 Amazon account credentials** (one for fresh, one for now) → stored in `secrets.env`, never in git.

## 14. Open items

- Exact windowed-schedule times (Phase 4) — derived from measured QC throughput in Phase 1–2.
- Whether to keep a weekly serviceability re-probe or fold it into daily-full (decided after Phase 1 numbers).
