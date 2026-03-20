# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — GitOps Migration

**Shipped:** 2026-03-20
**Phases:** 4 | **Plans:** 8 | **Sessions:** ~5

### What Was Built
- Jellyfin and Pi-hole Helm charts at `charts/jellyfin/` and `charts/pihole/` — all original K3s constraints preserved
- Flux v2.8.3 bootstrapped on the cluster via GitHub App auth, polling `main` at 1m interval
- Both workloads transferred from `kubectl apply` to Flux helm-controller ownership with `prune: true`
- Pi-hole converted from DaemonSet to single-node Deployment; custom DNS ConfigMap for LAN hostnames
- `make deploy` removed; CLAUDE.md, README.md, SETUP.md aligned to GitOps-only workflow

### What Worked
- GSD's phased approach: each phase had a clear goal and testable success criteria that drove clean execution
- The delete-then-reconcile pattern for Flux ownership transfer was correct — no downtime, clean field manager handoff
- Documenting gotchas in CLAUDE.md in real-time (K3s DNS deadlock, systemd-resolved stub) created durable institutional knowledge
- `reconcileStrategy: Revision` inside `spec.chart.spec` (not top-level) was the critical discovery for template-change detection

### What Was Inefficient
- Phase 2 required an unplanned fix plan (02-01) to correct the bootstrap-flux Makefile target before actual bootstrapping — research phase could have caught the `--path` and `--version` flags
- Pi-hole's DaemonSet-to-Deployment conversion was discovered during Phase 3 execution rather than planned; port 53 multi-node conflict is a known Flux/K3s pattern worth researching upfront

### Patterns Established
- `upgrade.force: true` on a HelmRelease to recover from terminal retry-limit state; remove after READY=True
- Pi-hole custom DNS via `custom.list` ConfigMap — cleaner than per-workload mDNS sidecars
- Static DNS pins (8.8.8.8/1.1.1.1) on K3s nodes to break the DNS-pull-own-image deadlock
- Bootstrap commits go directly to main (Flux writes them); no separate executor commit needed

### Key Lessons
1. **Research Makefile targets before planning bootstrap phases** — CLI flag changes between Flux versions are underdocumented and cause plan rework
2. **DaemonSet workloads with host ports conflict on multi-node clusters** — always convert to pinned Deployment when port exclusivity matters
3. **`prune: false` first, then ownership transfer, then `prune: true`** — the sequence is load-bearing; skipping it risks deleting live workloads
4. **Field manager conflicts require delete-not-patch** — `kubectl patch` won't fix Helm ownership conflicts; delete the resource and let Flux recreate it

### Cost Observations
- Model mix: ~100% sonnet (no opus or haiku used)
- Sessions: ~5 across 4 phases
- Notable: Infrastructure phases are token-efficient — most work is file edits and Ansible/Makefile changes, not large codebases

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | ~5 | 4 | Initial project — baseline established |

### Top Lessons (Verified Across Milestones)

1. Delete-then-reconcile is the correct pattern for transferring resource ownership in Flux
2. Phase research should explicitly check CLI version compatibility for infrastructure tooling
