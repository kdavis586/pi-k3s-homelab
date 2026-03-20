---
phase: 03-migration-and-ownership-transfer
plan: "02"
subsystem: infra
tags: [flux, helm, pihole, gitops, ownership-transfer, prune]

# Dependency graph
requires:
  - phase: 03-migration-and-ownership-transfer
    provides: Jellyfin Flux ownership (03-01), pihole-dns LoadBalancer service identified for deletion
  - phase: 02-flux-bootstrap
    provides: Flux controllers running, GitRepository polling main, HelmRelease CRDs applied
provides:
  - Pi-hole DaemonSet owned by Flux helm-controller (READY=True on apple-pi + pumpkin-pi)
  - prune: true enabled on flux-system Kustomization (git is sole source of truth)
  - Raw manifest directories k8s/jellyfin/ and k8s/pihole/ removed from repo
  - ansible/group_vars/all.yaml flux_version updated to v2.8.3 (matches actual installed version)
affects:
  - 03-03-validation (if planned)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Delete pihole-dns LoadBalancer service before Pi-hole DaemonSet transfer to free port 53 on hostNetwork nodes"
    - "upgrade.force: true used to recover Flux HelmRelease from terminal retry-limit state"
    - "flux-system Kustomization (path: ./flux) directly owns all HelmReleases via recursive YAML discovery — no separate apps Kustomization needed"

key-files:
  created: []
  modified:
    - flux/apps/pihole.yaml (upgrade.force: true added then removed after successful transfer)
    - flux/flux-system/apps-kustomization.yaml (prune: false -> true)
    - ansible/group_vars/all.yaml (flux_version: v2.4.0 -> v2.8.3)
  deleted:
    - k8s/jellyfin/deployment.yaml
    - k8s/jellyfin/ingress.yaml
    - k8s/jellyfin/namespace.yaml
    - k8s/jellyfin/pvc.yaml
    - k8s/jellyfin/service.yaml
    - k8s/pihole/00-namespace.yaml
    - k8s/pihole/daemonset.yaml
    - k8s/pihole/ingress.yaml
    - k8s/pihole/service-web.yaml

key-decisions:
  - "pihole-dns LoadBalancer Service (klipper svclb) held port 53 on both worker nodes, blocking Pi-hole hostNetwork DaemonSet pods from scheduling — delete service first, then Flux reconcile succeeds"
  - "upgrade.force: true is the correct recovery path when Flux HelmRelease hits terminal retry limit; remove after successful upgrade"
  - "apps-kustomization.yaml (Flux Kustomization CRD) is dead config — flux-system Kustomization directly manages HelmReleases via recursive YAML discovery of ./flux path; prune: true already active via flux-system"

patterns-established:
  - "Port conflict diagnosis: if hostNetwork DaemonSet pods are Pending with FailedScheduling + 'free ports', check for svclb-* kube-system pods holding the same port"
  - "Flux retry-limit recovery: add upgrade.force: true, reconcile, then remove force flag after READY=True"

requirements-completed: [MIG-02, MIG-03, MIG-04]

# Metrics
duration: ~9min
completed: 2026-03-20
---

# Phase 3 Plan 02: Pi-hole Ownership Transfer and Prune Enablement Summary

**Pi-hole transferred from kubectl to Flux helm-controller via delete-pihole-dns-then-reconcile pattern; prune: true active; k8s/jellyfin/ and k8s/pihole/ removed — git is now sole source of truth**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-03-20T10:15:58Z
- **Completed:** 2026-03-20T10:25:00Z (approx, pending human verify checkpoint)
- **Tasks:** 2 auto complete + 1 checkpoint (human-verify pending)
- **Files modified:** 3 modified, 9 deleted

## Accomplishments

- Identified and resolved Pi-hole scheduling blocker: `pihole-dns` LoadBalancer Service held port 53 on both worker nodes via klipper svclb pods, preventing hostNetwork DaemonSet from binding; deleted service to free port
- Pi-hole HelmRelease READY=True; both pihole pods Running on apple-pi (192.168.1.101) and pumpkin-pi (192.168.1.102)
- Used `upgrade.force: true` to recover from Flux terminal retry-limit state after initial upgrade timeout; removed flag after successful transfer
- Enabled prune on apps-kustomization.yaml (prune: false -> true); effective prune is via flux-system Kustomization which directly manages HelmReleases
- Removed k8s/jellyfin/ and k8s/pihole/ raw manifest directories (9 files); k8s/storage/ and k8s/templates/ retained
- Updated flux_version in all.yaml from v2.4.0 to v2.8.3 to match actually installed version

