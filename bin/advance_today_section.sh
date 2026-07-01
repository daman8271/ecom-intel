#!/usr/bin/env bash
# =============================================================================
# advance_today_section.sh — EAGER per-section today/ advance (one source).
#
# Advances a SINGLE logical source's slice of the verbatim today/ snapshot the
# moment that source is ready, without waiting for the other three. Complements
# build_today.sh (which stays the atomic all-4 end-of-day consistency build).
#
#   source            data-bank subdir             own-repo mirror
#   ---------------   --------------------------   ------------------------------
#   factory           today/factory/               /root/jivo-factory-intel/today/ (whole)
#   ecom-app          today/ecom-app/              /root/jivo-intel/today/         (whole)
#   price-scraper     today/price-scraper/         (ecom mirror deferred to build_today)
#   competitors       today/competitors/           (ecom mirror deferred to build_today)
#
# The data-bank today/ is what HERMES/Param reads — it is always advanced here.
# The shared ecom repo mirror (price-scraper + competitors share one today/) is
# left to build_today.sh's clean atomic ps+comp swap to avoid partial-slice risk.
#
# Zero-loss: stage -> count+sha256 verify -> per-subdir atomic swap. On ANY
# mismatch it aborts, drops the tmp, leaves the prior today/<slice> untouched.
# Single-flight: shares build_today.lock so it never races the atomic build.
#
#   advance_today_section.sh <source> [--date YYYY-MM-DD] [--dry-run]
# =============================================================================
set -uo pipefail
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C

SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SELFDIR/build_today.log"
LOCK="$SELFDIR/build_today.lock"
EMPTY_TREE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"

ECOM_REPO="/opt/ecom-intel"
FACTORY_REPO="/root/jivo-factory-intel"
APP_REPO="/root/jivo-intel"
DB_REPO="/root/jivo-data-bank"
DB_TODAY="$DB_REPO/today"

SECRETS="/opt/ecom-intel/secrets.env"
TG_HELPER="/root/telegram_helper.py"

SRC=""; DATE=""; DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --date) DATE="${2:-}"; shift 2 ;;
    --date=*) DATE="${1#*=}"; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    price-scraper|competitors|factory|ecom-app) SRC="$1"; shift ;;
    *) echo "advance_today_section.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SRC" ] || { echo "usage: advance_today_section.sh <source> [--date D] [--dry-run]" >&2; exit 2; }
TODAY="$(TZ=Asia/Kolkata date +%F)"
DATE="${DATE:-$TODAY}"
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "bad --date '$DATE'" >&2; exit 2; }
IS_TODAY=0; [ "$DATE" = "$TODAY" ] && IS_TODAY=1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/advance_today.XXXXXX")"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

log(){ printf '[%s] adv[%s]: %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$SRC" "$*" | tee -a "$LOG" >&2; }
tg(){ [ "$DRYRUN" = "1" ] && return 0
  [ -f "$SECRETS" ] && [ -f "$TG_HELPER" ] || return 0
  ( set -a; . "$SECRETS" 2>/dev/null || true; set +a
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
    python3 "$TG_HELPER" send "$1" >/dev/null 2>&1 || true ) || true; }
abort(){ log "ABORT: $*"; rm -rf "$DB_TODAY/$SRC.tmp" "$WORK" 2>/dev/null || true
  tg "🛑 advance_today_section[$SRC] FAILED $DATE: $*"; exit 1; }

case "$SRC" in
  price-scraper|competitors) REPO="$ECOM_REPO" ;;
  factory) REPO="$FACTORY_REPO" ;;
  ecom-app) REPO="$APP_REPO" ;;
esac
VAULT="$REPO/vault"

# ---- readiness (identical to build_today.sh src_ready) ----------------------
src_ready(){ local c
  case "$SRC" in
    price-scraper) [ -f "$ECOM_REPO/vault/daily/$DATE.md" ] ;;
    competitors)   [ -f "$ECOM_REPO/vault/competitor/daily/Competitor-$DATE.md" ] ;;
    ecom-app)      git -C "$APP_REPO" log --grep="^daily ${DATE}\$" -1 --format=%H 2>/dev/null | grep -q . ;;
    factory)
      [ "$(TZ=Asia/Kolkata date -r "$FACTORY_REPO/render-proof.json" +%F 2>/dev/null)" = "$DATE" ] && return 0
      c="$(TZ=Asia/Kolkata git -C "$FACTORY_REPO" rev-list -1 --since="$DATE 00:00:00" --before="$DATE 23:59:59" HEAD -- vault 2>/dev/null)"
      [ -n "$c" ] ;;
  esac
}

