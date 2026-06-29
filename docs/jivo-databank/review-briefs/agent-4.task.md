# Reviewer 4 — DATA ACCURACY vs source, NO fabrication (read-only, adversarial)
Verify every number in product/hub nodes is traceable to source — nothing invented. (Recent REAL mistakes to hunt for: a metric-gap mislabeled as an "OTHER" segment; a ROAS figure conflating platform scopes. Find anything like that.)
CHECK:
1. Price lens (ref/floor, live, diff%, violation) vs /opt/ecom-intel/data/pricematch/history.csv (latest per canonical_sku+platform). Sample >=10.
2. JIVO tier-level 2026 numbers in nodes/hubs vs /root/jivo-intel/docs/app-model/target-history.csv. Sample >=10.
3. Values absent from source must be OMITTED, not fabricated/estimated without a label.
4. Hunt mislabels, scope-conflations, over-stated coverage claims.
OUTPUT: /root/orchestrator/runs/vaultreview/shared/agent-4.findings.md (samples checked, every wrong/invented number, verdict). Append to .../shared/bus.md: "R4 accuracy: <verdict>". `touch .../shared/vaultreview-4.done`. READ-ONLY.
