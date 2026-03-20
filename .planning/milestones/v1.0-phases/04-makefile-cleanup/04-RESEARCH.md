# Phase 4: Makefile Cleanup — Research

**Researched:** 2026-03-20
**Domain:** Makefile / Shell scripting, Flux CD CLI diagnostics, documentation hygiene
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MAKE-01 | `make deploy` target is removed — Flux is the sole deploy path | Makefile audit complete; `deploy` target and `ansible/playbooks/deploy.yaml` both identified; safe-removal approach documented |
| MAKE-02 | `make flux-status` (or similar) added for checking reconciliation state | Target already exists in current Makefile as `flux-status`; confirmed working pattern using `flux get all` |
| MAKE-03 | CLAUDE.md updated — diagnostic commands reference `flux get` instead of `kubectl apply` | Specific stale text in CLAUDE.md identified; replacement content documented |
</phase_requirements>

---

## Summary

Phase 4 is a cleanup and documentation phase — the largest technical risk is already resolved by completing Phase 3. The cluster is fully GitOps-managed by Flux; the `make deploy` target is now dead code that could mislead future operators into thinking manual applies are still valid.

The scope is narrow: one Makefile target to remove, one Ansible playbook to delete or archive, and one doc file (CLAUDE.md) to update. A secondary goal is updating README.md and SETUP.md, which also reference `make deploy` in cluster bring-up instructions. MAKE-03 names CLAUDE.md explicitly but the spirit of the requirement is that the imperative path is not documented anywhere as a current workflow.

**Primary recommendation:** Remove `make deploy` and `ansible/playbooks/deploy.yaml` entirely (they reference `k8s/` which no longer exists after Phase 3). Update CLAUDE.md to replace the stale workflow block with GitOps instructions and `flux get` diagnostic references. Touch README.md and SETUP.md to align cluster bring-up steps. No new Makefile infrastructure is needed — `make flux-status` and `make flux-reconcile` already exist.

---

## Current State Audit (HIGH confidence)

### What exists in the Makefile today

| Target | Status | Action Required |
|--------|--------|-----------------|
| `deploy` | Present — calls `ansible/playbooks/deploy.yaml` which applies `k8s/` (deleted in Phase 3) | Remove |
| `flux-status` | Present — runs `flux get all --kubeconfig $(KUBECONFIG)` | Keep as-is (satisfies MAKE-02) |
| `flux-reconcile` | Present — runs `flux reconcile source git` + `flux reconcile kustomization` | Keep as-is |
| `bootstrap-flux` | Present | Keep as-is |
| `status` | Present — runs `kubectl get nodes,pods,svc,pvc -A` | Keep as-is (cluster diagnostics, not deploy) |
| `generate`, `setup`, `install-k3s`, `logs`, `ssh-%` | Present | Keep as-is |

**MAKE-02 is already satisfied.** The `flux-status` target exists and correctly wraps `flux get all`. No new work needed on the Makefile beyond removing `deploy`.

### What exists in ansible/playbooks today

| File | Status | Action Required |
|------|--------|-----------------|
| `deploy.yaml` | Applies `k8s/` recursively via `kubectl apply -R -f` — `k8s/` no longer exists | Delete |
| `base-setup.yaml` | OS provisioning — keep | No change |
| `k3s-install.yaml` | K3s provisioning — keep | No change |
| `generate-configs.yaml` | Template rendering — keep | No change |

### What exists in documentation today

CLAUDE.md has two problems:

1. **Workflow table** (lines 13-19) lists `make deploy` as a current command
2. **Swapping the USB drive** section (lines 134-139) documents raw `kubectl` commands that bypass make — these are emergency-only procedures for a physical hardware operation. This warrants a note clarifying they are an exception, not a deploy path.

README.md line 68: `make deploy        # kubectl apply all k8s manifests` — needs removal/replacement.

SETUP.md line 93: `make deploy        # Apply all k8s manifests` in the Step 5 bring-up sequence — needs replacement with bootstrap-flux instruction and git-push-to-deploy note.

---

## Architecture Patterns

### Makefile Target Removal — Safe Approach

Removing a Makefile target is a one-line deletion. The `.PHONY` declaration must also be updated to remove `deploy` from the list (line 13 of current Makefile).

```makefile
# Before
.PHONY: help generate setup install-k3s deploy status logs bootstrap-flux flux-status flux-reconcile

# After
.PHONY: help generate setup install-k3s status logs bootstrap-flux flux-status flux-reconcile
```

No callers inside the repo depend on `make deploy` being runnable (the `k8s/` directory it applies no longer exists, so running it would fail anyway — the playbook path resolves to nothing).

### Defensive "Deploy Removed" Pattern (Optional)

