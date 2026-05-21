# Proxy guide — residential Indian exit IPs for ecom-intel

**Why:** the Hostinger VPS has a **datacenter IP** that some Indian e-commerce
sites reject. **Zepto is hard-blocked** (CloudFront 403 before any page loads —
see `platforms/zepto/BLOCKED.md`), and **Amazon** works today but may escalate to
a captcha on the datacenter IP. The fix is to route Playwright through a
**residential (or mobile) proxy with an Indian exit IP**.

The integration is already built and wired (see "How it's wired" below). The
**only thing missing is credentials** — the moment you add `PROXY_*` to
`secrets.env`, Zepto routes through the proxy automatically.

---

## TL;DR recommendation

| Role | Provider | Plan / model | Rough monthly cost (our volume) |
|---|---|---|---|
| **Primary (buy this)** | **IPRoyal Residential** | Pay-as-you-go, per-GB, **no monthly minimum**, traffic never expires | **~$10–25/mo** (buy 5–10 GB up front; it doesn't expire) |
| **Cheaper alternative** | **DataImpulse Residential** | Pay-as-you-go **$1/GB**, $5 min top-up, India ~2.1M IPs | **~$8–10/mo** |
| **Premium fallback** | **Bright Data** (or SOAX for mobile IPs) | Pay-as-you-go ~$4/GB, best success rate / unblock infra | **~$30–40/mo** (only if IPRoyal IPs get flagged) |

**Why IPRoyal as primary:** lowest-friction for our LOW volume — true zero
monthly minimum, **non-expiring credit** (so 3 runs/day of a small site won't
"waste" a subscription), clean `country-in` + sticky-session syntax that drops
straight into Playwright, and a ~3.8M Indian residential IP pool — plenty for
40 pincodes x 3 runs/day. We are nowhere near the scale that justifies an
enterprise contract (Oxylabs/Bright Data minimums and dashboards are overkill).

**Our data volume is tiny** (see sizing below: **~8 GB/month** realistic,
**~28 GB/month** absolute worst case), so **per-GB pay-as-you-go beats every
per-IP / monthly-subscription model.** Do **not** buy a 25+ GB/month plan.

---

## Provider comparison

Prices are entry-level / low-commit tiers as of 2026; verify on each vendor's
site before buying — proxy pricing shifts often.

| Provider | Price model | Entry price (PAYG) | Min spend | Indian IPs | Geo-targeting | Rotation / sticky | Playwright fit | Verdict for us |
|---|---|---|---|---|---|---|---|---|
| **IPRoyal** | per-GB, PAYG | ~$7/GB @1GB, ~$1.75/GB at volume | **none** (1 GB) | ~3.8M | country/state/city | rotating per-request **or** sticky up to **7 days** | creds in user/pass, country+session in password suffix | **Primary — right-sized, non-expiring credit** |
| **DataImpulse** | per-GB, PAYG | **$1/GB** | $5 (5 GB) | ~2.1M | country incl. free | rotating + sticky | `user:pass@gw.dataimpulse.com:823` | **Cheaper alt — cheapest /GB; smaller pool** |
| **Decodo (ex-Smartproxy)** | per-GB, plan | $4/GB PAYG; $3.75/GB @3GB | ~$11.25/mo | large | country/city/ZIP | rotating + sticky (≤30 min) | gateway user/pass | Good, but min-spend; sticky capped at 30 min |
| **SOAX** | per-GB / plan | $4/GB PAYG; $90 @25GB plan | $90/mo plan | ~5M (strong mobile) | country/region/city/ISP | rotating + sticky | gateway user/pass | Best **mobile** India IPs; overkill cost for us |
| **Bright Data** | per-GB, PAYG | ~$4/GB (~$2.94 India) | low (PAYG) | huge | very granular | rotating + sticky | gateway user/pass | **Premium fallback** — best unblocking, pricier UX |
| **Oxylabs** | per-GB / plan | ~$8/GB @10GB | ~$80/plan | huge | granular | rotating + sticky | gateway user/pass | Premium/enterprise — overkill |
| PacketStream | per-GB, PAYG | $1/GB | $10 deposit | smaller | country | rotating | gateway user/pass | Cheap but thinner India pool / reliability |

**Overkill for us:** Oxylabs and SOAX's $80–90 plans, and any per-IP or
25+ GB monthly subscription. **Right-sized:** IPRoyal / DataImpulse PAYG.
**Mobile IPs** (SOAX) are only worth it if residential IPs start getting
flagged on Zepto — not our first move.

---

## Data volume sizing (why PAYG, why small)

Scope to size: **4 platforms × ~40 pincodes × 3 runs/day**, Playwright page
loads with **images/fonts/media blocked** (the scrapers already `route.abort()`
those, so traffic is mostly HTML/JS/XHR ≈ **~2 MB per pincode page-set**).

| Scenario | Daily | Monthly |
|---|---|---|
| **Zepto only** (40 pincodes × 3 runs) | ~240 MB | **~7 GB** |
| Amazon as insurance (national, scraped once/run) | ~18 MB | ~0.5 GB |
| **Realistic (Zepto + Amazon)** | ~260 MB | **~8 GB/mo** |
| Worst case (all 4 platforms looped 40 pincodes via proxy) | ~950 MB | **~28 GB/mo** |

Marketplaces (Amazon, Flipkart) have **national** pricing — scraped **once per
run, not 40×** — so the realistic figure is dominated by Zepto. **Budget
~8–10 GB/month**, buy in small increments. At IPRoyal's rate that's roughly
**$10–25/month**; on DataImpulse's $1/GB it's **~$8–10/month**.

---

## What to buy + which credentials to hand over

### 1. Sign up (IPRoyal — primary pick)
1. Create an account at **iproyal.com**.
2. Buy **Royal Residential Proxies**, **Pay As You Go**. Start with **5–10 GB**
   (it does **not expire** — no pressure to use it on a schedule).
3. In the dashboard, open the residential proxy / "Proxy access" page. Note:
   - **Host:** `geo.iproyal.com`
   - **Port:** `12321`
   - your **username** and **password** (the base credentials).
4. (Optional) whitelist the VPS IP, or just use username/password auth (what we
   use).

### 2. Hand these three values to the system (put them in `secrets.env`)
Copy `secrets.env.example` → `secrets.env` if you haven't, then set:

```
PROXY_URL=http://geo.iproyal.com:12321
PROXY_USERNAME=<your IPRoyal username>
PROXY_PASSWORD=<your IPRoyal password>_country-in_session-a1b2c3d4_lifetime-10m
```

That's the entire handover: **PROXY_URL, PROXY_USERNAME, PROXY_PASSWORD.**
Nothing else changes. Keep `secrets.env` at `chmod 600`; it is gitignored.

> Don't have separate fields handy? You can instead set everything in one URL —
> the system splits the embedded creds out automatically:
> `PROXY_URL=http://USER:PASS_country-in_session-a1b2c3d4_lifetime-10m@geo.iproyal.com:12321`

### 3. Run it
```bash
./run.sh zepto      # log shows: [net] PROXY http://geo.iproyal.com:12321 user=...***
```
If the 403 guard stops firing and `summary.total_rows > 20`, you're unblocked.
If the **proxy IP is also 403'd**, rotate (drop `_session-`/`_lifetime-` to get a
fresh IP per request) or escalate to the premium fallback (Bright Data / SOAX
mobile).

