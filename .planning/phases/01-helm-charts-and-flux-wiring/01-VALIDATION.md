---
phase: 1
slug: helm-charts-and-flux-wiring
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | helm template (built-in CLI) + bash/grep |
| **Config file** | none — no test framework required |
| **Quick run command** | `helm template charts/jellyfin \| grep -q "Recreate" && helm template charts/pihole \| grep -q "hostNetwork"` |
| **Full suite command** | `helm template charts/jellyfin && helm template charts/pihole` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | CHART-01 | file+render | `helm template charts/jellyfin \| grep -q "kind: Deployment"` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | CHART-02 | render | `helm template charts/jellyfin \| grep -q "nodeSelector"` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | CHART-03 | render | `helm template charts/pihole \| grep -q "hostNetwork"` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | CHART-04 | render | `helm template charts/pihole \| grep -q "NET_ADMIN"` | ❌ W0 | ⬜ pending |
| 1-01-05 | 01 | 1 | CHART-05 | render | `helm template charts/jellyfin \| grep -v "fsGroup"` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | FLUX-01 | file | `test -f flux/apps/jellyfin.yaml && grep -q "HelmRelease" flux/apps/jellyfin.yaml` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | FLUX-02 | file | `test -f flux/apps/pihole.yaml && grep -q "HelmRelease" flux/apps/pihole.yaml` | ❌ W0 | ⬜ pending |
| 1-02-03 | 02 | 2 | FLUX-03 | file | `grep -q "dependsOn" flux/flux-system/apps-kustomization.yaml` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `charts/jellyfin/` — chart scaffold must exist before `helm template` can run
- [ ] `charts/pihole/` — chart scaffold must exist before `helm template` can run

*Charts are the test artifacts themselves; Wave 0 means creating the chart stubs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| reconcileStrategy takes effect on Flux reconcile | FLUX-01, FLUX-02 | Requires live Flux controller; cluster may not be bootstrapped in Phase 1 | After Phase 2 bootstrap: `flux reconcile helmrelease jellyfin -n jellyfin` and observe revision change |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