Some teams replace the removed target with an error stub to give a clear message if someone muscle-memories `make deploy`:

```makefile
deploy: ## [REMOVED] Flux is the sole deploy path — push to main branch instead
	@echo "Error: make deploy has been removed. Flux manages all cluster state."
	@echo "To deploy: git commit && git push origin main"
	@echo "To check status: make flux-status"
	@exit 1
```

This is a judgment call. The error stub is friendlier but keeps the target name alive in help output (confusingly). Removing it entirely is cleaner and simpler — the success criteria says "absent from the Makefile" as an acceptable outcome. **Recommendation: remove entirely.**

### CLAUDE.md Documentation Pattern

The workflow section should be updated to reflect GitOps reality. The stale block to replace:

```bash
# Current (stale) — in CLAUDE.md lines 13-19
make generate     # Render all Jinja2 templates → cloud-init files, inventory, k8s manifests
make setup        # Ansible: base OS setup + USB mount + avahi (idempotent)
make install-k3s  # Ansible: install K3s server then agents (idempotent)
make deploy       # kubectl apply all k8s manifests          ← REMOVE THIS LINE
make status       # kubectl get nodes + pods
make ssh-<name>   # e.g. make ssh-the-bakery, make ssh-apple-pi
```

Replacement block adds Flux diagnostics:

```bash
make generate       # Render all Jinja2 templates → cloud-init files, inventory, k8s manifests
make setup          # Ansible: base OS setup + USB mount + avahi (idempotent)
make install-k3s    # Ansible: install K3s server then agents (idempotent)
make bootstrap-flux # Bootstrap Flux CD onto cluster (one-time, requires bw unlocked)
make status         # kubectl get nodes + pods + svc + pvc
make flux-status    # Show Flux reconciliation state for all resources
make flux-reconcile # Force immediate git sync (instead of waiting for 1-min poll)
make ssh-<name>     # e.g. make ssh-the-bakery, make ssh-apple-pi
```

A new subsection should document the GitOps deploy workflow explicitly:

```markdown
### Deploying workloads (GitOps path)

Push to `main` — Flux reconciles within 60 seconds:
```bash
git add charts/jellyfin/  # or whatever changed
git commit -m "feat: ..."
git push origin main
make flux-status          # watch reconciliation
```

For a manual trigger without waiting:
```bash
make flux-reconcile       # force immediate sync
make flux-status          # confirm READY=True
```

Diagnostic commands:
```bash
flux get all              # all Flux resources across namespaces
flux get helmreleases -A  # HelmRelease status
flux get sources git -A   # GitRepository polling status
flux logs                 # Flux controller event stream
```
```

The CRITICAL section about "Use make for everything" (lines 23-33) is still valid and should be kept — it correctly calls out that `kubectl apply` and `ansible-playbook` are wrong, and that changes should be encoded then applied via make. The only stale part is the mention of `make deploy` in the example list.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Checking Flux state | Custom kubectl queries | `flux get all` / `make flux-status` | Already exists; flux CLI formats output with READY status |
| Force reconcile | Manual kubectl patch | `flux reconcile` / `make flux-reconcile` | Already exists in Makefile |
| Deploy path | Any `kubectl apply` wrapper | `git push` | Flux handles it; any kubectl path creates dual authority |

---

## Common Pitfalls

### Pitfall 1: Leaving deploy.yaml in ansible/playbooks/

**What goes wrong:** The file continues to exist referencing a deleted `k8s/` directory. A future operator or Claude session might try to call it directly. It also creates false impression that the deploy playbook is a valid path.

**How to avoid:** Delete `ansible/playbooks/deploy.yaml` as part of MAKE-01. It has no valid use once `k8s/` is gone.

**Risk if skipped:** LOW — make deploy target is removed so no make command calls it, but the file lingers confusingly.

### Pitfall 2: Updating CLAUDE.md but not README.md or SETUP.md

**What goes wrong:** The success criteria specifies CLAUDE.md explicitly. README.md and SETUP.md both have `make deploy` in cluster bring-up instructions. If left stale, a fresh-setup operator following SETUP.md Step 5 would run `make deploy` and get an error (target missing) with no explanation.

**How to avoid:** Update all three files in a single plan. SETUP.md Step 5 should replace `make deploy` with `make bootstrap-flux` and a note that subsequent deploys happen via git push.

**Warning signs:** Grep for `make deploy` across all `.md` files after edits — should return zero results.

### Pitfall 3: Forgetting the .PHONY line

**What goes wrong:** The Makefile `.PHONY` declaration on line 13 includes `deploy`. If the target block is deleted but `.PHONY` is not updated, Make will emit a warning about the orphan declaration (or silently ignore it). It is not a functional bug but is messy.

