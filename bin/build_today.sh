#!/usr/bin/env bash
# =============================================================================
# build_today.sh — daily verbatim `today/` MD snapshot for the JIVO vaults.
#
# Captures, byte-for-byte, every *.md note that a given IST day's crons changed,
# across 4 logical sources (3 source repos) and assembles them into a full-
# REPLACE `today/` folder in each source repo plus a 4-way combined split in the
# data-bank. Zero data loss, no merging, no summarization.
#
#   Sources (logical)        Repo                       Vault scope
#   ----------------------   ------------------------   --------------------------------
#   price-scraper            /opt/ecom-intel            vault/  EXCEPT vault/competitor/
#   competitors              /opt/ecom-intel            vault/competitor/
#   factory                  /root/jivo-factory-intel   vault/
#   ecom-app                 /root/jivo-intel           vault/
#
#   Output layout (vault-relative paths, leading `vault/` stripped):
#     /opt/ecom-intel/today/          ps + competitor own slice
#     /root/jivo-factory-intel/today/ factory own slice
#     /root/jivo-intel/today/         ecom-app own slice
#     /root/jivo-data-bank/today/{price-scraper,competitors,factory,ecom-app}/
#
# Flags (compose freely):
#   --date <YYYY-MM-DD>  treat this IST date as "today" (default = IST today).
#   --dry-run            stage into today.tmp/ + verify; NO swap, commit, push.
#   --dest <root>        write each repo's today/ under <root>/<repo-basename>/
#                        instead of the real repo (isolated testing). Source
#                        vaults are always read from the real repos.
#   --help
#
# Fail-closed: builds only if ALL 4 sources are ready for the date; on ANY
# sha256 or count mismatch it aborts, removes today.tmp/, keeps the prior good
# today/, and alerts. Atomic swap via today.prev rotation. Single-flight (flock).
# Pushes ride the */15 push_all_repos.sh cron; a direct cron push is best-effort.
# =============================================================================
set -uo pipefail
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C

# ---- constants --------------------------------------------------------------
SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SELFDIR/build_today.log"
LOCK="$SELFDIR/build_today.lock"
EMPTY_TREE="$(git hash-object -t tree /dev/null 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"

ECOM_REPO="/opt/ecom-intel"
FACTORY_REPO="/root/jivo-factory-intel"
APP_REPO="/root/jivo-intel"
DB_REPO="/root/jivo-data-bank"

SOURCES=(price-scraper competitors factory ecom-app)

# Telegram (best-effort, real-mode only)
SECRETS="/opt/ecom-intel/secrets.env"
TG_HELPER="/root/telegram_helper.py"

# ---- flags ------------------------------------------------------------------
DATE=""
DRYRUN=0
DEST_ROOT=""
usage(){ sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --date)    DATE="${2:-}"; shift 2 ;;
    --date=*)  DATE="${1#*=}"; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    --dest)    DEST_ROOT="${2:-}"; shift 2 ;;
    --dest=*)  DEST_ROOT="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "build_today.sh: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

TODAY="$(TZ=Asia/Kolkata date +%F)"
DATE="${DATE:-$TODAY}"
if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "build_today.sh: bad --date '$DATE' (want YYYY-MM-DD)" >&2; exit 2
fi
IS_TODAY=0; [ "$DATE" = "$TODAY" ] && IS_TODAY=1
MODE="backfill"; [ "$IS_TODAY" = "1" ] && MODE="live"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build_today.XXXXXX")"
cleanup(){ rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

# ---- logging / alerts -------------------------------------------------------
log(){ printf '[%s] %s\n' "$(TZ=Asia/Kolkata date '+%F %T %Z')" "$*" | tee -a "$LOG" >&2; }

tg(){ # best-effort telegram custom message (real-mode only); never fails
  [ "$DRYRUN" = "1" ] && return 0
  [ -n "$DEST_ROOT" ] && return 0
  [ -f "$SECRETS" ] && [ -f "$TG_HELPER" ] || return 0
  ( set -a; . "$SECRETS" 2>/dev/null || true; set +a
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || exit 0
    python3 "$TG_HELPER" send "$1" >/dev/null 2>&1 || true ) || true
}

abort(){ # message — fail-closed: leave prior today/ untouched, drop all today.tmp
  log "ABORT: $*"
  for base in "$ECOM_BASE" "$FACTORY_BASE" "$APP_BASE" "$DB_BASE"; do
    [ -n "${base:-}" ] && rm -rf "$base/today.tmp" 2>/dev/null || true
  done
  tg "🛑 build_today FAILED for ${DATE}: $*"
  exit 1
}

# ---- single-flight ----------------------------------------------------------
exec 9>"$LOCK" || { echo "cannot open lock $LOCK" >&2; exit 1; }
if ! flock -n 9; then log "another build_today holds the lock — exiting"; exit 0; fi

log "=== build_today start (date=$DATE mode=$MODE dry_run=$DRYRUN dest='${DEST_ROOT:-<real>}') ==="

# ---- repo helpers -----------------------------------------------------------
repo_of(){ case "$1" in
    price-scraper|competitors) echo "$ECOM_REPO" ;;
    factory)  echo "$FACTORY_REPO" ;;
    ecom-app) echo "$APP_REPO" ;;
