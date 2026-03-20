# Pi-k3s Homelab — GitOps Migration

## What This Is

A Raspberry Pi K3s homelab cluster running Jellyfin and Pi-hole, being migrated from manual `make deploy` to a fully GitOps-driven workflow using Flux CD. Helm charts replace raw manifests, and all cluster state changes flow through git — no direct kubectl or ansible-apply paths after bootstrapping.

## Core Value

Push to main → cluster converges. No manual deploy steps after initial cluster setup.

## Requirements

### Validated

- ✓ K3s cluster provisioned via Ansible on 3 Raspberry Pis — existing
- ✓ Jellyfin deployed with USB storage and local-path PVC — existing
- ✓ Pi-hole deployed as DaemonSet with mDNS via avahi — existing
- ✓ Traefik ingress with hostnames for Jellyfin and Pi-hole web UI — existing
- ✓ Flux CD bootstrapped on cluster, authenticating via SSH deploy key — Validated in Phase 2: flux-bootstrap
- ✓ Jellyfin and Pi-hole raw manifests converted to Helm charts in `charts/` — Validated in Phase 1: helm-charts-and-flux-wiring
- ✓ Flux HelmRelease CRDs reference local charts from this repo — Validated in Phase 1: helm-charts-and-flux-wiring
- ✓ Flux watches `main` branch — pushing to main triggers cluster convergence — Validated in Phase 3: migration-and-ownership-transfer
- ✓ `make deploy` removed; Flux is the sole deploy path — Validated in Phase 4: makefile-cleanup

### Active

*(All requirements validated — milestone complete)*

### Out of Scope

- Secrets management (Sealed Secrets, SOPS) — cluster not internet-exposed, no sensitive secrets in use
- Separate GitOps repo — same repo approach keeps everything co-located
- Published/external Helm chart registry — charts live locally in `charts/`
- `gitops` branch strategy — direct push to main is sufficient for a homelab

## Context

- Existing k8s manifests live in `k8s/jellyfin/` and `k8s/pihole/` — some are Jinja2-generated from `ansible/group_vars/all.yaml` via `make generate`
- A `k8s/flux-system/gotk-sync.yaml` already exists (likely a stub from a prior attempt)
- `make deploy` currently runs `kubectl apply` directly — this will be removed
- No secrets to manage: Pi-hole has no web password set, cluster is LAN-only
- Hardware: 3 Pis (the-bakery .100 = control plane, apple-pi .101 = Jellyfin/storage, pumpkin-pi .102 = agent)

## Constraints

- **Infrastructure**: All setup/install steps must continue to go through `make` commands (CLAUDE.md requirement)
- **No direct kubectl**: Changes to cluster state after bootstrapping must flow through Flux, not `kubectl apply`
- **Node affinity**: Jellyfin must remain pinned to `apple-pi` (USB storage attached there)
- **exFAT**: USB mount does not support Unix ownership — Helm chart must preserve `uid=0,gid=0,umask=000` mount options

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flux in same repo | Simpler — one repo manages infra + cluster state | ✓ Implemented |
| SSH deploy key for Flux auth | Scoped to this repo, no broad token access | ✓ Implemented |
| Local Helm charts (not OCI registry) | Homelab simplicity, no external registry dependency | ✓ Implemented |
| HelmRelease CRDs via Helm Controller | Flux-native way to manage Helm charts declaratively | ✓ Implemented |
| Remove make deploy | Eliminates dual deploy paths and accidental manual applies | ✓ Implemented in Phase 4 |

## Current State

Phase 4 complete — GitOps migration milestone fully delivered. Push to `main` is now the only way to deploy changes. All four phases complete.

---
*Last updated: 2026-03-20 after Phase 4 completion*
