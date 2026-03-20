# Milestones

## v1.0 GitOps Migration (Shipped: 2026-03-20)

**Phases completed:** 4 phases, 8 plans
**Git range:** a460d29..bafdf83
**Files changed:** 98 files, +16,455 / -241 lines
**Timeline:** 2026-03-14 → 2026-03-20 (6 days)

**Key accomplishments:**

- Jellyfin and Pi-hole converted to Helm charts at `charts/jellyfin/` and `charts/pihole/`, all K3s constraints preserved
- Flux v2.8.3 bootstrapped via GitHub App auth; GitRepository polling `main` at 1m interval
- Both workloads transferred from `kubectl` to Flux helm-controller ownership; `prune: true` enabled
- Pi-hole converted from DaemonSet to single-node Deployment; custom DNS ConfigMap serves LAN hostnames
- `make deploy` removed; CLAUDE.md, README.md, SETUP.md reflect GitOps-only workflow

---