esac; }

db_slice_of(){ echo "$1"; }  # data-bank subdir == source name

# Output base dir for a real repo path (honours --dest).
base_for(){ local repo="$1"
  if [ -n "$DEST_ROOT" ]; then echo "$DEST_ROOT/$(basename "$repo")"; else echo "$repo"; fi
}

ECOM_BASE="$(base_for "$ECOM_REPO")"
FACTORY_BASE="$(base_for "$FACTORY_REPO")"
APP_BASE="$(base_for "$APP_REPO")"
DB_BASE="$(base_for "$DB_REPO")"

# ---- diff window per repo ([date 00:00, date+1 00:00) IST) ------------------
declare -A WIN_BASE WIN_END BASE_SHA END_SHA
resolve_window(){ local repo="$1" base end next
  base="$(TZ=Asia/Kolkata git -C "$repo" rev-list -1 --before="$DATE 00:00:00" HEAD 2>/dev/null)"
  [ -n "$base" ] || base="$EMPTY_TREE"
  if [ "$IS_TODAY" = "1" ]; then
    end="HEAD"
  else
    next="$(TZ=Asia/Kolkata date -d "$DATE +1 day" +%F)"
    end="$(TZ=Asia/Kolkata git -C "$repo" rev-list -1 --before="$next 00:00:00" HEAD 2>/dev/null)"
    [ -n "$end" ] || end="HEAD"
  fi
  WIN_BASE["$repo"]="$base"; WIN_END["$repo"]="$end"
  BASE_SHA["$repo"]="$(git -C "$repo" rev-parse "$base" 2>/dev/null || echo "$base")"
  END_SHA["$repo"]="$(git -C "$repo" rev-parse "$end" 2>/dev/null || echo "$end")"
}
for repo in "$ECOM_REPO" "$FACTORY_REPO" "$APP_REPO"; do resolve_window "$repo"; done

# ---- working-tree porcelain (live-today only) -------------------------------
porcelain_paths(){ local repo="$1"; shift   # remaining args = pathspec
  git -C "$repo" status --porcelain -z -- "$@" 2>/dev/null | (
    while IFS= read -r -d '' entry; do
      [ -n "$entry" ] || continue
      local xy="${entry:0:2}" path="${entry:3}"
      case "$xy" in *R*|*C*) IFS= read -r -d '' _old 2>/dev/null || true ;; esac
      printf '%s\n' "$path"
    done
  )
}

# ---- changed *.md set for one source (repo-relative paths) ------------------
emit_changed(){ local src="$1" repo base end
  repo="$(repo_of "$src")"; base="${WIN_BASE[$repo]}"; end="${WIN_END[$repo]}"
  case "$src" in
    price-scraper) git -C "$repo" diff --name-only --diff-filter=AMR "$base" "$end" -- 'vault/' ':(exclude)vault/competitor/**' 2>/dev/null ;;
    competitors)   git -C "$repo" diff --name-only --diff-filter=AMR "$base" "$end" -- vault/competitor 2>/dev/null ;;
    factory|ecom-app) git -C "$repo" diff --name-only --diff-filter=AMR "$base" "$end" -- vault 2>/dev/null ;;
  esac
  if [ "$IS_TODAY" = "1" ]; then
    case "$src" in
      price-scraper) porcelain_paths "$repo" 'vault/' ':(exclude)vault/competitor/**' ;;
      competitors)   porcelain_paths "$repo" vault/competitor ;;
      factory|ecom-app) porcelain_paths "$repo" vault ;;
    esac
  fi
  # competitor date-stamped filename safety-net (recovers the post-midnight
  # commit-window miss; filtered to on-disk existence below)
  if [ "$src" = "competitors" ]; then
    printf '%s\n' "vault/competitor/daily/Competitor-$DATE.md" "vault/competitor/Competitor-Watch.md"
  fi
}

