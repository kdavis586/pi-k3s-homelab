---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: milestone_complete
stopped_at: v1.0 GitOps Migration milestone archived — 4 phases, 8 plans complete
last_updated: "2026-03-20T14:27:11.020Z"
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 8
  completed_plans: 8
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Push to main → cluster converges. No manual deploy steps after initial cluster setup.
**Current focus:** Planning next milestone (v1.1)

## Current Position

Milestone v1.0 complete — all 4 phases shipped.
Next: `/gsd:new-milestone` to define v1.1 scope.

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01-helm-charts-and-flux-wiring P01 | 2min | 2 tasks | 7 files |
| Phase 01 P02 | 2min | 2 tasks | 6 files |
| Phase 01 P03 | 1min | 3 tasks | 4 files |
| Phase 02-flux-bootstrap P01 | 2min | 2 tasks | 1 files |
| Phase 02-flux-bootstrap P02 | ~45min | 2 tasks | 5 files |
| Phase 03-migration-and-ownership-transfer P01 | 20min | 2 tasks | 2 files |
| Phase 03-migration-and-ownership-transfer P02 | 9min | 2 tasks | 12 files |
| Phase 03 P02 | 60min | 3 tasks | 12 files |
| Phase 04-makefile-cleanup P01 | 4min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- All phases: Flux in same repo (one repo manages infra + cluster state)
- All phases: SSH deploy key for Flux auth (scoped to this repo)
- All phases: Local Helm charts in `charts/` (no external registry)
- Phase 1: `reconcileStrategy: Revision` must be set at authoring time or chart changes are invisible to Flux
- [Phase 01-helm-charts-and-flux-wiring]: Hardcode namespace: jellyfin in all Helm templates (not Release.Namespace) to prevent accidental namespace drift
- [Phase 01-helm-charts-and-flux-wiring]: Use Traefik IngressRoute CRD (traefik.io/v1alpha1) not standard Ingress, matching K3s default ingress controller
- [Phase 01]: Hardcode namespace: pihole in all Helm templates (not Release.Namespace) — chart is single-purpose
- [Phase 01]: Use Traefik IngressRoute (traefik.io/v1alpha1) CRD in Pi-hole chart — standard Ingress incompatible with K3s bundled Traefik
- [Phase 01 P03]: Flux Kustomization CRD for apps committed to flux/flux-system/apps-kustomization.yaml (not flux/apps/) to avoid filename collision with plain kustomize config
- [Phase 01 P03]: prune: false mandatory in Phase 1 Flux Kustomization — prevents deletion of live workloads before Flux owns them; Phase 3 enables prune
- [Phase 01 P03]: reconcileStrategy: Revision must be at spec.chart.spec level in HelmRelease — required for Flux to detect local chart file changes without Chart.yaml version bumps
- [Phase 02-flux-bootstrap]: bootstrap-flux uses --path=flux so Flux manifests land in flux/flux-system/ (not k8s/flux-system/)
- [Phase 02-flux-bootstrap]: Flux controller version pinned to v2.4.0 via --version flag matching flux_version in all.yaml
- [Phase 02-flux-bootstrap P02]: Bootstrap uses GitHub App auth (Bitwarden-stored PEM) not GITHUB_TOKEN PAT — no plaintext secrets in environment
- [Phase 02-flux-bootstrap P02]: Flux installed v2.8.3 (not v2.4.0) — resolved to latest compatible; update flux_version in all.yaml to match
- [Phase 02-flux-bootstrap P02]: gotk-*.yaml committed by bootstrap directly to main — never commit these manually
- [Phase 03-migration-and-ownership-transfer]: Delete-then-reconcile is the correct Flux ownership transfer approach: delete kubectl resources (preserve PVC), delete stale Helm release Secret, then flux reconcile helmrelease
- [Phase 03-migration-and-ownership-transfer]: pihole-dns LoadBalancer Service exists on cluster — Plan 02 must absorb it into the Pi-hole chart or explicitly delete before reconcile
- [Phase 03-migration-and-ownership-transfer]: pihole-dns LoadBalancer Service (klipper svclb) held port 53 on worker nodes blocking hostNetwork DaemonSet — delete service before Pi-hole reconcile
- [Phase 03-migration-and-ownership-transfer]: upgrade.force: true recovers Flux HelmRelease from terminal retry-limit state; remove flag after READY=True
- [Phase 03-migration-and-ownership-transfer]: apps-kustomization.yaml Flux Kustomization CRD is dead config — flux-system Kustomization directly manages HelmReleases; prune already active via flux-system
- [Phase 03]: Pi-hole converted from DaemonSet to Deployment pinned to pumpkin-pi — one pod, avoids port 53 conflict between nodes, simpler scheduling
- [Phase 03]: mDNS sidecar approach abandoned after 3 failed fix attempts; Pi-hole custom.list ConfigMap serves jellyfin.local and pihole.local to all LAN devices
- [Phase 04-makefile-cleanup]: Remove make deploy entirely (not archive) — dead code with k8s/ deleted creates confusion

### Pending Todos

None yet.

### Blockers/Concerns

None — v1.0 milestone complete.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260321-ik3 | Align project structure and conventions with industry standards for GitOps K3s homelab | 2026-03-21 | 1e5073a | [260321-ik3-align-project-structure-and-conventions-](./quick/260321-ik3-align-project-structure-and-conventions-/) |
| 260321-iwc | Fix README accuracy: remove mDNS references, correct mermaid diagram IPs, add Initial Setup and Day-to-Day Usage sections | 2026-03-21 | 3038f3a | [260321-iwc-fix-readme-accuracy-remove-mdns-referenc](./quick/260321-iwc-fix-readme-accuracy-remove-mdns-referenc/) |

## Session Continuity

Last session: 2026-03-21T00:05:00Z
Stopped at: Completed quick task 260321-iwc — README accuracy fixes
Resume file: None