---

## The IPRoyal password syntax (how rotation/geo is controlled)

With IPRoyal, **everything is encoded as `_key-value` suffixes appended to the
password.** The username/host/port never change.

| Suffix | Meaning | Example |
|---|---|---|
| `_country-in` | Indian exit IP (ISO code `in`) | `pass_country-in` |
| `_session-XXXXXXXX` | sticky session id — **8 alphanumeric chars**; same id ⇒ same IP | `pass_country-in_session-a1b2c3d4` |
| `_lifetime-10m` | how long to hold that IP — `s`/`m`/`h`/`d`, **min 1s, max 7d** | `..._lifetime-10m` |
| *(omit session/lifetime)* | **rotating** — fresh IP on every request | `pass_country-in` |

Full sticky example:
`yourpass_country-in_session-a1b2c3d4_lifetime-10m`

---

## How to use rotation vs sticky, per platform

| Platform | Recommended mode | Why |
|---|---|---|
| **Zepto** | **Sticky per pincode**, short lifetime (`_session-<perpin>_lifetime-10m`) | Zepto resolves the dark store from GPS; an IP that flips mid-pincode mid-load looks bot-like. Hold one Indian IP for the home→search page-set of each pincode (~seconds), then a new id for the next pincode spreads load across IPs. Rotating per-request also works but a stable IP per pincode is cleaner. |
| **Amazon (insurance)** | **Rotating** (omit `_session-`) — or sticky for the duration of one run | Amazon scrape is a single national pass per run, not 40 pincodes. A fresh Indian residential IP per run avoids reusing a flagged IP. Use sticky only if Amazon ties the interstitial-bypass cookie to the connecting IP within a run. |
| **Other platforms** (Blinkit/Flipkart/Flipkart-Minutes) | **DIRECT (no proxy)** — leave `PROXY_*` as-is per-platform | They already work from the datacenter IP. Don't burn proxy GB on them. Only Zepto is wired to the proxy today; wire others the same way **only if** they start getting blocked. |

