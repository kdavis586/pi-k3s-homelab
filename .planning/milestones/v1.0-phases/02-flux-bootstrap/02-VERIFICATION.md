---
phase: 02-flux-bootstrap
verified: 2026-03-20T00:00:00Z
status: passed
score: 4/4 success criteria verified
re_verification: false
---

# Phase 2: Flux Bootstrap Verification Report

**Phase Goal:** Flux CD controllers are running on the cluster and reconciling from the main branch of this repository via SSH deploy key
**Verified:** 2026-03-20
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `make bootstrap-flux` installs Flux and registers SSH deploy key without manual kubectl | VERIFIED | Makefile target uses `./scripts/get-github-app-token.sh` + `flux bootstrap github`; cluster state confirms: all 4 controllers Running, bootstrapped: true |
| 2 | GitRepository polls main at 1m interval with READY=True | VERIFIED | `flux/flux-system/gotk-sync.yaml` contains `interval: 1m0s`, `branch: main`, `url: ssh://git@github.com/kdavis586/pi-k3s-homelab`; cluster state: READY=True confirmed by user |
| 3 | Flux-generated manifests committed to `flux/flux-system/` | VERIFIED | Commits 5d1d4e8 ("Add Flux v2.8.3 component manifests") and 90e887f ("Add Flux sync manifests") exist in git history; all three files present |
| 4 | Jellyfin and Pi-hole continue running after first reconcile (prune: false in effect) | VERIFIED | `flux/flux-system/apps-kustomization.yaml` has `prune: false`; cluster state: Jellyfin Running; Pi-hole Pending (pre-existing issue 3d4h old, not caused by bootstrap) |

**Score:** 4/4 success criteria verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `flux/flux-system/gotk-components.yaml` | Flux CRDs and controller Deployments | VERIFIED | 6428 lines; contains `fluxcd` domain across CRD groups; committed by bootstrap at 5d1d4e8 |
| `flux/flux-system/gotk-sync.yaml` | GitRepository + flux-system Kustomization CRDs | VERIFIED | 27 lines; SSH URL confirmed: `ssh://git@github.com/kdavis586/pi-k3s-homelab`; interval: 1m0s; committed by bootstrap at 90e887f |
| `flux/flux-system/kustomization.yaml` | Plain kustomize config referencing gotk files | VERIFIED | References both `gotk-components.yaml` and `gotk-sync.yaml` |
| `Makefile` | bootstrap-flux target with `--path=flux` and GitHub App auth | VERIFIED | `--path=flux` at line 46; GitHub App token generation via `./scripts/get-github-app-token.sh`; guard checks for `flux` CLI and `bw` CLI present |
| `scripts/get-github-app-token.sh` | GitHub App installation token generator | VERIFIED | File exists; used by `make bootstrap-flux` target |
| `k8s/flux-system/gotk-sync.yaml` | DELETED — stale HTTPS stub must not exist | VERIFIED | File absent from filesystem; was never git-tracked (untracked `??`) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `flux/flux-system/gotk-sync.yaml` | GitHub repo main branch | SSH deploy key in flux-system secret | WIRED | `url: ssh://git@github.com/kdavis586/pi-k3s-homelab` confirmed; cluster state: GitRepository READY=True, polling main at 1m |
| `flux/flux-system/kustomization.yaml` | `gotk-components.yaml` and `gotk-sync.yaml` | kustomize resources list | WIRED | `resources:` explicitly lists both files |
| `Makefile bootstrap-flux` | `flux bootstrap github` | `--path=flux` flag | WIRED | `--path=flux` at line 46; produces `flux/flux-system/` layout matching Phase 1 artifacts |
| `flux/flux-system/apps-kustomization.yaml` | `flux/apps/` Helm charts | `prune: false` Kustomization | WIRED | `path: ./flux/apps`, `prune: false`, `interval: 10m`; apps Kustomization active on cluster |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BOOT-01 | 02-01-PLAN.md, 02-02-PLAN.md | Flux CD v2 controllers installed via `make bootstrap-flux` | SATISFIED | Flux v2.8.3 controllers running (helm-controller, kustomize-controller, notification-controller, source-controller — all 1/1 Running); `flux check` passed |
| BOOT-02 | 02-02-PLAN.md | Flux authenticates to GitHub via SSH deploy key (not HTTPS) | SATISFIED | `gotk-sync.yaml` line 14: `url: ssh://git@github.com/kdavis586/pi-k3s-homelab`; SSH deploy key registered on GitHub |
| BOOT-03 | 02-02-PLAN.md | GitRepository polls main branch on 1-minute interval | SATISFIED | `gotk-sync.yaml`: `interval: 1m0s`, `branch: main`; cluster state READY=True confirmed |
| BOOT-04 | 02-01-PLAN.md, 02-02-PLAN.md | Bootstrap manifests committed to `flux/flux-system/` | SATISFIED | All three files exist; bootstrap commits 5d1d4e8 and 90e887f in git history |
| BOOT-05 | 02-02-PLAN.md | First reconcile does not delete existing workloads (prune: false) | SATISFIED | `apps-kustomization.yaml` has `prune: false`; Jellyfin survived reconcile Running; Pi-hole Pending (pre-existing, not bootstrap-caused) |

No orphaned requirements — all five BOOT requirements are covered by the two plans.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Makefile` | 47 | `--version=v$(shell flux --version | cut -d' ' -f3)` | Info | The version flag dynamically reads the installed flux CLI version rather than pinning to the `flux_version` in `all.yaml`. This is intentional (per SUMMARY decisions) — bootstrap installed v2.8.3 when v2.4.0 was specified, so the Makefile was updated to track actual CLI version. Not a blocker. |

No blocker or warning anti-patterns found. The one info item is a documented intentional deviation.

---

### Human Verification Required

All critical verifications have been confirmed directly by the user during the Task 2 human-verify checkpoint:

1. **flux check passed** — "all checks passed", flux-v2.8.3, bootstrapped: true
2. **GitRepository READY=True** — confirmed polling main at 1m interval via SSH
3. **4 controllers Running** — helm-controller, kustomize-controller, notification-controller, source-controller
4. **Jellyfin Running** — survived first reconcile
5. **Pi-hole Pending** — pre-existing issue (3d4h before bootstrap), prune: false confirmed not deleting it
6. **SSH deploy key registered on GitHub** — user confirmed at github.com/kdavis586/pi-k3s-homelab/settings/keys

No additional human verification required.

---

### Gaps Summary

No gaps. All four success criteria are verified with codebase evidence and confirmed cluster state.

One notable deviation from Plan 02-01 intent: the `--version` flag now dynamically resolves the installed flux CLI version rather than pinning to `v2.4.0`. This is documented in SUMMARY and is an intentional decision — bootstrap installed v2.8.3 in practice, so the Makefile was updated to reflect reality. This does not block any requirement.

---

_Verified: 2026-03-20_
_Verifier: Claude (gsd-verifier)_