# ---- ready-gate -------------------------------------------------------------
src_ready(){ local src="$1" repo c
  case "$src" in
    price-scraper) [ -f "$ECOM_REPO/vault/daily/$DATE.md" ] ;;
    competitors)   [ -f "$ECOM_REPO/vault/competitor/daily/Competitor-$DATE.md" ] ;;
    ecom-app)      git -C "$APP_REPO" log --grep="^daily ${DATE}\$" -1 --format=%H 2>/dev/null | grep -q . ;;
    factory)
      # primary: render-proof.json mtime == DATE (live, lag-free)
      if [ "$(TZ=Asia/Kolkata date -r "$FACTORY_REPO/render-proof.json" +%F 2>/dev/null)" = "$DATE" ]; then return 0; fi
      # backfill-safe fallback: a vault-touching commit within the IST day
      c="$(TZ=Asia/Kolkata git -C "$FACTORY_REPO" rev-list -1 --since="$DATE 00:00:00" --before="$DATE 23:59:59" HEAD -- vault 2>/dev/null)"
      [ -n "$c" ] ;;
  esac
}

MISSING=()
for src in "${SOURCES[@]}"; do
  if src_ready "$src"; then log "ready-gate: $src OK"; else log "ready-gate: $src NOT READY"; MISSING+=("$src"); fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  log "ready-gate: holding off — missing: ${MISSING[*]} (poller will retry). Leaving existing today/ untouched."
  exit 0
fi

# ---- compute changed sets (existence-filtered) ------------------------------
declare -A CNT
for src in "${SOURCES[@]}"; do
  repo="$(repo_of "$src")"
  emit_changed "$src" | grep -E '\.md$' | sort -u | while IFS= read -r f; do
    [ -f "$repo/$f" ] && printf '%s\n' "$f"
  done > "$WORK/$src.reporel"
  # vault-relative (strip leading vault/)
  sed 's#^vault/##' "$WORK/$src.reporel" > "$WORK/$src.vaultrel"
  CNT["$src"]="$(wc -l < "$WORK/$src.reporel" | tr -d ' ')"
  log "changed: $src = ${CNT[$src]} md files"
  if [ "${CNT[$src]}" -eq 0 ]; then abort "source '$src' produced 0 changed md (unexpected) — refusing to build"; fi
done

# ---- prepare staging dirs ---------------------------------------------------
for base in "$ECOM_BASE" "$FACTORY_BASE" "$APP_BASE" "$DB_BASE"; do
  rm -rf "$base/today.tmp" 2>/dev/null || true
  mkdir -p "$base/today.tmp" || abort "mkdir today.tmp failed under $base"
done

# rsync verbatim (-a == cp -p superset). files-from is vault-relative; SRCROOT
# is the real repo vault so the leading vault/ is stripped in the output.
stage(){ local srcroot="$1" filesfrom="$2" destdir="$3"
  [ -s "$filesfrom" ] || { mkdir -p "$destdir"; return 0; }
  mkdir -p "$destdir"
  rsync -a --files-from="$filesfrom" "$srcroot/" "$destdir/" 2>>"$LOG" \
    || abort "rsync failed: $srcroot -> $destdir"
}

# accumulate parallel src/dst absolute-path lists for the sha256 verify
add_pairs(){ local srcroot="$1" vaultrel="$2" dstbase="$3" outsrc="$4" outdst="$5"
  while IFS= read -r r; do
    printf '%s\n' "$srcroot/$r" >> "$outsrc"
    printf '%s\n' "$dstbase/$r" >> "$outdst"
  done < "$vaultrel"
}

ECOM_VAULT="$ECOM_REPO/vault"
FAC_VAULT="$FACTORY_REPO/vault"
APP_VAULT="$APP_REPO/vault"