**How to avoid:** Edit both the `.PHONY` declaration and the target block together.

### Pitfall 4: Breaking the help target

**What goes wrong:** The `help` target parses `## comment` suffixes. Removing `deploy` is safe. But if an editor accidentally corrupts the `## Show this help` comment on the `help` target, `make help` breaks entirely.

**How to avoid:** Verify `make help` output after edits.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual verification (no automated test framework for Makefile/docs) |
| Config file | none |
| Quick run command | `make help` — confirms no `deploy` target in output |
| Full suite command | `grep -r "make deploy" *.md` — confirms no stale references |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MAKE-01 | `make deploy` target absent from Makefile | smoke | `make deploy 2>&1 \| grep -i "no rule"` | ✅ Makefile exists |
| MAKE-01 | `ansible/playbooks/deploy.yaml` deleted | smoke | `ls ansible/playbooks/deploy.yaml 2>&1 \| grep "No such"` | ✅ exists pre-delete |
| MAKE-02 | `make flux-status` runs without error | smoke | `make flux-status` (requires live cluster + kubeconfig) | ✅ target already exists |
| MAKE-03 | CLAUDE.md has no `make deploy` reference | smoke | `grep "make deploy" CLAUDE.md` returns empty | ✅ CLAUDE.md exists |
| MAKE-03 | CLAUDE.md contains `flux get` commands | smoke | `grep "flux get" CLAUDE.md` returns matches | ✅ CLAUDE.md exists |

### Sampling Rate

- **Per task commit:** `make help` to verify help output is clean
- **Per wave merge:** `grep -r "make deploy" *.md` returns zero results
- **Phase gate:** All checks green before marking Phase 4 complete

### Wave 0 Gaps

None — no test infrastructure needed. All verification is shell-level smoke checks against existing files.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| `make deploy` → `kubectl apply -R -f k8s/` | `git push` → Flux reconcile | Eliminating dual authority; Flux provides lifecycle management including deletions |
| Imperative deploy with no rollback story | GitOps with git history as audit trail | Every cluster change is a git commit |
| `kubectl apply` is additive-only (no prune) | Flux prune: true removes resources deleted from git | Resource lifecycle fully managed |

---

## Open Questions

1. **Whether to update SETUP.md Step 5 to include bootstrap-flux**
   - What we know: SETUP.md documents the initial cluster bring-up sequence as `make setup` → `make install-k3s` → `make deploy`. With GitOps, after `make install-k3s` the correct next step is `make bootstrap-flux`, then `git push` handles workload deployment.
   - What's unclear: SETUP.md is a human-readable guide; bootstrap-flux requires Bitwarden unlock and GitHub App credentials. The guide may be out of scope for AI-driven changes if it requires explaining secret management setup.
   - Recommendation: Update SETUP.md Step 5 to say "run `make bootstrap-flux` (see README for credential setup)" and remove `make deploy`. Keep the sequence accurate even if the credential setup details are brief.

2. **Whether deploy.yaml should be deleted or moved to an archive**
   - What we know: The file references `k8s/` which no longer exists. It cannot be run successfully.
   - Recommendation: Delete it. Archiving adds complexity with no benefit — git history preserves it if ever needed.

---

## Sources

### Primary (HIGH confidence)

- Direct read of `Makefile` — current targets, `.PHONY` list, `deploy` target implementation
- Direct read of `ansible/playbooks/deploy.yaml` — confirms it applies `k8s/` which is gone
- Direct read of `CLAUDE.md` — exact lines that reference `make deploy`
- Direct read of `SETUP.md` and `README.md` — confirms `make deploy` in bring-up instructions
- Direct read of `.planning/REQUIREMENTS.md` — MAKE-01, MAKE-02, MAKE-03 definitions

### Secondary (MEDIUM confidence)

- `.planning/phases/03-migration-and-ownership-transfer/03-02-SUMMARY.md` — confirms Phase 3 complete and `make deploy` is now dead code
- `.planning/research/ARCHITECTURE.md` — prior research confirms intent: "Post-bootstrap, make deploy should be removed"

### Tertiary (LOW confidence)

- None — this phase requires no external research; all facts are observable from the repository itself

---

## Metadata

**Confidence breakdown:**

- Current state audit: HIGH — read directly from files
- Makefile edit mechanics: HIGH — standard Make syntax, no ambiguity
- Documentation scope (which files to update): HIGH — grep confirmed all occurrences
- MAKE-02 already satisfied: HIGH — `flux-status` target confirmed present in Makefile

**Research date:** 2026-03-20
**Valid until:** Not time-sensitive — no external dependencies; all facts are local to the repo
