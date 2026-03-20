---
phase: 01-helm-charts-and-flux-wiring
plan: 01
subsystem: infra
tags: [helm, jellyfin, kubernetes, traefik, k3s]

# Dependency graph
requires: []
provides:
  - Jellyfin Helm chart at charts/jellyfin/ with Chart.yaml, values.yaml, and 5 templates
  - Valid chart that helm template and helm lint both pass with 0 failures
  - All constraints from k8s/jellyfin/ raw manifests preserved (Recreate strategy, nodeSelector, hostPath media, Traefik IngressRoute, no fsGroup)
affects:
  - 01-02 (Flux wiring will reference this chart via HelmRelease)
  - 01-03 (Pi-hole chart will follow same chart structure pattern)

# Tech tracking
tech-stack:
  added: [helm v4]
  patterns: [local Helm charts in charts/ directory, hardcoded namespace in templates (not Release.Namespace)]

key-files:
  created:
    - charts/jellyfin/Chart.yaml
    - charts/jellyfin/values.yaml
    - charts/jellyfin/templates/namespace.yaml
    - charts/jellyfin/templates/deployment.yaml
    - charts/jellyfin/templates/service.yaml
    - charts/jellyfin/templates/ingress.yaml
    - charts/jellyfin/templates/pvc.yaml
  modified: []

key-decisions:
  - "Hardcode namespace: jellyfin in all templates (not Release.Namespace) — chart always deploys to a fixed namespace, prevents Helm-managed namespace drift"
  - "Use Traefik IngressRoute (traefik.io/v1alpha1) not standard Ingress — matches existing cluster setup, Traefik is the K3s default ingress controller"
  - "Generate Host() match rule from values.yaml ingress.hosts list — allows override without template changes"

patterns-established:
  - "Helm template pattern: use namespace: <fixed-name> in all resource templates, never .Release.Namespace"
  - "Values extraction: configurable values in values.yaml, structural/constraint fields hardcoded in templates"

requirements-completed: [CHART-01, CHART-02]

# Metrics
duration: 2min
completed: 2026-03-18
---

# Phase 01 Plan 01: Jellyfin Helm Chart Summary

**Jellyfin raw k8s manifests converted to Helm chart with Recreate strategy, hostPath media volume, Traefik IngressRoute, and no fsGroup — all constraints preserved exactly**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-19T02:50:46Z
- **Completed:** 2026-03-19T02:52:35Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Created charts/jellyfin/Chart.yaml and values.yaml with all configurable values extracted from existing manifests
- Created 5 Helm templates (namespace, deployment, service, ingress, pvc) faithfully converting raw k8s manifests
- Verified with helm template (renders all 5 resource kinds) and helm lint (0 failures)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Jellyfin chart scaffold and values** - `88dd54b` (feat)
2. **Task 2: Create Jellyfin Helm templates from existing manifests** - `8bbd986` (feat)

## Files Created/Modified

- `charts/jellyfin/Chart.yaml` - Helm chart metadata (apiVersion v2, version 0.1.0)
- `charts/jellyfin/values.yaml` - Default values: image, nodeSelector, resources, storage paths, ingress hosts
- `charts/jellyfin/templates/namespace.yaml` - Namespace resource (static)
- `charts/jellyfin/templates/deployment.yaml` - Deployment with Recreate strategy, nodeSelector, hostPath media volume, health probes, no securityContext/fsGroup
- `charts/jellyfin/templates/service.yaml` - ClusterIP service on port 8096 (static)
- `charts/jellyfin/templates/ingress.yaml` - Traefik IngressRoute (traefik.io/v1alpha1) with Host() rules generated from values
- `charts/jellyfin/templates/pvc.yaml` - 5Gi ReadWriteOnce PVC for Jellyfin config on local-path

## Decisions Made

- Hardcoded `namespace: jellyfin` in all templates rather than using `.Release.Namespace`. The chart is purpose-built for this homelab and always deploys to the jellyfin namespace — using Release.Namespace would allow accidental namespace drift via Helm install flags.
- Used Traefik `IngressRoute` CRD (not standard `Ingress`) matching the existing raw manifest. K3s ships with Traefik as the default ingress controller and the existing setup depends on the CRD.
- Built the IngressRoute `match` expression dynamically from `values.ingress.hosts` using Go template range/join, so hosts can be customized without editing templates.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `helm` not in default zsh PATH when invoked from Claude Code bash — resolved by using full path `/opt/homebrew/Cellar/helm/4.1.3/bin/helm`. No code change needed.

## Self-Check: PASSED

All files found and commits verified.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- charts/jellyfin/ is a valid, tested Helm chart ready for Flux HelmRelease wiring in plan 01-02
- The chart structure (Chart.yaml, values.yaml, templates/) establishes the pattern that the Pi-hole chart (plan 01-03) should follow
- No blockers

---
*Phase: 01-helm-charts-and-flux-wiring*
*Completed: 2026-03-18*
