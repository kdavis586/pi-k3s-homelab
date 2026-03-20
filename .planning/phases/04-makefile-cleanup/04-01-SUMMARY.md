---
phase: 04-makefile-cleanup
plan: 01
subsystem: infra
tags: [makefile, flux, gitops, documentation]

# Dependency graph
requires:
  - phase: 03-migration-and-ownership-transfer
    provides: Flux fully owns all workloads, k8s/ directory deleted — make deploy is dead code
provides:
  - Clean Makefile with no deploy target
  - CLAUDE.md updated with GitOps workflow and flux diagnostics
  - README.md and SETUP.md aligned to bootstrap-flux bring-up sequence
affects: [future-phases, onboarding]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GitOps deploy: push to main, Flux reconciles within 60s"
    - "Diagnostic commands: flux get all, flux get kustomizations -A, flux get helmreleases -A, flux get sources git -A"

key-files:
  created: []
  modified:
    - Makefile
    - CLAUDE.md
    - README.md
    - SETUP.md

key-decisions:
  - "Remove make deploy entirely (not archive) — dead code with k8s/ deleted creates confusion"
  - "Document flux get kustomizations -A as fourth diagnostic command to meet completeness bar"

patterns-established:
  - "Workflow: git add -> git commit -> git push origin main -> make flux-status"
  - "Force sync: make flux-reconcile -> make flux-status"

requirements-completed: [MAKE-01, MAKE-02, MAKE-03]

# Metrics
duration: 4min
completed: 2026-03-20
---

# Phase 04 Plan 01: Makefile Cleanup Summary

**Removed imperative make deploy path and updated CLAUDE.md, README.md, SETUP.md to document GitOps (push-to-main + Flux) as the sole deploy mechanism**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-20T11:59:43Z
- **Completed:** 2026-03-20T12:03:10Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Removed `deploy` target from Makefile and deleted `ansible/playbooks/deploy.yaml` — no dead code remains
- Updated CLAUDE.md with new Workflow command block, GitOps deploy subsection with push workflow and flux diagnostic commands, updated Wrong/Right examples, and corrected Key files table (charts/ and flux/ instead of deleted k8s/)
- Updated README.md cluster bring-up sequence (bootstrap-flux replaces deploy) and Repo Structure section (removed k8s/, added charts/ and flux/)
- Updated SETUP.md Step 5 with bootstrap-flux and added post-bootstrap auto-deploy note

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove deploy target from Makefile and delete deploy.yaml** - `18ad5bc` (chore)
2. **Task 2: Update CLAUDE.md, README.md, and SETUP.md to reflect GitOps workflow** - `ed27ede` (docs)

**Plan metadata:** (final commit hash — see below)

## Files Created/Modified

- `Makefile` - Removed deploy from .PHONY and removed Day-to-day section with deploy target
- `ansible/playbooks/deploy.yaml` - Deleted (dead code)
- `CLAUDE.md` - New workflow block, GitOps subsection, updated Wrong/Right examples, updated Key files table
- `README.md` - Updated cluster bring-up bash block and Repo Structure tree
- `SETUP.md` - Updated Step 5 with bootstrap-flux and post-bootstrap note

## Decisions Made

- Remove make deploy entirely rather than archive it — it points to k8s/ which no longer exists, so keeping it would cause errors and confusion
- Add `flux get kustomizations -A` as a fourth flux get diagnostic command to satisfy the completeness requirement (plan specified >= 4 occurrences of `flux get` in CLAUDE.md)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The `help` target regex `[a-zA-Z_-]+` does not match `install-k3s` because `3` is a digit — `install-k3s` does not appear in `make help` output. This is a pre-existing bug unrelated to this plan's changes. Deferred to avoid scope creep.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 04 is now complete — all four phases of the homelab project are done
- The repo is clean: Makefile matches actual GitOps workflow, docs are accurate
- No blockers

---
*Phase: 04-makefile-cleanup*
*Completed: 2026-03-20*
