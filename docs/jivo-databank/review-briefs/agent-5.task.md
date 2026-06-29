# Reviewer 5 — COVERAGE, completeness & tier classification (read-only, adversarial)
Verify nothing was silently dropped and classification is correct.
CHECK:
1. All matched products (core + new_confirmed in bridge_result.json, ~170) exist as product nodes — list any MISSING.
2. The unmatched (no_ecom / needs_help / pack-gaps) — are they NOTED somewhere, not silently dropped?
3. Hubs present + correct: 10 platforms (amazon,swiggy,blinkit,zepto,flipkart,flipkart_grocery,jiomart,bigbasket,citymall,zomato), all categories, Premium/Commodity/Other — each backlinks its members.
4. TIER per product correct: PREMIUM=canola,groundnut,pomace,extra-light/virgin/olive,sesame,yellow mustard,coconut,ghee; COMMODITY=mustard kacchi ghani,sunflower,soyabean,rice bran,gold; else OTHER. Flag misclassifications.
5. Home.md is a complete map-of-content.
OUTPUT: /root/orchestrator/runs/vaultreview/shared/agent-5.findings.md (missing products/hubs, misclassifications, verdict). Append to .../shared/bus.md: "R5 coverage: <verdict>". `touch .../shared/vaultreview-5.done`. READ-ONLY.
