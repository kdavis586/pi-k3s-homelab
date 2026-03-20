---
phase: 3
slug: migration-and-ownership-transfer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl / flux CLI (shell commands) |
| **Config file** | none — CLI-based verification |
| **Quick run command** | `make status` |
| **Full suite command** | `flux get helmreleases -A && make status` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `make status`
- **After every plan wave:** Run `flux get helmreleases -A && make status`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | MIG-01 | cli | `flux get helmreleases -A \| grep jellyfin` | ✅ | ⬜ pending |
| 3-01-02 | 01 | 1 | MIG-01 | cli | `curl -s http://jellyfin.local` | ✅ | ⬜ pending |
| 3-02-01 | 02 | 2 | MIG-02 | cli | `flux get helmreleases -A \| grep pihole` | ✅ | ⬜ pending |
| 3-02-02 | 02 | 2 | MIG-02 | cli | `curl -s http://192.168.1.100/admin` | ✅ | ⬜ pending |
| 3-03-01 | 03 | 3 | MIG-03 | cli | `grep 'prune: true' flux/clusters/homelab/apps-kustomization.yaml` | ✅ | ⬜ pending |
| 3-04-01 | 03 | 3 | MIG-04 | git | `test ! -d k8s/jellyfin && test ! -d k8s/pihole && echo REMOVED` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — all verification is CLI-based using kubectl, flux, and curl.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Jellyfin library intact after migration | MIG-01 | Requires visual UI check | Open http://jellyfin.local, verify library entries present |
| Pi-hole DNS resolving for LAN clients | MIG-02 | Requires live client DNS test | From a client device, `nslookup google.com 192.168.1.101` returns valid response |
| No field manager conflicts | MIG-01, MIG-02 | Requires inspect of HelmRelease conditions | `flux get helmreleases -A` shows no "field manager conflict" in MESSAGE column |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
