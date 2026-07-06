# Jivo Shard Runner

This is the safe Mac/VPS helper lane for pincode platforms.

It is intentionally staged-only:

- split pincode configs deterministically with `index % total`
- run a platform shard in an isolated work directory
- write shard artifacts under `shards/runs/<run_id>/...`
- merge only on the VPS after validating manifest SHA, shard coverage, and duplicate-free pincodes
- never write live `platforms/<platform>/result.json` from a Mac worker

Enabled platforms:

```text
blinkit
zepto
flipkart-minutes
```

## Run One Shard

```sh
cd /opt/ecom-intel
tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json 2 1 "$(date +%Y%m%d-%H%M%S)-blinkit"
```

Artifacts land under:

```text
/opt/ecom-intel/shards/runs/<run_id>/blinkit/shard-1-of-2/
```

### Blinkit Auth Guard

Blinkit shards are auth-required. `run_platform_shard.sh blinkit ...` auto-discovers
the auth state from:

- `/opt/ecom-intel/secrets/blinkit-auth-state.json`
- `/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`

It exports `BLINKIT_REQUIRE_AUTH=1` and exits `3` if no auth state is available. The
merge step preserves Blinkit auth metadata: merged `summary.auth_session` is `1` only
when every shard was authenticated, and `summary.auth_required` is `1` if any shard
required auth. Downstream Blinkit ingest rejects unauthenticated drops by default.

## Merge On VPS

```sh
python3 tools/shards/merge_platform_shards.py blinkit /tmp/merged-result.json \
  /path/to/shard-0/manifest.0-of-2.json /path/to/shard-0/result.json \
  /path/to/shard-1/manifest.1-of-2.json /path/to/shard-1/result.json
```

Only after merge validation should a human or a later promoted script decide whether to promote the merged result into the live platform folder and run the existing report/review/delivery path.

## Mac Worker Pattern

Production daily Blinkit is not this manual shard lane. It runs as a full Mac Pro
collector through launchd:

```sh
/Users/danny./VPS-Migration/scripts/run_blinkit_mac_to_vps.sh
```

LaunchAgent:

```text
com.danny.blinkit-mac-to-vps
```

Schedule: `03:45` IST. The wrapper uses the persistent auth state at
`/Users/danny./VPS-Migration/secrets/blinkit-auth-state.json`, fails before scraping if
that file is missing/invalid, uploads the full result to the VPS, and invokes Blinkit
ingest with `BLINKIT_REQUIRE_AUTH_DROP=1`.

For a manual shard worker on the Mac, run from the current tree:

```sh
ssh macpro 'cd "$HOME/Jivo data/ecom-intel/current" && \
  BLINKIT_AUTH_STATE_FILE="$HOME/VPS-Migration/secrets/blinkit-auth-state.json" \
  ./tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json 2 1 "$(date +%Y%m%d-%H%M%S)-blinkit"'
```

The shard helper:

- uses the current repo tree on the Mac
- refuses to run while the Swiggy Mac job appears active
- runs the shard index/total passed on the command line
- rsyncs artifacts back to VPS staging only when `SYNC_DEST` is set

Manual shards remain staged artifacts only; production promotion and delivery are still
controlled from the VPS.

## Verified Smoke Tests

These checks were completed on 2026-07-03 IST with `BLINKIT_SIM=1`:

- Mac local staged run: produced one Blinkit shard result under `/Users/danny./Jibo/ecom-intel/current/shards/runs/<run_id>/blinkit/shard-1-of-2/`.
- Mac-to-VPS staged sync: pushed the same artifact shape to `/tmp/ecom-shard-smoke-sync/<run_id>/blinkit/shard-1-of-2/`.
- VPS split/merge simulation: merged shard `0-of-2` and shard `1-of-2` only after manifest and pincode coverage validation.

For a non-production Mac sync smoke:

```sh
ssh macpro 'cd "$HOME/Jivo data/ecom-intel/current" && \
  BLINKIT_SIM=1 ./tools/shards/run_platform_shard.sh blinkit /tmp/blinkit-two-pins-mac.json 2 1 smoke-blinkit'
```

For a real manual worker run after Swiggy is finished:

```sh
ssh macpro 'cd "$HOME/Jivo data/ecom-intel/current" && \
  BLINKIT_AUTH_STATE_FILE="$HOME/VPS-Migration/secrets/blinkit-auth-state.json" \
  ./tools/shards/run_platform_shard.sh blinkit platforms/blinkit/pincodes.daily.json 2 1 "$(date +%Y%m%d-%H%M%S)-blinkit"'
```

The real worker run still writes only staged artifacts. Promotion into live results remains a separate VPS-controlled decision.

## Guardrails

- Do not install launchd schedules for manual shard wrappers; only the full daily
  Blinkit Mac collector is scheduled.
- Do not point `SYNC_DEST` at a final report/result path.
- Do not use this lane for BigBasket without explicit paid-credit approval.
- Do not split Amazon Fresh/Now until account/session ownership is designed.
