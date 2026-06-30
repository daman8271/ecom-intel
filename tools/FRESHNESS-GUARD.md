# freshness_guard.py — data-freshness / coverage guard

Makes a silently-frozen data series LOUD before it reaches a graph. Stdlib-only, read-only, never crashes the build.

**What it does**
1. Per competitor platform: most-recent data date + rows/SKU trend from BOTH `baselines/<p>.json` and `data/<p>/history.csv` (freshest signal wins) -> GREEN (<=2d) / AMBER (3-6d or sharp drop vs trailing median) / RED (>6d or zero rows). Thresholds live in the `CONFIG` dict at the top.
2. Vault: buckets `~/jivo-data-bank/ecom/skus/*.md` by `last_seen`; flags any cluster (>=10 SKUs) frozen at one past date. The 2026-06-04 amazon-now correction (190 notes) is labelled **KNOWN/EXPECTED**; anything else is **INVESTIGATE**.
3. First-party: reads the real data column (`upload_date`, never the vault-touch `__last_seen`) in `~/jivo-data-bank/jivo/data/*price*.md` and flags stale tables (e.g. `amazon_price_data` stuck mid-May).

**Outputs:** `~/jivo-data-bank/DATA-FRESHNESS.md` (human) + `~/jivo-data-bank/data-freshness.json` (machine) + stdout summary. **Exits nonzero on any actionable RED** (a live platform that froze / zero rows; known-dead platforms and historical vault clusters do NOT gate). `--alert` sends the RED summary via Telegram if `secrets.env` has `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` (same pattern as `tools/guardian.py`), else prints a hook stub.

**Integration (run as the LAST step of the daily build, BEFORE the vault is pushed):**
```bash
python3 ~/ecom-intel/tools/freshness_guard.py --alert || { echo "[freshness] RED — not pushing graphs"; exit 1; }
```