exec 9>"$LOCK" || { echo "cannot open lock $LOCK" >&2; exit 1; }
if ! flock -n 9; then log "build_today.lock held — exiting"; exit 0; fi

log "=== advance start (date=$DATE dry_run=$DRYRUN) ==="
if ! src_ready; then log "not ready for $DATE — nothing to do"; exit 0; fi

# already at DATE?  (skip if the data-bank subdir manifest already records it)
cur="$(python3 - "$DB_TODAY/_manifest.json" "$SRC" <<'PY' 2>/dev/null || true
import json,sys
try:
    d=json.load(open(sys.argv[1])); print(d.get("sources",{}).get(sys.argv[2],{}).get("date",""))
except Exception: print("")
PY
)"
if [ "$cur" = "$DATE" ] && [ "$DRYRUN" = "0" ]; then log "already at $DATE — no-op"; exit 0; fi

# ---- diff window ------------------------------------------------------------
base="$(TZ=Asia/Kolkata git -C "$REPO" rev-list -1 --before="$DATE 00:00:00" HEAD 2>/dev/null)"; [ -n "$base" ] || base="$EMPTY_TREE"
if [ "$IS_TODAY" = "1" ]; then end="HEAD"; else
  next="$(TZ=Asia/Kolkata date -d "$DATE +1 day" +%F)"
  end="$(TZ=Asia/Kolkata git -C "$REPO" rev-list -1 --before="$next 00:00:00" HEAD 2>/dev/null)"; [ -n "$end" ] || end="HEAD"; fi
BASE_SHA="$(git -C "$REPO" rev-parse "$base" 2>/dev/null || echo "$base")"
END_SHA="$(git -C "$REPO" rev-parse "$end" 2>/dev/null || echo "$end")"

porcelain_paths(){ git -C "$REPO" status --porcelain -z -- "$@" 2>/dev/null | (
  while IFS= read -r -d '' e; do [ -n "$e" ] || continue
    local xy="${e:0:2}" p="${e:3}"; case "$xy" in *R*|*C*) IFS= read -r -d '' _o 2>/dev/null||true;; esac
    printf '%s\n' "$p"; done ); }

case "$SRC" in
  price-scraper) PS=('vault/' ':(exclude)vault/competitor/**') ;;
  competitors)   PS=('vault/competitor') ;;
  factory|ecom-app) PS=('vault') ;;
esac
{ git -C "$REPO" diff --name-only --diff-filter=AMR "$base" "$end" -- "${PS[@]}" 2>/dev/null
  [ "$IS_TODAY" = "1" ] && porcelain_paths "${PS[@]}"
  [ "$SRC" = "competitors" ] && printf '%s\n' "vault/competitor/daily/Competitor-$DATE.md" "vault/competitor/Competitor-Watch.md"
} | grep -E '\.md$' | sort -u | while IFS= read -r f; do [ -f "$REPO/$f" ] && printf '%s\n' "$f"; done > "$WORK/reporel"
sed 's#^vault/##' "$WORK/reporel" > "$WORK/vaultrel"
CNT="$(wc -l < "$WORK/reporel" | tr -d ' ')"
log "changed: $CNT md files"
[ "$CNT" -gt 0 ] || abort "0 changed md for $SRC (unexpected) — refusing"

# ---- stage into data-bank subdir tmp + zero-loss verify ---------------------
TMP="$DB_TODAY/$SRC.tmp"; rm -rf "$TMP"; mkdir -p "$TMP"
rsync -a --files-from="$WORK/vaultrel" "$VAULT/" "$TMP/" 2>>"$LOG" || abort "rsync failed -> $TMP"
: > "$WORK/src"; : > "$WORK/dst"
while IFS= read -r r; do printf '%s\n' "$VAULT/$r" >> "$WORK/src"; printf '%s\n' "$TMP/$r" >> "$WORK/dst"; done < "$WORK/vaultrel"
act="$(find "$TMP" -type f | wc -l | tr -d ' ')"
[ "$CNT" = "$act" ] || abort "count mismatch: expected $CNT dest $act"
sh1="$(xargs -r -a "$WORK/src" -d '\n' sha256sum | awk '{print $1}')"
sh2="$(xargs -r -a "$WORK/dst" -d '\n' sha256sum | awk '{print $1}')"
[ "$sh1" = "$sh2" ] || abort "sha256 mismatch (byte divergence source vs staged)"
log "verify OK: $CNT files, sha256 byte-identical"

if [ "$DRYRUN" = "1" ]; then
  log "--dry-run: staged+verified at $TMP; NO swap/commit. Leaving tmp for inspection."
  exit 0
fi