# --- own slices ---
# ecom own = price-scraper + competitors (path-disjoint; competitor lives under competitor/)
cat "$WORK/price-scraper.vaultrel" "$WORK/competitors.vaultrel" > "$WORK/ecom_own.vaultrel"
stage "$ECOM_VAULT" "$WORK/ecom_own.vaultrel" "$ECOM_BASE/today.tmp"
: > "$WORK/ecom.src"; : > "$WORK/ecom.dst"
add_pairs "$ECOM_VAULT" "$WORK/price-scraper.vaultrel" "$ECOM_BASE/today.tmp" "$WORK/ecom.src" "$WORK/ecom.dst"
add_pairs "$ECOM_VAULT" "$WORK/competitors.vaultrel"   "$ECOM_BASE/today.tmp" "$WORK/ecom.src" "$WORK/ecom.dst"

stage "$FAC_VAULT" "$WORK/factory.vaultrel" "$FACTORY_BASE/today.tmp"
: > "$WORK/factory.src"; : > "$WORK/factory.dst"
add_pairs "$FAC_VAULT" "$WORK/factory.vaultrel" "$FACTORY_BASE/today.tmp" "$WORK/factory.src" "$WORK/factory.dst"

stage "$APP_VAULT" "$WORK/ecom-app.vaultrel" "$APP_BASE/today.tmp"
: > "$WORK/app.src"; : > "$WORK/app.dst"
add_pairs "$APP_VAULT" "$WORK/ecom-app.vaultrel" "$APP_BASE/today.tmp" "$WORK/app.src" "$WORK/app.dst"

# --- data-bank 4-way combined split ---
: > "$WORK/db.src"; : > "$WORK/db.dst"
stage "$ECOM_VAULT" "$WORK/price-scraper.vaultrel" "$DB_BASE/today.tmp/price-scraper"
add_pairs "$ECOM_VAULT" "$WORK/price-scraper.vaultrel" "$DB_BASE/today.tmp/price-scraper" "$WORK/db.src" "$WORK/db.dst"
stage "$ECOM_VAULT" "$WORK/competitors.vaultrel" "$DB_BASE/today.tmp/competitors"
add_pairs "$ECOM_VAULT" "$WORK/competitors.vaultrel" "$DB_BASE/today.tmp/competitors" "$WORK/db.src" "$WORK/db.dst"
stage "$FAC_VAULT" "$WORK/factory.vaultrel" "$DB_BASE/today.tmp/factory"
add_pairs "$FAC_VAULT" "$WORK/factory.vaultrel" "$DB_BASE/today.tmp/factory" "$WORK/db.src" "$WORK/db.dst"
stage "$APP_VAULT" "$WORK/ecom-app.vaultrel" "$DB_BASE/today.tmp/ecom-app"
add_pairs "$APP_VAULT" "$WORK/ecom-app.vaultrel" "$DB_BASE/today.tmp/ecom-app" "$WORK/db.src" "$WORK/db.dst"

# ---- zero-loss verify (count + sha256 parallel sequences) -------------------
verify_tree(){ local label="$1" tmpdir="$2" srclist="$3" dstlist="$4" exp act sh1 sh2
  exp="$(wc -l < "$srclist" | tr -d ' ')"
  act="$(find "$tmpdir" -type f ! -name '_manifest.json' | wc -l | tr -d ' ')"
  if [ "$exp" != "$act" ]; then abort "$label count mismatch: expected $exp, dest has $act"; fi
  sh1="$(xargs -r -a "$srclist" -d '\n' sha256sum | awk '{print $1}')"
  sh2="$(xargs -r -a "$dstlist" -d '\n' sha256sum | awk '{print $1}')"
  if [ "$sh1" != "$sh2" ]; then abort "$label sha256 mismatch (byte divergence between source and staged copy)"; fi
  log "verify: $label OK ($exp files, sha256 byte-identical)"
}
verify_tree "ecom/today"    "$ECOM_BASE/today.tmp"    "$WORK/ecom.src"    "$WORK/ecom.dst"
verify_tree "factory/today" "$FACTORY_BASE/today.tmp" "$WORK/factory.src" "$WORK/factory.dst"
verify_tree "app/today"     "$APP_BASE/today.tmp"     "$WORK/app.src"     "$WORK/app.dst"
verify_tree "data-bank/today" "$DB_BASE/today.tmp"    "$WORK/db.src"      "$WORK/db.dst"

# ---- manifests (provenance only) --------------------------------------------
GEN="$(TZ=Asia/Kolkata date '+%F %T %Z')"
DRYJSON=false; [ "$DRYRUN" = "1" ] && DRYJSON=true

