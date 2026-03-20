---
phase: 03-migration-and-ownership-transfer
plan: "01"
subsystem: infra
tags: [flux, helm, jellyfin, gitops, ownership-transfer]

# Dependency graph
requires:
  - phase: 02-flux-bootstrap
    provides: Flux controllers running, GitRepository polling main, HelmRelease CRDs applied
provides:
  - Jellyfin Deployment, Service, IngressRoute owned by Flux helm-controller (not kubectl)
  - PVC jellyfin-config preserved through ownership transfer
  - Pre-flight assessment findings documented for Plan 02
affects:
  - 03-02-pihole-ownership-transfer

# Tech tracking
tech-stack:
  added: []
  patterns:
    - delete-then-reconcile for transferring kubectl-managed resources to Flux Helm ownership
    - delete stale Helm release Secret before reconcile to force clean install

key-files:
  created: []
  modified:
    - ansible/group_vars/all.yaml (added flux_version and github_repo vars)
    - k8s/pihole/service-dns.yaml (removed — old kubectl manifest, replaced by Helm chart)

key-decisions:
  - "Delete-then-reconcile is the correct ownership transfer approach: delete resources (not PVC), delete stale Helm release Secret, then flux reconcile helmrelease"
  - "homelab/node-group=workloads node labels already present on apple-pi and pumpkin-pi — no label step needed in Plan 02"
  - "pihole-dns LoadBalancer Service already exists on cluster — Plan 02 must include it in the Pi-hole chart or explicitly delete it before reconcile"

patterns-established:
  - "Ownership transfer pattern: delete kubectl resources (preserve PVC) → delete Helm release Secret → flux reconcile → verify READY=True"
  - "Pre-flight assessment before any ownership transfer: check HelmRelease status, Helm release Secrets, node labels, existing services, PVC state"

requirements-completed: [MIG-01]

# Metrics
duration: ~20min
completed: 2026-03-20
---

# Phase 3 Plan 01: Pre-flight Assessment and Jellyfin Ownership Transfer Summary

**Jellyfin Deployment/Service/IngressRoute transferred from kubectl to Flux helm-controller ownership via delete-then-reconcile, with PVC jellyfin-config preserved and HelmRelease READY=True**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-03-20T10:11:19Z
- **Completed:** 2026-03-20T10:30:00Z (approx, includes human verification)
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 2

## Accomplishments

- Completed pre-flight cluster assessment: node labels present, pihole-dns LoadBalancer service exists (noted for Plan 02), PVC jellyfin-config confirmed Bound
- Deleted stale Helm release Secret and kubectl-managed Jellyfin resources (Deployment, Service, IngressRoute), preserving PVC
- Flux reconcile reinstalled Jellyfin via helm-controller; HelmRelease READY=True, field managers: helm-controller + k3s only
- Human verified Jellyfin accessible at http://jellyfin.local with media library intact

## Task Commits

Each task was committed atomically:

1. **Task 1: Pre-flight cluster assessment and Jellyfin ownership transfer** - `eaaf6c9` (feat)
2. **Task 2: Verify Jellyfin accessibility after ownership transfer** - human-verify checkpoint, approved by user

**Plan metadata:** (this commit)

## Files Created/Modified

- `ansible/group_vars/all.yaml` - Added flux_version and github_repo vars (pre-existing Phase 2 changes committed here)
- `k8s/pihole/service-dns.yaml` - Removed (old kubectl manifest superseded by Pi-hole Helm chart)

## Decisions Made

- **Delete-then-reconcile is the correct transfer approach:** Attempting to reconcile with existing kubectl-managed resources causes field manager conflicts. Deleting the resources and the stale Helm release Secret forces Flux to perform a clean install under Helm ownership.
- **Node labels already present:** Pre-flight found `homelab/node-group=workloads` already on apple-pi and pumpkin-pi — Plan 02 does not need a label step.
- **pihole-dns LoadBalancer Service already exists:** This kubectl-managed service must be handled in Plan 02 — either absorbed into the Pi-hole chart or explicitly deleted before reconcile.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

During Stage 2, a stale Helm release Secret existed from an earlier failed reconcile attempt. This was deleted before resource deletion per the plan's conditional path (Step A, error-state branch). Resolved without deviation from the documented procedure.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Jellyfin is fully under Flux ownership — READY=True, PVC preserved, UI verified
- Plan 02 (Pi-hole ownership transfer) can proceed immediately
- Key findings for Plan 02:
  - Node labels (`homelab/node-group=workloads`) already present on both worker nodes — no label step needed
  - `pihole-dns` LoadBalancer Service exists in the `pihole` namespace — must be handled (delete or absorb into chart)
  - Pi-hole pod is currently Pending (pre-existing blocker: DaemonSet scheduling) — Plan 02 must resolve this

---
*Phase: 03-migration-and-ownership-transfer*
*Completed: 2026-03-20*
