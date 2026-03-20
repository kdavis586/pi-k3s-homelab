---
phase: 02-flux-bootstrap
plan: 01
subsystem: infra
tags: [flux, gitops, makefile, k8s]

# Dependency graph
requires:
  - phase: 01-helm-charts-and-flux-wiring
    provides: flux/ directory structure and Flux Kustomization manifests
provides:
  - Corrected Makefile bootstrap-flux target using --path=flux and --version=v2.4.0
  - Removal of stale k8s/flux-system/gotk-sync.yaml stub
affects: [02-flux-bootstrap, 03-flux-gitops-adoption]

# Tech tracking
tech-stack:
  added: []
  patterns: [Makefile target pins Flux version to match group_vars/all.yaml flux_version]

key-files:
  created: []
  modified:
    - Makefile

key-decisions:
  - "bootstrap-flux uses --path=flux so Flux manifests land in flux/flux-system/ (not k8s/flux-system/)"
  - "Flux controller version pinned to v2.4.0 via --version flag matching flux_version in all.yaml"
  - "Stale k8s/flux-system/gotk-sync.yaml was never tracked in git — deleted from filesystem only"

patterns-established:
  - "Makefile bootstrap-flux target: guard checks (flux CLI, GITHUB_TOKEN) precede the bootstrap command"

requirements-completed: [BOOT-01, BOOT-04]

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 02 Plan 01: Fix bootstrap-flux Makefile target and remove stale gotk-sync.yaml stub

**Makefile bootstrap-flux target corrected to --path=flux and --version=v2.4.0; stale HTTPS-based gotk-sync.yaml stub removed from filesystem**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T13:05:30Z
- **Completed:** 2026-03-19T13:07:41Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Fixed --path=k8s to --path=flux in bootstrap-flux Makefile target so bootstrap produces flux/flux-system/ (not k8s/flux-system/)
- Added --version=v2.4.0 flag to pin Flux controllers to the version declared in group_vars/all.yaml
- Removed stale k8s/flux-system/gotk-sync.yaml that used HTTPS URL and wrong path (./k8s) — was never tracked in git

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix bootstrap-flux Makefile target** - `335b75b` (fix)
2. **Task 2: Delete stale k8s/flux-system/gotk-sync.yaml** - no git commit (file was never tracked; deleted from filesystem)

**Plan metadata:** (pending docs commit)

## Files Created/Modified

- `Makefile` - Fixed bootstrap-flux target: --path=flux, --version=v2.4.0 added; pre-existing uncommitted flux-status and flux-reconcile targets also captured in this commit

## Decisions Made

- `--path=flux` is correct because `flux bootstrap github` creates a `flux-system/` subdirectory inside the `--path` argument, producing `flux/flux-system/` which matches Phase 1 artifact locations
- Pinning `--version=v2.4.0` prevents the Flux CLI from installing whatever controller version it ships with, keeping it aligned with `flux_version` in all.yaml
- The stale `k8s/flux-system/gotk-sync.yaml` was never added to git (appeared as `??` in `git status`) — deletion required only a filesystem `rm`, no `git rm`

## Deviations from Plan

None - plan executed exactly as written.

Note: The Makefile commit also captured previously unstaged changes (flux-status and flux-reconcile targets, updated .PHONY line, deploy comment update) that were already present from prior sessions. These are not deviations — they were pre-existing unstaged work that was part of the intended Makefile state.

## Issues Encountered

- `git rm k8s/flux-system/gotk-sync.yaml` failed because the file was never tracked (untracked `??` in git status). Resolved by using `rm` directly and confirming the file is absent.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Makefile bootstrap-flux target is correct and ready for execution
- Running `make bootstrap-flux` (with GITHUB_TOKEN set) will bootstrap Flux v2.4.0 controllers and create manifests in flux/flux-system/
- The removed gotk-sync.yaml cannot accidentally be applied via `make deploy`
- Phase 02-02 can proceed to run the actual bootstrap

## Self-Check: PASSED

- Makefile: FOUND
- 02-01-SUMMARY.md: FOUND
- Commit 335b75b: FOUND

---
*Phase: 02-flux-bootstrap*
*Completed: 2026-03-19*
