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

## Merge On VPS

```sh
python3 tools/shards/merge_platform_shards.py blinkit /tmp/merged-result.json \
  /path/to/shard-0/manifest.0-of-2.json /path/to/shard-0/result.json \
  /path/to/shard-1/manifest.1-of-2.json /path/to/shard-1/result.json
```

Only after merge validation should a human or a later promoted script decide whether to promote the merged result into the live platform folder and run the existing report/review/delivery path.

## Mac Worker Pattern

On the Mac, use:

```sh
/Users/danny./Jibo/workload-sharing/run_blinkit_half_to_vps.sh
```

That wrapper:

- uses `/Users/danny./Jibo/ecom-intel/current`
- refuses to run while the Swiggy Mac job appears active
- runs shard `1-of-2` by default
- rsyncs artifacts back to VPS staging under `/opt/ecom-intel/shards/inbox/macpro/`

No launchd schedule is installed yet.