## Task Commits

Each task was committed atomically:

1. **Task 1 (intermediate): Add upgrade.force to unblock HelmRelease** - `04dff45` (fix)
2. **Task 1: Pi-hole ownership transferred to Flux helm-controller** - `1ab1c8e` (feat)
3. **Task 2: Enable prune, remove raw manifests, update flux_version** - `393000d` (chore)

**Plan metadata:** (this commit)

## Files Created/Modified

- `flux/apps/pihole.yaml` - `upgrade.force: true` added to recover from retry-limit, then removed after successful transfer
- `flux/flux-system/apps-kustomization.yaml` - `prune: false` changed to `prune: true`
- `ansible/group_vars/all.yaml` - `flux_version` updated from `v2.4.0` to `v2.8.3`
- `k8s/jellyfin/` (5 files) - removed (Flux owns workload)
- `k8s/pihole/` (4 files) - removed (Flux owns workload, service-dns.yaml removed in 03-01)

## Decisions Made

- **pihole-dns LoadBalancer Service must be deleted before Pi-hole DaemonSet transfer:** The klipper service load balancer (svclb) creates DaemonSet pods in kube-system that bind port 53 on every node. Pi-hole uses `hostNetwork: true` and also needs port 53. Deleting the LoadBalancer service terminates the svclb pods and frees port 53 immediately — Pi-hole pods went from Pending to Running without any other changes.
- **upgrade.force: true recovery path confirmed:** When a Flux HelmRelease reaches "terminal error: exceeded maximum retries: cannot remediate failed release", annotating for reconcile alone is insufficient. Adding `upgrade.force: true` in the HelmRelease spec triggers a forced upgrade cycle that breaks out of the terminal state.
- **apps-kustomization.yaml is effectively dead config:** The `flux-system` Kustomization (path: `./flux`) discovers and applies all YAML files recursively, including HelmReleases in `flux/apps/`. The Flux `Kustomization` CRD in `apps-kustomization.yaml` was never actually applied (not included in `flux/flux-system/kustomization.yaml`). The HelmReleases are directly managed by `flux-system` Kustomization, which already has `prune: true`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added intermediate fix commit for upgrade.force recovery before task completion commit**
- **Found during:** Task 1 (Pi-hole ownership transfer)
- **Issue:** Pi-hole HelmRelease entered terminal retry-limit state after upgrade timeout caused by port 53 conflict; the `flux reconcile helmrelease` command alone cannot recover from this state
- **Fix:** Added `upgrade.force: true` as an intermediate commit, pushed, reconciled to recover to READY=True, then removed `force: true` in the final task commit
- **Files modified:** `flux/apps/pihole.yaml`
- **Verification:** `flux get hr pihole -n flux-system` showed READY=True after force upgrade
- **Committed in:** `04dff45` (intermediate), `1ab1c8e` (task 1 final)

---

**Total deviations:** 1 auto-fixed (Rule 1 - required multi-step recovery path not in original plan)
**Impact on plan:** Required fix for plan completion. Port conflict was the pre-existing blocker noted in 03-01-SUMMARY.md; recovery path was the plan's own fallback step (Step 6). No scope creep.

## Issues Encountered

The `pihole-dns` LoadBalancer Service conflict was pre-identified in 03-01-SUMMARY.md. The plan correctly specified deleting the service before reconcile. What wasn't anticipated was that the Flux reconcile had already started (and failed with timeout) before this session began — resulting in the HelmRelease being in terminal retry-limit state when this plan started executing. The `upgrade.force: true` fallback (plan Step 6) resolved it.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both workloads (Jellyfin + Pi-hole) fully under Flux ownership
- Both HelmReleases READY=True simultaneously
- prune: true active on flux-system Kustomization (effective pruning for all managed resources)
- Raw manifest directories removed — git is sole source of truth
- Task 3 human-verify checkpoint pending: Pi-hole DNS resolution and Jellyfin UI accessibility check

---
*Phase: 03-migration-and-ownership-transfer*
*Completed: 2026-03-20*
