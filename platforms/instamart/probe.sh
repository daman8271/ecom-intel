#!/usr/bin/env bash
# Recon: validate a transplanted GUEST Instamart session from this VPS.
# Stages: build cookie jar -> select-location (resolve store) -> search 'jivo'.
# Bounded (<=4 requests). Writes temp artifacts into secrets/ (gitignored).
set -uo pipefail
DIR="/opt/ecom-intel/platforms/instamart"
SRC="$DIR/secrets/swiggy_cookies.json"
JAR="$DIR/secrets/cookiejar.txt"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

# --- build Netscape jar from the cookie export ---
python3 - "$SRC" "$JAR" <<'PY'
import json,sys
cookies=json.load(open(sys.argv[1]))
out=["# Netscape HTTP Cookie File"]
for c in cookies:
    dom=c["domain"]; sub="TRUE" if dom.startswith(".") else "FALSE"
    sec="TRUE" if c.get("secure") else "FALSE"
    exp=str(int(c.get("expirationDate") or 0)); pre="#HttpOnly_" if c.get("httpOnly") else ""
    out.append(f'{pre}{dom}\t{sub}\t{c.get("path","/")}\t{sec}\t{exp}\t{c["name"]}\t{c["value"]}')
open(sys.argv[2],"w").write("\n".join(out)+"\n")
print(f"jar: {len(cookies)} cookies")
PY

MATCHER=$(python3 -c "import random;print(''.join(random.choice('0123456789abcdefg') for _ in range(23)))")
COMMON=(-sS -m 25 --http2 --compressed -A "$UA"
  -H 'accept: */*' -H 'accept-language: en-IN,en;q=0.9'
  -H 'content-type: application/json'
  -H 'origin: https://www.swiggy.com' -H 'referer: https://www.swiggy.com/instamart/'
  -H "matcher: $MATCHER" -H 'x-build-version: 2.341.0'
  -b "$JAR" -c "$JAR")
LAT=12.9719; LNG=77.6412   # Indiranagar, Bengaluru

echo "================ STAGE A: select-location/v2 ================"
ABODY=$(printf '{"data":{"lat":%s,"lng":%s,"address":"","addressId":"","annotation":"","clientId":"INSTAMART-APP"}}' "$LAT" "$LNG")
CODE_A=$(curl "${COMMON[@]}" -D "$DIR/secrets/_a.hdr" -o "$DIR/secrets/_a.json" -w '%{http_code}' \
  -X POST 'https://www.swiggy.com/api/instamart/home/select-location/v2' --data "$ABODY")
echo "HTTP $CODE_A  bytes=$(wc -c < "$DIR/secrets/_a.json")"
echo "--- key response headers ---"
grep -iE '^(HTTP/|server|x-rate-limit|retry-after|x-cache|via|content-type|set-cookie):' "$DIR/secrets/_a.hdr" | sed -E 's/(set-cookie: [a-zA-Z0-9_-]+=)[^;]+/\1<redacted>/I' | head -15
echo "--- body head ---"; head -c 220 "$DIR/secrets/_a.json"; echo
STORE=$(python3 - "$DIR/secrets/_a.json" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(""); sys.exit()
def f(o):
    if isinstance(o,dict):
        for k in ("storeId","primaryStoreId","store_id"):
            if k in o and isinstance(o[k],(str,int)) and str(o[k]).strip() not in ("","0"): return str(o[k])
        for v in o.values():
            r=f(v)
            if r: return r
    elif isinstance(o,list):
        for v in o:
            r=f(v)
            if r: return r
    return ""
print(f(d))
PY
)
echo "resolved storeId=[$STORE]"

echo; echo "================ STAGE B: search 'jivo' ================"
SBODY='{"facets":[],"sortAttribute":"","query":"jivo","search_results_offset":"0","page_type":"INSTAMART_SEARCH_PAGE","is_pre_search_tag":false}'
SURL="https://www.swiggy.com/api/instamart/search/v2?storeId=${STORE}&primaryStoreId=${STORE}&secondaryStoreId=&offset=0&pageType=INSTAMART_SEARCH_PAGE&query=jivo&limit=40"
CODE_B=$(curl "${COMMON[@]}" -o "$DIR/secrets/_b.json" -w '%{http_code}' -X POST "$SURL" --data "$SBODY")
echo "HTTP $CODE_B  bytes=$(wc -c < "$DIR/secrets/_b.json")"
echo "--- body head ---"; head -c 200 "$DIR/secrets/_b.json"; echo
echo "--- parsed products ---"
python3 - "$DIR/secrets/_b.json" <<'PY'
import json,sys
raw=open(sys.argv[1],encoding='utf-8',errors='replace').read()
try: d=json.loads(raw)
except Exception as e:
    print("NOT JSON:",str(e)[:80]); print("head:",raw[:160]); sys.exit()
found=[]
def walk(o):
    if isinstance(o,dict):
        nm=o.get("display_name") or o.get("name")
        pr=o.get("price")
        if nm and isinstance(pr,dict) and any(k in pr for k in ("mrp","offer_price","store_price")):
            found.append((str(nm), pr.get("mrp"), pr.get("offer_price") or pr.get("store_price"), o.get("in_stock", o.get("available"))))
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(d)
print("products-with-price:", len(found))
for nm,mrp,sp,st in found[:10]:
    print(f"  - {nm[:46]:46} MRP={mrp} SP={sp} stock={st}")
PY
echo "================ END ================"