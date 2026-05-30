#!/usr/bin/env bash
# RECON #3 — try to reproduce the nowstore search WITHOUT a browser, carrying the
# cookies playwright collected. Reads cookies from a playwright cookies json.
#   ./curltest.sh recon/cookies.now.json 'https://www.amazon.in/s?k=jivo&i=nowstore'
set -u
COOKIE_JSON="${1:-recon/cookies.now.json}"
URL="${2:-https://www.amazon.in/s?k=jivo&i=nowstore}"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

# build a Cookie header from the playwright cookie jar (name=value; ...)
COOKIES=$(node -e '
const c=require(process.argv[1]);
process.stdout.write(c.map(x=>x.name+"="+x.value).join("; "));
' "$COOKIE_JSON")

echo "=== GET $URL ===" >&2
OUT=$(mktemp)
HTTP=$(curl -s -o "$OUT" -w '%{http_code}' \
  -H "User-Agent: $UA" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Language: en-IN,en;q=0.9' \
  -H "Cookie: $COOKIES" \
  --compressed \
  "$URL")
echo "HTTP $HTTP  bytes=$(wc -c < "$OUT")" >&2
echo "--- markers ---" >&2
grep -o 'data-asin="[A-Z0-9]\{10\}"' "$OUT" | sort -u | head -20
echo "--- captcha/robot? ---" >&2
grep -o -i 'validateCaptcha\|api-services-support\|robot check\|Enter the characters' "$OUT" | sort -u | head
echo "--- price hits (a-offscreen) ---" >&2
grep -o '<span class="a-offscreen">[^<]*</span>' "$OUT" | head -10
echo "--- jivo title hits ---" >&2
grep -o -i 'jivo[^<"]\{0,40\}' "$OUT" | sort -u | head -10
echo "(full html saved to $OUT)" >&2
echo "$OUT"