src_obj(){ local s="$1" repo; repo="$(repo_of "$s")"
  jq -n --arg name "$s" --arg repo "$repo" \
        --arg base "${BASE_SHA[$repo]}" --arg end "${END_SHA[$repo]}" \
        --argjson files "${CNT[$s]}" \
        '{($name): {repo:$repo, base_commit:$base, end_commit:$end, files:$files}}'
}
write_manifest(){ local tmpdir="$1" total="$2"; shift 2  # remaining = source names
  local combined; combined="$( for s in "$@"; do src_obj "$s"; done | jq -s 'add' )"
  jq -n --arg date "$DATE" --arg gen "$GEN" --arg mode "$MODE" \
        --argjson dry "$DRYJSON" --argjson total "$total" --argjson sources "$combined" \
        '{schema:"jivo-today/manifest@1", date:$date, generated_at:$gen, mode:$mode,
          dry_run:$dry, total_files:$total, sources:$sources}' > "$tmpdir/_manifest.json"
}
ECOM_TOTAL=$(( ${CNT[price-scraper]} + ${CNT[competitors]} ))
DB_TOTAL=$(( ${CNT[price-scraper]} + ${CNT[competitors]} + ${CNT[factory]} + ${CNT[ecom-app]} ))
write_manifest "$ECOM_BASE/today.tmp"    "$ECOM_TOTAL"        price-scraper competitors
write_manifest "$FACTORY_BASE/today.tmp" "${CNT[factory]}"    factory
write_manifest "$APP_BASE/today.tmp"     "${CNT[ecom-app]}"   ecom-app
write_manifest "$DB_BASE/today.tmp"      "$DB_TOTAL"          price-scraper competitors factory ecom-app

log "staged+verified: ecom=$ECOM_TOTAL factory=${CNT[factory]} app=${CNT[ecom-app]} data-bank=$DB_TOTAL"

# ---- dry-run stops here -----------------------------------------------------
if [ "$DRYRUN" = "1" ]; then
  log "--dry-run: staging verified; NO swap/commit/push. today.tmp/ left in place for inspection."
  log "=== build_today done (dry-run) ==="
  exit 0
fi

# ---- atomic swap ------------------------------------------------------------
swap(){ local base="$1"
  rm -rf "$base/today.prev" 2>/dev/null || true
  [ -d "$base/today" ] && mv "$base/today" "$base/today.prev" 2>/dev/null || true
  mv "$base/today.tmp" "$base/today" || abort "atomic swap failed under $base"
}
swap "$ECOM_BASE"; swap "$FACTORY_BASE"; swap "$APP_BASE"; swap "$DB_BASE"
log "atomic swap complete in all 4 today/ roots"

# ---- commit (real repos only; --dest writes to non-repos, skip git) ---------
if [ -z "$DEST_ROOT" ]; then
  ensure_gitignore(){ local repo="$1" e
    for e in 'today.tmp/' 'today.prev/'; do
      grep -qxF "$e" "$repo/.gitignore" 2>/dev/null || printf '%s\n' "$e" >> "$repo/.gitignore"
    done
  }
  MSG="today: $DATE snapshot (${DB_TOTAL} files: ps=${CNT[price-scraper]}/comp=${CNT[competitors]}/factory=${CNT[factory]}/app=${CNT[ecom-app]})"
  for repo in "$ECOM_REPO" "$FACTORY_REPO" "$APP_REPO" "$DB_REPO"; do
    ensure_gitignore "$repo"
    git -C "$repo" add .gitignore today 2>>"$LOG" || true
    if git -C "$repo" diff --cached --quiet 2>/dev/null; then
      log "commit: $repo nothing to commit (today/ unchanged)"
    else
      git -C "$repo" commit -q -m "$MSG" 2>>"$LOG" && log "commit: $repo OK" || log "commit: $repo failed (non-fatal)"
    fi
    # Best-effort cron push; the */15 push_all_repos.sh cron is the guaranteed backstop.
    git -C "$repo" push >>"$LOG" 2>&1 && log "push: $repo OK" || log "push: $repo deferred to */15 cron"
  done
fi

tg "✅ build_today OK ${DATE} (${MODE}) — ${DB_TOTAL} md: ps=${CNT[price-scraper]} comp=${CNT[competitors]} factory=${CNT[factory]} app=${CNT[ecom-app]}"
log "=== build_today done (committed) ==="
exit 0
