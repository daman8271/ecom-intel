# Reviewer 3 — CROSS-VAULT FUSION correctness (read-only, adversarial)
The core deliverable: each product node fuses its JIVO source note(s) + ECOM source note(s) + price lens, joined by SKU+platform. Verify the fusion is CORRECT, not just present.
CHECK (sample >=12 products incl. Groundnut 1L, Canola 1L, Mustard 1L, an olive/pomace, a sunflower or soyabean commodity, a ghee):
1. For each product node, the links to jivo + ecom notes point to the RIGHT physical product (same oil + pack) — OPEN the linked notes and confirm, don't assume.
2. The SKU+platform join matches the bridge (/opt/ecom-intel/docs/jivo-databank/sku-bridge/bridge_result.json) — spot-check canonical_sku <-> jivo SKU.
3. Products that SHOULD fuse to both vaults but link only one — flag.
4. Any clearly WRONG fusion (e.g. Groundnut linked to a Mustard note).
OUTPUT: /root/orchestrator/runs/vaultreview/shared/agent-3.findings.md (per-sample verdict, mis-fusions, overall verdict). Append to .../shared/bus.md: "R3 fusion: <verdict>". `touch .../shared/vaultreview-3.done`. READ-ONLY.
