# Reviewer 1 — ZERO-DATA-LOSS audit (read-only, adversarial)
The combined vault at /opt/ecom-intel/combined-vault/ was built by copying TWO source vaults in + adding a link layer. The owner's #1 rule = ZERO data loss. Verify it INDEPENDENTLY — do NOT trust the build's own .manifest.json; recompute everything yourself.
CHECK:
1. combined-vault/jivo/ vs /root/jivo-intel/vault/ — exact file COUNT, total BYTES, and the set of per-file sha256s must match. List ANY file missing, extra, truncated, or content-changed.
2. combined-vault/ecom/ vs /opt/ecom-intel/vault/ — same.
3. Open combined-vault/.manifest.json and verify its numbers are TRUE (recompute; flag if it overstates/lies).
4. Byte-compare the 5 LARGEST notes between source and copy.
OUTPUT: write /root/orchestrator/runs/vaultreview/shared/agent-1.findings.md (counts, every mismatch, verdict LOSSLESS=yes/no). Append one line to .../shared/bus.md: "R1 zero-loss: <verdict>". Then `touch /root/orchestrator/runs/vaultreview/shared/vaultreview-1.done`. READ-ONLY: never modify the vault or sources.
