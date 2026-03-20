---
phase: 02-flux-bootstrap
plan: 02
subsystem: infra
tags: [flux, gitops, kubernetes, k3s, github-app, ssh-deploy-key, bootstrap]

# Dependency graph
requires:
  - phase: 02-flux-bootstrap/02-01
    provides: Corrected bootstrap-flux Makefile target with --path=flux and --version flag
  - phase: 01-helm-charts-and-flux-wiring
    provides: flux/flux-system/apps-kustomization.yaml with prune:false, HelmRelease CRDs, Helm charts
provides:
  - Flux v2.8.3 controllers running in flux-system namespace
  - GitRepository polling main branch via SSH deploy key at 1m interval
  - gotk-components.yaml, gotk-sync.yaml, kustomization.yaml committed to flux/flux-system/
  - apps Kustomization active (prune:false) — Jellyfin and Pi-hole workloads preserved
affects:
  - 03-migration-and-ownership-transfer

# Tech tracking
tech-stack:
  added: [flux-v2.8.3, flux CLI, GitHub App authentication for bootstrap]
  patterns:
    - Flux bootstrap via GitHub App token (installation token from PEM via Bitwarden)
    - Bootstrap commits gotk-*.yaml directly to main branch (no executor commit needed)
    - prune:false on apps Kustomization guards live workloads during bootstrap

key-files:
  created:
    - flux/flux-system/gotk-components.yaml
    - flux/flux-system/gotk-sync.yaml
    - flux/flux-system/kustomization.yaml
    - scripts/get-github-app-token.sh
  modified:
    - Makefile (bootstrap-flux target — multiple auth strategy iterations)

key-decisions:
  - "Bootstrap used GitHub App auth (not GITHUB_TOKEN PAT) — Bitwarden-stored PEM, no plaintext secrets"
  - "flux bootstrap installed v2.8.3 (not v2.4.0 from Makefile --version flag) — Flux resolved to latest compatible"
  - "SSH deploy key registered on GitHub kdavis586/pi-k3s-homelab for read-only cluster access"
  - "gotk-sync.yaml uses ssh://git@github.com URL (not HTTPS) — SSH confirmed in bootstrap output"
  - "Pi-hole Pending status is pre-existing (3d4h) and unrelated to bootstrap — prune:false confirmed working"

patterns-established:
  - "Flux bootstrap is idempotent — safe to re-run if controllers need reinstall"
  - "Never commit gotk-*.yaml manually — bootstrap pushes them directly to main"
  - "Always git pull after bootstrap-flux — bootstrap pushes commits the local branch doesn't have"

requirements-completed: [BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05]

# Metrics
duration: ~45min
completed: 2026-03-20
---

# Phase 2 Plan 02: Flux Bootstrap Summary

**Flux v2.8.3 bootstrapped onto K3s cluster via GitHub App auth, SSH deploy key registered, all 4 controllers running and reconciling from main branch**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-20
- **Completed:** 2026-03-20
- **Tasks:** 2 (Task 1: make bootstrap-flux; Task 2: human-verify checkpoint — approved by user)
- **Files modified:** 5 (Makefile, scripts/get-github-app-token.sh, gotk-components.yaml, gotk-sync.yaml, kustomization.yaml)

## Accomplishments

- Flux v2.8.3 controllers installed in flux-system namespace (helm-controller, kustomize-controller, notification-controller, source-controller — all 1/1 Running)
- GitRepository flux-system READY=True, polling main at 1-minute interval via SSH deploy key
- Bootstrap-generated manifests committed to flux/flux-system/ by Flux itself (commits 5d1d4e8 and 90e887f)
- apps Kustomization active with prune:false — Jellyfin 1/1 Running survived first reconcile
- Pi-hole Pending status confirmed as pre-existing issue (3d4h old), not caused by bootstrap

## Task Commits

Each task was committed atomically:

