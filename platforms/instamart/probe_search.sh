#!/usr/bin/env bash
# Find the working search/listing endpoint shape, using the bootstrapped jar + real storeId.
set -uo pipefail
DIR="/opt/ecom-intel/platforms/instamart"; JAR="$DIR/secrets/cookiejar.txt"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
MATCHER=$(python3 -c "import random;print(''.join(random.choice('0123456789abcdefg') for _ in range(23)))")
COMMON=(-sS -m 25 --http2 --compressed -A "$UA"
  -H 'accept: */*' -H 'accept-language: en-IN,en;q=0.9' -H 'content-type: application/json'
  -H 'origin: https://www.swiggy.com' -H 'referer: https://www.swiggy.com/instamart/'
  -H "matcher: $MATCHER" -H 'x-build-version: 2.341.0' -b "$JAR" -c "$JAR")
STORE=1190778
SBODY='{"facets":[],"sortAttribute":"","query":"jivo","search_results_offset":"0","page_type":"INSTAMART_SEARCH_PAGE","is_pre_search_tag":false}'

count_products() { python3 - "$1" <<'PY'
import json,sys
raw=open(sys.argv[1],encoding='utf-8',errors='replace').read()
try: d=json.loads(raw)
except Exception as e: print(f"   NOT-JSON ({str(e)[:40]})  head={raw[:90]!r}"); sys.exit()
found=[]
def walk(o):
    if isinstance(o,dict):
        nm=o.get("display_name") or o.get("name"); pr=o.get("price")
        if nm and isinstance(pr,dict) and any(k in pr for k in("mrp","offer_price","store_price")):
            found.append((str(nm),pr.get("mrp"),pr.get("offer_price") or pr.get("store_price")))
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(d)
print(f"   JSON OK  products-with-price={len(found)}")
for nm,mrp,sp in found[:6]: print(f"      - {nm[:44]:44} MRP={mrp} SP={sp}")
PY
}

try() { # label method url [body]
  local label="$1" method="$2" url="$3" body="${4:-}" out="$DIR/secrets/_s.json" hdr="$DIR/secrets/_s.hdr"
  local code
  if [ "$method" = GET ]; then
    code=$(curl "${COMMON[@]}" -D "$hdr" -o "$out" -w '%{http_code}' "$url")
  else
    code=$(curl "${COMMON[@]}" -D "$hdr" -o "$out" -w '%{http_code}' -X POST "$url" --data "$body")
  fi
  local ct; ct=$(grep -i '^content-type:' "$hdr" | head -1 | tr -d '\r')
  echo ">>> $label : HTTP $code  bytes=$(wc -c <"$out")  [$ct]"
  count_products "$out"
  echo
}

echo "############ search/listing endpoint discovery (storeId=$STORE) ############"
try "V1 POST search/v2"       POST "https://www.swiggy.com/api/instamart/search/v2?storeId=$STORE&primaryStoreId=$STORE&secondaryStoreId=&offset=0&query=jivo&clientId=INSTAMART-APP&pageType=INSTAMART_SEARCH_PAGE" "$SBODY"
try "V2 GET  search/v2"       GET  "https://www.swiggy.com/api/instamart/search/v2?query=jivo&pageNumber=0&pageSize=20&storeId=$STORE&primaryStoreId=$STORE&clientId=INSTAMART-APP"
try "V3 POST search (no v2)"  POST "https://www.swiggy.com/api/instamart/search?storeId=$STORE&primaryStoreId=$STORE&query=jivo&clientId=INSTAMART-APP&pageType=INSTAMART_SEARCH_PAGE" "$SBODY"
echo "############ done ############"