> **How to vary the sticky id per pincode:** if/when we want true per-pincode
> stickiness, the scraper can build the password at runtime by appending
> `_session-<8 chars derived from the pincode>` to `PROXY_PASSWORD`. For the
> first cut, a single shared `_session-...` (or pure rotating) in `secrets.env`
> is enough to get Zepto loading.

---

## How it's wired (engineering reference)

- **`tools/proxy.js`** — `getProxy()` reads `PROXY_URL` / `PROXY_USERNAME` /
  `PROXY_PASSWORD` from `process.env` first, then from `secrets.env` (it parses
  the file itself, because `run.sh` launches `node` **before** it sources
  `secrets.env`). Returns a Playwright `{ server, username, password }` object,
  or **`null` when unset** (⇒ scrapers run **DIRECT**, unchanged). Creds embedded
  in the URL (`http://user:pass@host:port`) are split out automatically; a bare
  `host:port` is normalised to `http://host:port`.
- **`platforms/zepto/scrape.js`** — `const getProxy = require('../../tools/proxy')`,
  then `chromium.launch({ headless: true, ...(proxy ? { proxy } : {}) })`. When
  no proxy is set the spread is a no-op and behaviour is identical to before.
  Logs `[net] DIRECT (no proxy)` or `[net] PROXY ...` (password never printed).
- **Hardening Amazon** is the same two-line change: add the `require` and the
  conditional `proxy` spread to `platforms/amazon/scrape.js`'s `chromium.launch`.
  No other code changes. (Not done yet — Amazon works DIRECT today; do it the
  moment Amazon runs start returning 0 rows / a captcha.)
- **`secrets.env.example`** — copy-paste template with the commented `PROXY_*`
  block. The real `secrets.env` is gitignored and must stay `chmod 600`.

---

## Sources
- IPRoyal residential pricing & PAYG: <https://iproyal.com/pricing/residential-proxies/>
- IPRoyal sticky-session / country syntax: <https://docs.iproyal.com/proxies/residential/proxy/rotation>
- IPRoyal Playwright integration: <https://iproyal.com/integrations/proxy-integration-with-playwright/>
- DataImpulse residential ($1/GB, India): <https://dataimpulse.com/residential-proxies/>
- Decodo (ex-Smartproxy) pricing: <https://decodo.com/proxies/residential-proxies/pricing>
- SOAX India proxies / pricing: <https://soax.com/proxies/locations/india>
- Bright Data vs Oxylabs (premium tier reference): <https://brightdata.com/blog/comparison/bright-data-vs-oxylabs>