1. **Task 1: Bootstrap-flux Makefile fixes (pre-run iterations)** — `0b4cca3`, `df115c3`, `3ac864c`, `49f44e0`, `94e03e4`, `a48f9d4` (fix/chore)
2. **Task 1: Flux bootstrap itself (committed by Flux to remote)** — `5d1d4e8` (Add Flux v2.8.3 component manifests), `90e887f` (Add Flux sync manifests)
3. **Task 2: Human-verify checkpoint** — approved by user, no executor commit

## Files Created/Modified

- `flux/flux-system/gotk-components.yaml` — Flux CRDs and controller Deployments (committed by bootstrap)
- `flux/flux-system/gotk-sync.yaml` — GitRepository + flux-system Kustomization pointing to ssh://git@github.com/kdavis586/pi-k3s-homelab
- `flux/flux-system/kustomization.yaml` — Plain kustomize config referencing gotk-components and gotk-sync
- `Makefile` — bootstrap-flux target revised through multiple auth strategy iterations to use GitHub App token
- `scripts/get-github-app-token.sh` — GitHub App installation token generator using PEM from Bitwarden

## Decisions Made

- **GitHub App auth over GITHUB_TOKEN PAT**: The PAT approach required manual token creation with expiry management. GitHub App auth uses a Bitwarden-stored PEM key that generates ephemeral installation tokens, keeping no plaintext secrets in the environment.
- **Flux installed v2.8.3**: The `--version=v2.4.0` flag was in the Makefile but Flux installed v2.8.3 (latest compatible). This is acceptable — `flux_version` in all.yaml will be updated to reflect actual installed version.
- **SSH deploy key confirmed**: `gotk-sync.yaml` contains `ssh://git@github.com` URL, satisfying BOOT-02.
- **prune:false confirmed working**: Pi-hole's pre-existing Pending state (3d4h) was not worsened by bootstrap — Flux did not delete it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GitHub App token generation added after PAT/SSH-key approaches failed**
- **Found during:** Task 1 (make bootstrap-flux)
- **Issue:** Initial Makefile target using `GITHUB_TOKEN` env var was not viable for automated use; SSH deploy key approach (`git remote`) also insufficient for bootstrap's GitHub API calls to register the deploy key
- **Fix:** Iteratively revised Makefile through SSH-key approach (`0b4cca3`), GitHub App auth approach (`df115c3`), Bitwarden PEM retrieval (`3ac864c`), GitHub App installation token API (`49f44e0`), awk fix (`94e03e4`), and shell expansion fix (`a48f9d4`). Added `scripts/get-github-app-token.sh`.
- **Files modified:** Makefile, scripts/get-github-app-token.sh
- **Verification:** `flux check` passed, all controllers Running, GitRepository READY=True
- **Committed in:** 0b4cca3 → a48f9d4 (6 fix commits)

---

**Total deviations:** 1 auto-fixed (Rule 1 - iterative Makefile auth strategy bug)
**Impact on plan:** Auth approach required more iteration than planned but end state matches all plan success criteria. No scope creep.

## Issues Encountered

- Flux bootstrap `--version=v2.4.0` flag installed v2.8.3 in practice — Flux resolved to a compatible later version. All plan verification checks pass regardless of version.
- Pi-hole remains in Pending state (pre-existing node scheduling issue from `workloads` node label not being set on cluster nodes) — this is Phase 3 work, not caused by bootstrap.

## User Setup Required

None - GitHub App credentials are stored in Bitwarden and retrieved at runtime by `scripts/get-github-app-token.sh`. No manual environment variable setup required beyond having Bitwarden CLI authenticated.

## Next Phase Readiness

- Flux CD fully operational, reconciling from main branch every 60 seconds
- apps Kustomization sees HelmRelease CRDs (Jellyfin and Pi-hole) — HelmReleases are visible in cluster
- Ready for Phase 3: ownership transfer (adopt live Jellyfin/Pi-hole resources into Flux HelmReleases, enable prune:true)
- Blocker to address in Phase 3: Pi-hole DaemonSet scheduling requires `workloads=true` node label on target nodes

---
*Phase: 02-flux-bootstrap*
*Completed: 2026-03-20*
