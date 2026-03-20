---
phase: 4
slug: makefile-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell / Make (no test framework — file and command verification) |
| **Config file** | none |
| **Quick run command** | `make -n deploy 2>&1 | grep -c "No rule to make target"` |
| **Full suite command** | `make -n deploy 2>&1; grep -r "make deploy" CLAUDE.md README.md SETUP.md` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Verify the specific file change (grep or make -n)
- **After every plan wave:** Run full suite command above
- **Before `/gsd:verify-work`:** All manual verifications must pass
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | MAKE-01 | file | `grep -c "deploy:" Makefile` should return 0 | ✅ | ⬜ pending |
| 4-01-02 | 01 | 1 | MAKE-01 | file | `test ! -f ansible/playbooks/deploy.yaml` | ✅ | ⬜ pending |
| 4-01-03 | 01 | 2 | MAKE-03 | file | `grep -c "make deploy" CLAUDE.md` should return 0 | ✅ | ⬜ pending |
| 4-01-04 | 01 | 2 | MAKE-03 | file | `grep -c "flux get" CLAUDE.md` should return ≥1 | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No test framework installation needed — all verification is via shell commands and file inspection.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `make flux-status` returns Flux reconciliation state | MAKE-02 | Requires live cluster connection | SSH or run `make flux-status` — should show flux objects, not error |
| CLAUDE.md workflow block reads correctly as GitOps | MAKE-03 | Prose readability | Read the updated workflow section — confirm no `kubectl apply` deploy references remain |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
