---
phase: 2
slug: flux-bootstrap
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flux CLI + kubectl (infra verification, no test framework) |
| **Config file** | none — CLI commands against live cluster |
| **Quick run command** | `flux check --kubeconfig ~/.kube/config-pi-k3s` |
| **Full suite command** | `flux get all -n flux-system --kubeconfig ~/.kube/config-pi-k3s` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flux check --kubeconfig ~/.kube/config-pi-k3s`
- **After every plan wave:** Run `flux get all -n flux-system --kubeconfig ~/.kube/config-pi-k3s`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | BOOT-01 | file-check | `test -f Makefile && grep -q bootstrap-flux Makefile` | ✅ | ⬜ pending |
| 2-01-02 | 01 | 1 | BOOT-02 | cli-check | `flux check --kubeconfig ~/.kube/config-pi-k3s` | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | BOOT-03 | git-check | `git ls-files flux/flux-system/ \| grep -q gotk-components` | ❌ W0 | ⬜ pending |
| 2-01-04 | 01 | 1 | BOOT-04 | cli-check | `flux get sources git -n flux-system --kubeconfig ~/.kube/config-pi-k3s` | ❌ W0 | ⬜ pending |
| 2-01-05 | 01 | 1 | BOOT-05 | cli-check | `kubectl get deploy -n jellyfin --kubeconfig ~/.kube/config-pi-k3s` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- None — this phase installs Flux itself; there is no pre-existing test infrastructure to scaffold. Verification is done via `flux` and `kubectl` CLI commands post-bootstrap.

*Existing infrastructure covers all phase requirements via CLI verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GitHub deploy key appears in repo Settings → Deploy keys | BOOT-02 | Requires GitHub UI access | Navigate to repo → Settings → Deploy keys, confirm `flux-system` key is present with read access |
| GitRepository polling interval = 1m | BOOT-04 | Interval only visible in cluster resource | `kubectl get gitrepository -n flux-system -o yaml --kubeconfig ~/.kube/config-pi-k3s \| grep interval` → must show `interval: 1m` |
| Jellyfin and Pi-hole survive first reconcile | BOOT-05 | Requires watching pods during reconcile | After bootstrap, observe `kubectl get pods -A --kubeconfig ~/.kube/config-pi-k3s` — jellyfin and pihole pods must remain Running |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
