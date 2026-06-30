'use strict';
// Adaptive politeness for the Instamart scraper.
// Derived from Scrapy's AutoThrottle algorithm + RetryMiddleware, reimplemented
// standalone (no framework). Goal: stay comfortably under whatever Swiggy's real
// per-IP limit is, WITHOUT proxy/IP rotation. We measure latency and back off.
//
// Four ideas borrowed (see memory: instamart-scraper-research):
//   1. AutoThrottle adaptive delay: delay drifts toward (latency / target_concurrency),
//      smoothed, clamped to [minDelay, maxDelay]. target_concurrency = 1 => one in flight.
//   2. Non-200 guard: a fast error/429 page must NOT be allowed to *lower* the delay.
//   3. Honor Retry-After: if the server tells us how long to wait, we obey it exactly.
//   4. Hard per-window request budget: belt-and-suspenders on top of adaptive delay.

const sleep = (ms) => new Promise((r) => setTimeout(r, Math.max(0, Math.round(ms))));

class Throttle {
  constructor(opts = {}) {
    this.startDelay = opts.startDelay ?? 5000;   // initial gap between requests (ms)
    this.minDelay   = opts.minDelay   ?? 2500;   // floor (DOWNLOAD_DELAY)
    this.maxDelay   = opts.maxDelay   ?? 60000;  // ceiling
    this.targetConcurrency = opts.targetConcurrency ?? 1;
    this.randomize  = opts.randomize  ?? true;   // RANDOMIZE_DOWNLOAD_DELAY: uniform(0.5x,1.5x)
    this.windowMs   = opts.windowMs   ?? 300000; // AWS WAF rate windows are 60-300s; use 5 min
    this.budget     = opts.budget     ?? 80;     // max requests per window (well under any plausible cap)

    this.delay = this.startDelay;
    this.windowStart = Date.now();
    this.count = 0;
    this.requests = 0;
  }

  // Call BEFORE each request. Enforces the per-window budget, then sleeps the
  // (optionally randomized) current delay.
  async wait() {
    const now = Date.now();
    if (now - this.windowStart >= this.windowMs) { this.windowStart = now; this.count = 0; }
    if (this.count >= this.budget) {
      const rest = this.windowMs - (now - this.windowStart);
      if (rest > 0) { console.error(`[throttle] window budget ${this.budget} hit; sleeping ${Math.round(rest/1000)}s`); await sleep(rest); }
      this.windowStart = Date.now(); this.count = 0;
    }
    let d = this.delay;
    if (this.randomize) d = d * (0.5 + Math.random()); // uniform(0.5x, 1.5x)
    await sleep(d);
    this.count++;
    this.requests++;
  }

  // Call AFTER each response with the measured latency (ms), HTTP status, and
  // Retry-After seconds if present. Implements the AutoThrottle adjustment.
  observe(latencyMs, status, retryAfterSec) {
    if (retryAfterSec && retryAfterSec > 0) {
      // Server told us exactly how long to wait — obey, and don't go below it.
      this.delay = Math.min(this.maxDelay, Math.max(this.delay, retryAfterSec * 1000));
      return;
    }
    const target = Math.max(0, latencyMs) / this.targetConcurrency;
    let nd = (this.delay + target) / 2;     // smooth halfway toward target
    nd = Math.max(target, nd);              // bias slow, not fast
    nd = Math.min(Math.max(this.minDelay, nd), this.maxDelay);
    // Non-200 guard: never let a fast error response speed us up.
    if (status && status !== 200 && nd <= this.delay) return;
    this.delay = nd;
  }

  // Decide whether a status is worth retrying (Scrapy RETRY_HTTP_CODES).
  static retryable(status) {
    return [429, 500, 502, 503, 504, 408, 522, 524].includes(status);
  }

  // Exponential backoff with jitter (the bit Scrapy itself lacks) — used when
  // there is no Retry-After header.
  static backoffMs(attempt, base = 3000, cap = 30000) {
    return Math.min(cap, base * Math.pow(2, attempt)) + Math.floor(Math.random() * 1000);
  }
}

module.exports = { Throttle, sleep };
