---
phase: 01-helm-charts-and-flux-wiring
plan: "03"
subsystem: infra
tags: [flux, helm, kustomize, helmrelease, gitops, k3s]

# Dependency graph
requires:
  - phase: 01-01
    provides: charts/jellyfin Helm chart with all templates
  - phase: 01-02
    provides: charts/pihole Helm chart with all templates
provides:
  - "flux/apps/jellyfin.yaml: HelmRelease CRD for Jellyfin referencing ./charts/jellyfin"
  - "flux/apps/pihole.yaml: HelmRelease CRD for Pi-hole referencing ./charts/pihole"
  - "flux/apps/kustomization.yaml: plain Kustomize config listing HelmRelease resources"
  - "flux/flux-system/apps-kustomization.yaml: Flux Kustomization CRD pointing to ./flux/apps with prune:false and dependsOn flux-system"
affects: [02-flux-bootstrap, 03-ownership-transfer]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "HelmRelease with inline spec.chart for local git-sourced charts"
    - "reconcileStrategy: Revision inside spec.chart.spec (NOT top-level) to detect file changes without version bumps"
    - "Plain kustomize.config.k8s.io/v1beta1 in target directory, Flux Kustomization CRD (kustomize.toolkit.fluxcd.io/v1) placed in flux/flux-system/"
    - "dependsOn flux-system to ensure controllers are healthy before reconciling app HelmReleases"
    - "prune: false for Phase 1 — enabled in Phase 3 after Flux owns existing resources"

key-files:
  created:
    - flux/apps/jellyfin.yaml
    - flux/apps/pihole.yaml
    - flux/apps/kustomization.yaml
    - flux/flux-system/apps-kustomization.yaml
  modified: []

key-decisions:
  - "Committed Flux apps Kustomization CRD to flux/flux-system/apps-kustomization.yaml (not flux/apps/) to avoid filename collision with the plain kustomize config; Phase 2 bootstrap writes its own files to flux/flux-system/ and they coexist"
  - "prune: false is mandatory for Phase 1 to prevent Flux from deleting live workloads before it owns them"
  - "reconcileStrategy: Revision placed at spec.chart.spec level (not top-level spec) — required for Flux to detect local chart file changes without Chart.yaml version bumps"

patterns-established:
  - "Pattern: Two-file approach for Flux app directory — plain kustomization.yaml (kustomize.config.k8s.io) in flux/apps/ lists resources; Flux Kustomization CRD (kustomize.toolkit.fluxcd.io) in parent directory points to the path"
  - "Pattern: All HelmReleases for local charts include reconcileStrategy: Revision at spec.chart.spec"

requirements-completed: [CHART-05, FLUX-01, FLUX-02, FLUX-03]

# Metrics
duration: 1min
completed: "2026-03-19"
---

# Phase 01 Plan 03: Flux Wiring Summary

**Flux CD wiring complete: HelmRelease CRDs for Jellyfin and Pi-hole with reconcileStrategy: Revision, plain kustomize discovery config, and Flux Kustomization CRD with dependsOn flux-system and prune: false**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-19T02:55:32Z
- **Completed:** 2026-03-19T02:56:42Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Created HelmRelease CRDs for both Jellyfin and Pi-hole with correct local chart path references and `reconcileStrategy: Revision` in `spec.chart.spec` (not top-level)
- Created plain `kustomize.config.k8s.io/v1beta1` Kustomization in `flux/apps/` listing both HelmRelease files for kustomize-controller discovery
- Created Flux `kustomize.toolkit.fluxcd.io/v1` Kustomization CRD in `flux/flux-system/` with `dependsOn: flux-system` and `prune: false` — ready for Phase 2 bootstrap to pick up
- Full phase validation passed: both charts render and lint clean, all Flux wiring grep checks pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Create HelmRelease CRDs for Jellyfin and Pi-hole** - `c427718` (feat)
2. **Task 2: Create Kustomization files for Flux app discovery** - `bb2e698` (feat)
3. **Task 3: Run full phase validation** - no separate commit (validation-only task)

## Files Created/Modified
- `flux/apps/jellyfin.yaml` - HelmRelease CRD for Jellyfin: references `./charts/jellyfin`, `reconcileStrategy: Revision`, `targetNamespace: jellyfin`, `createNamespace: false`
- `flux/apps/pihole.yaml` - HelmRelease CRD for Pi-hole: references `./charts/pihole`, `reconcileStrategy: Revision`, `targetNamespace: pihole`, `createNamespace: false`
- `flux/apps/kustomization.yaml` - Plain Kustomize config (kustomize.config.k8s.io/v1beta1) listing `jellyfin.yaml` and `pihole.yaml` as resources
- `flux/flux-system/apps-kustomization.yaml` - Flux Kustomization CRD (kustomize.toolkit.fluxcd.io/v1): `path: ./flux/apps`, `prune: false`, `dependsOn: [{name: flux-system}]`

## Decisions Made
- Committed the Flux Kustomization CRD to `flux/flux-system/apps-kustomization.yaml` rather than `flux/apps/kustomization.yaml` to avoid a filename collision with the plain kustomize config that kustomize-controller needs to discover HelmRelease files. Phase 2 bootstrap writes its own files to `flux/flux-system/` and they coexist without conflict.
- Set `prune: false` — required for Phase 1 so Flux does not delete existing live workloads before it owns them. Phase 3 will enable prune after ownership transfer.
- `reconcileStrategy: Revision` lives at `spec.chart.spec` inside HelmRelease — this is critical for local charts where `Chart.yaml` version is not bumped on every git push.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- Phase 1 artifacts are complete: `charts/jellyfin/`, `charts/pihole/`, and all Flux wiring in `flux/`
- Phase 2 (Flux bootstrap) can proceed: `flux bootstrap github` will write to `flux/flux-system/` and pick up `apps-kustomization.yaml` which is already committed there
- Known concern from STATE.md: existing `k8s/flux-system/gotk-sync.yaml` stub uses wrong path (`./k8s`) and HTTPS URL — Phase 2 bootstrap must supersede it; validate it does not create a duplicate Kustomization

---
*Phase: 01-helm-charts-and-flux-wiring*
*Completed: 2026-03-19*
