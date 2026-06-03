> ## STATUS 2026-06-03 — REBUILT onto the genuine Now surface; cron still PAUSED
> The live scraper is now **`scrape.ctnow.js`** (the real Amazon Now storefront,
> `/s?k=jivo&almBrandId=ctnow`), wired into `run.sh` for `amazon-now`. The old
> `i=nowstore` `scrape.js` is FROZEN (it was the legacy Prime-Now/marketplace SEARCH —
> 0 real minute-ETAs, ~8% catalog, marketplace prices mislabelled "Now"; see
> `ROOTCAUSE-AmazonNow-2026-06-01.md`). Validated live 2026-06-03 (session "Hello,
> Kanhaiya" OK) with a 65-pincode representative run: 42/65 serviceable, 1152 rows,
> 69 SKUs, speed tiers {10 min:99, overnight:725, tomorrow:328}, **0 GLOW mismatches,
> every row badge-gated** (no marketplace leakage), Groundnut 1L recovered, olive-oil
> prices stable. The contaminated 06-01/05-31 `result.json`+xlsx are renamed `.CONTAMINATED`.
>
> **ACCOUNT ARCHITECTURE (NEW):** amazon-now now has its **OWN dedicated account**, distinct
> from amazon-fresh (proven by comparing storageState identity cookies — Now `ubid-acbin
> 520-2840772-…`, Fresh `259-8681039-…`; the previous shared account is preserved as
> `secrets/amazon-now.storageState.OLDACCT.bak.json`, which is byte-identical to Fresh's).
> Because Amazon's delivery location is account-global, two distinct accounts no longer
> collide and the two scrapers *could* run in parallel. **The shared `.amazon-account.lock`
> is KEPT** until a supervised concurrent run empirically proves non-interference.
>
> **REMAINING before un-pausing cron:** (1) one full 332-pincode run (the 06-03 run was a
> 65-pincode representative sample, kept short because Fresh was scraping in parallel under
> the same lock); (2) restore the 3×/day `run_all.sh` cron lines from
> `.crontab.backup-2026-06-03-paused`; (3) optional: the supervised concurrency test to
> drop the lock. The captcha/login notes below remain valid for refreshing either session.

# Amazon.in Now/Fresh login — CVF / AAMation captcha execution plan

> Goal: mint a reusable `storageState` cookie jar for the throwaway account (phone **8899011758**)
> from a **Hostinger datacenter IP**, **headless**, **no residential proxy**. That session later switches
> saved delivery addresses to scrape Amazon Now/Fresh price+stock across ~332 pincodes for 314 Jivo ASINs.
>
> The blocker: after phone-submit, Amazon serves `/ap/cvf/request` with an **AWS WAF "AAMation"
> adversarial grid captcha** (`WAF_ADVERSARIAL_SYNTHETIC_GRID_V2_LEVEL_3` — the deliberately hard tier)
> that gates the OTP send. This is NOT Arkose/FunCaptcha and NOT the old text captcha — it is the
> standard AWS WAF CAPTCHA widget (`captcha.awswaf.com`) wrapped inside Amazon's CVF.

---

## What we actually learned (the load-bearing facts)

1. **Two grading layers.** Tile clicks are pure in-widget JS state. On **Confirm**, the AWS WAF widget
   grades the selection over its own XHR and, on success, mints a **voucher** (the AWS WAF token). Only
   then does ACIC stuff that voucher into `#cvf_aamation_response_token` and POST the wrapper form to
   `/ap/cvf/verify`, which releases the OTP. **You cannot forge the answer** by writing a hidden field —
   the voucher is minted server-side by AWS WAF, so the grid must be solved with real in-DOM clicks.

2. **Tiles are canvas-only.** The 9 photos are painted on a single `<canvas width=324 height=324>`; there
   is no `<img>` URL or base64 to scrape. To "see" the tiles you must **screenshot the canvas/modal**.
   Nine transparent `<button>1..9</button>` overlays sit on the canvas (row-major: TL=index 0 … BR=index 8).

3. **"Solved: N Required: 3" counts GRIDS, not tiles.** Each grid asks for one object; a correct Confirm
   increments Solved by 1 and serves the next grid. So normally **3 consecutive grids** must be solved.

4. **Why it fires here.** AWS WAF runs silent fingerprint checks (Canvas/WebGL/AudioContext/Navigator/
   screen) + IP reputation + TLS + cookie/timing continuity. On a low-rep datacenter IP the baseline score
   is poor; the **phone-submit POST** is a sensitive action that lowers the trigger threshold, and a **cold
   context** (no `aws-waf-token`, old-headless flat canvas, Mac-UA-on-Linux) tips it over. The regular
   `/dp` scraper works from this same IP because plain product GETs aren't on this WAF+auth-risk path —
   which also means **guest browsing is low-risk and is the safe way to bank trust cookies**.

---

## PRIMARY STRATEGY (and why)

**Make the challenge RARE via fingerprint + warm-up hardening, and SOLVE it via a vision handoff the few
times it still fires.** Implemented in `login_v2.js`. Concretely, before any phone-submit:

1. **Real-Chrome new-headless rendering** (`channel:'chrome'`, `--headless=new`) when a Chrome binary is
   present, else `--headless=new` on bundled chromium with ANGLE/SwiftShader as a weaker fallback. This is
   the single highest-leverage change: old Playwright headless produces a **flat, identical Canvas/WebGL
   hash** on every box — a documented instant red flag. (If you want the strongest signal, run headed under
   Xvfb: `xvfb-run -a --server-args='-screen 0 1366x900x24' node login_v2.js` with `HEADED=1`.)
2. **Coherent Linux identity.** Default UA is now a current **Linux** Chrome UA matching the box (kills the
   Mac-UA-on-Linux tell). `navigator.platform = 'Linux x86_64'`. We do **NOT** spoof WebGL vendor and do
   **NOT** add canvas noise (random noise is itself a negative signal — stable real fingerprint is the goal).
   Locale `en-IN`, timezone `Asia/Kolkata` (already correct).
3. **Session warm-up + aged guest state.** Reuse a persisted guest `storageState` from
   `secrets/guest.storageState.json` if present (run the bundled `--warmup` mode on a cron a few times across
   a day to age `session-id`/`ubid-acbin`/`aws-waf-token`). Then load the homepage, do human-paced
   scroll/hover, optionally open a `/dp` page, and reach signin by **clicking the real nav link**
   (`#nav-link-accountList`) — not a cold hand-built OpenID URL — carrying the `aws-waf-token` into the
   phone-submit. Type the phone with **per-keystroke delays**, with real mouse moves before clicks.
4. **If AAMation still appears → vision handoff loop** (Agent D protocol): screenshot the modal + grid,
   write meta + `AWAIT_VISION:<round>` to `/tmp/aamation_state`, poll `/tmp/aamation_click` for tile
   indices from the vision-capable orchestration loop, click the overlay buttons, Confirm, handle up to
   **4 rounds**, detect solve, then fall through to the existing OTP watch-file flow.

**Why this and not "just solve every captcha":** the captcha is `LEVEL_3` adversarial from a flagged DC IP,
so even a *correct* solve can be rejected by WAF risk scoring. Lowering the trigger rate is therefore the
real lever; the solver is the safety net. Login happens **once** to mint a reusable storageState, so an
occasional human-in-the-loop solve is acceptable.

**Why not buy a proxy:** hard constraint — no residential proxy. All tactics here are free (apt packages +
client-side changes) and stack.

---

## RANKED FALLBACKS

1. **Email + password on the web flow (no phone).** If the account has a password, enter the **email** (not
   the phone) in `#ap_email`, Continue, fill `#ap_password`, submit. This avoids the SMS-OTP send that the
   CVF was gating. Set `MODE=password EMAIL=… PASSWORD=…`. (May still hit AAMation since it's still the
   `inflex` web flow from a DC IP — pair with warm-up.) **Blocked on: does the account have a password?**
2. **Device/App OAuth path (audible-cli technique).** Build the device-OAuth signin URL
   (`openid.oa2.response_type=code`, `client_id=device:<serial>`, `scope=device_auth_access`,
   `pageId=amzn_audible_ios`, `assoc_handle=amzn_audible_ios_in`, PKCE) and **pre-seed `frc` + `map-md`
   cookies** before loading it; then email+password. The audible library reports this "prevents CAPTCHAs in
   most cases." Strongest alternative, but **also requires a password** and is more plumbing. Worth building
   as `login_v3.js` if route 1 still gets walled.
3. **Audio captcha fallback.** The widget ships the WCAG audio fallback (`#amzn-btn-audio-internal` /
   `.amzn-captcha-audio-play-btn`). One short transcription (local Whisper, or one paid WAF-aware solver
   call) is easier to automate than clicking 3 correct grids. Use only if vision-handoff proves unreliable;
   noisy WAF audio is not guaranteed (medium).
4. **Pre-aged guest storageState gardener** (already wired as `--warmup`): a tiny cron opens amazon.in as
   guest a few times across a day to age the `aws-waf-token` before the real login. Multiplier, not a
   standalone fix; the token TTL is hours, so warm shortly before the attempt.
5. **WhatsApp / voice OTP delivery.** Only changes *how* the code arrives **after** the puzzle; does NOT
   avoid AAMation. Keep as a delivery fallback if SMS to the dummy number is flaky.
6. **(Avoid) checkout/cart-confirm signin, exotic `assoc_handle`, mobile-UA.** Evidence is negative or
   neutral — cart-confirm is *more* captcha-prone; mobile UA on desktop GPU adds fingerprint tells; exotic
   handles look anomalous. Listed for completeness; do not pursue.

---

## EXACTLY WHAT WE NEED FROM THE USER

For the live run, please answer / do the following:

- **[BLOCKING] Does the account 8899011758 have a PASSWORD?** (yes/no). If yes, this unlocks fallbacks 1 & 2
  (the email+password paths that *avoid* the SMS-OTP gate entirely). If no, we're on the phone-OTP +
  captcha path and you'll need to relay the OTP.
- **[BLOCKING if password=yes] Is there an EMAIL on the account, and what is it?** (+ the password). Needed
  for fallbacks 1 & 2.
- **Be available to paste the OTP in chat during the live run.** When the script reaches `WAITING_FOR_OTP`,
  I will ask you for the 6-digit code; I'll write it to `/tmp/amazon_otp_input` for the script.
- **Be available to read captcha images during the live run.** If AAMation fires, the script writes a PNG
  per round and I (the vision-capable loop) read it and pick the tiles automatically — **you don't click
  anything**, but the session must be attended so I can drive it round-by-round.
- **Approve installing Chrome / Xvfb on the VPS** (one-time, free): `apt-get install -y google-chrome-stable`
  (best rendering) and optionally `xvfb` (for the headed-under-Xvfb mode). The script runs without them but
  the fingerprint is weaker.
- **Confirm the WhatsApp/voice fallback option:** is WhatsApp installed on the SIM for 8899011758, or can
  you answer a voice call there? (only needed if SMS is unreliable).

---

## ACCOUNT-SAFETY LIMITS (hard caps, enforced in code)

- **Max 1 phone-submit per process invocation.** The script NEVER loops back to re-enter/re-submit the
  phone to "retry" the captcha. A retry = a fresh, human-spaced process run.
- **Max 4 captcha rounds** (`MAX_ROUNDS=4`; Required is 3, +1 spare for a re-serve). Exceeding → bail.
- **Bail (no retry, close browser, exit non-zero)** on: max rounds, vision timeout (5 min/round), DOM
  changed (buttons≠9 / canvas missing), loop sent BAIL, or the **same grid re-served >2× consecutively**
  (vision can't solve it). Bailing here costs **zero OTP rate limit** because it's before any OTP is sent.
- **Cap total daily login attempts at ~2–3**, spaced by hours. Do warm-up/trigger experiments against
  guest/homepage loads, never against repeated phone-submits.
- **Never replay the saved tokens** (`anti-csrftoken-a2z`, `verifyToken`, `external-id`,
  `wafInputProperties.id`) from the dbg artifacts — they're stale/single-session and rotate every render.

---

## HONEST RISK ASSESSMENT

- **No tactic guarantees the challenge disappears.** AWS WAF weights datacenter-IP reputation heavily and
  the no-proxy constraint caps how far client-side fixes can go. Realistic outcome: warm-up + fingerprint
  hardening makes the puzzle *less frequent*; the vision handoff solves it when it fires.
- **A correct solve may still be rejected** (LEVEL_3 adversarial + flagged IP → WAF can re-serve or
  hard-fail regardless). If we get stuck re-serving the same grid, we bail rather than burn the account.
- **Vision accuracy on adversarial synthetic tiles is imperfect.** The images are deliberately distorted;
  3 grids in a row must all be right. Expect some sessions to bail and require a fresh attempt.
- **The password fallbacks are the most promising "skip the captcha" routes**, but they hinge on the open
  question of whether the throwaway account even has a password/email. A quick phone-OTP signup often has
  neither — in which case we're committed to the phone-OTP + captcha path.
- **Worst case (all routes wall):** the only remaining levers are a residential proxy (excluded by
  constraint) or a one-off manual login on a trusted machine to export the cookie jar, then transplant it to
  the VPS. The cookie jar from a trusted-IP login may still work for the address-switch scraping if Amazon
  doesn't hard-bind the session to the login IP — untested, but a cheap last resort to suggest to the user.
- **Account-flag risk is low** as long as the hard caps above are honored (one phone-submit/run, no OTP
  burning, bail-not-retry). The biggest real risk is wasted attempts, not a ban.
