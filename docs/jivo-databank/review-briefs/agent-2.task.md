# Reviewer 2 — LINK INTEGRITY & graph health (read-only, adversarial)
Review /opt/ecom-intel/combined-vault/. Verify the wikilink graph is sound and dense WITHOUT broken or hallucinated links.
CHECK:
1. Every [[wikilink]] in every note resolves to an existing note/hub. Count + list BROKEN links (target absent).
2. Orphans = notes with zero inbound AND zero outbound links — count + sample.
3. Link density = total links / total notes — report.
4. Injected "## Related"/"## Connections" links: sample 30 across products + source notes; confirm each target EXISTS and the link is sensible (not random/hallucinated). Flag bad ones.
OUTPUT: /root/orchestrator/runs/vaultreview/shared/agent-2.findings.md (broken count, orphans, density, bad-link samples, verdict). Append to .../shared/bus.md: "R2 links: <verdict>". `touch .../shared/vaultreview-2.done`. READ-ONLY.