# ---- atomic per-subdir swap (data-bank) -------------------------------------
DST="$DB_TODAY/$SRC"
rm -rf "$DST.prev" 2>/dev/null || true
[ -d "$DST" ] && mv "$DST" "$DST.prev"
mv "$TMP" "$DST" || abort "atomic subdir swap failed for $SRC"
log "data-bank today/$SRC advanced to $DATE ($CNT files)"

# ---- own-repo mirror (clean single-source repos only) -----------------------
GEN="$(TZ=Asia/Kolkata date '+%F %T %Z')"
mirror_repo=""
[ "$SRC" = "factory" ]  && mirror_repo="$FACTORY_REPO"
[ "$SRC" = "ecom-app" ] && mirror_repo="$APP_REPO"
if [ -n "$mirror_repo" ]; then
  MT="$mirror_repo/today.tmp"; rm -rf "$MT"; mkdir -p "$MT"
  rsync -a --files-from="$WORK/vaultrel" "$VAULT/" "$MT/" 2>>"$LOG" || abort "mirror rsync failed"
  mact="$(find "$MT" -type f | wc -l | tr -d ' ')"
  [ "$CNT" = "$mact" ] || abort "mirror count mismatch: $CNT vs $mact"
  python3 - "$MT/_manifest.json" "$SRC" "$REPO" "$BASE_SHA" "$END_SHA" "$CNT" "$DATE" "$GEN" <<'PY'
import json,sys
p,src,repo,b,e,cnt,date,gen=sys.argv[1:9]
json.dump({"schema":"jivo-today/manifest@1","date":date,"generated_at":gen,"mode":"eager",
 "dry_run":False,"total_files":int(cnt),
 "sources":{src:{"repo":repo,"base_commit":b,"end_commit":e,"files":int(cnt),"date":date}}},
 open(p,"w"),indent=2)
PY
  rm -rf "$mirror_repo/today.prev" 2>/dev/null || true
  [ -d "$mirror_repo/today" ] && mv "$mirror_repo/today" "$mirror_repo/today.prev"
  mv "$MT" "$mirror_repo/today" || abort "mirror swap failed"
  log "mirror $mirror_repo/today advanced to $DATE"
else
  log "mirror: deferred (shared ecom repo today/ synced by build_today atomic build)"
fi

# ---- merge data-bank manifest (per-section dates) ---------------------------
python3 - "$DB_TODAY/_manifest.json" "$SRC" "$REPO" "$BASE_SHA" "$END_SHA" "$CNT" "$DATE" "$GEN" <<'PY'
import json,sys,os
p,src,repo,b,e,cnt,date,gen=sys.argv[1:9]
try: m=json.load(open(p))
except Exception: m={}
srcs=m.get("sources",{}) or {}
floor=m.get("date","")  # legacy single-date -> baseline for untouched sections
for k,v in srcs.items():
    if isinstance(v,dict) and not v.get("date"): v["date"]=floor
srcs[src]={"repo":repo,"base_commit":b,"end_commit":e,"files":int(cnt),"date":date}
sd={k:(v.get("date") if isinstance(v,dict) else None) for k,v in srcs.items()}
dates=[d for d in sd.values() if d]
total=sum((v.get("files",0) if isinstance(v,dict) else 0) for v in srcs.values())
out={"schema":"jivo-today/manifest@1",
 "date":max(dates) if dates else date, "min_date":min(dates) if dates else date,
 "mixed_dates": bool(dates and min(dates)!=max(dates)),
 "generated_at":gen,"mode":"eager","dry_run":False,
 "section_dates":sd,"total_files":total,"sources":srcs}
json.dump(out,open(p,"w"),indent=2)
print("manifest: %s -> %s | section_dates=%s"%(src,date,sd))
PY

# ---- commit + push (best-effort; */15 push_all_repos.sh is the backstop) -----
commit_push(){ local repo="$1"; shift
  git -C "$repo" add "$@" 2>>"$LOG" || true
  if git -C "$repo" diff --cached --quiet 2>/dev/null; then log "commit: $repo nothing"; else
    git -C "$repo" commit -q -m "today: eager $SRC -> $DATE ($CNT md)" 2>>"$LOG" && log "commit: $repo OK" || log "commit: $repo failed (non-fatal)"; fi
  git -C "$repo" push >>"$LOG" 2>&1 && log "push: $repo OK" || log "push: $repo deferred to */15 cron"; }
commit_push "$DB_REPO" today
[ -n "$mirror_repo" ] && commit_push "$mirror_repo" today

tg "✅ eager today/ $SRC -> $DATE ($CNT md) — Hermes can pull"
log "=== advance done ($SRC -> $DATE) ==="
exit 0
