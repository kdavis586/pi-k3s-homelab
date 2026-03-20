# Phase 3: Migration and Ownership Transfer — Research

**Researched:** 2026-03-20
**Domain:** Flux CD HelmRelease ownership transfer, Kubernetes field manager conflicts, GitOps prune enablement
**Confidence:** HIGH (based on official Flux docs + direct inspection of repo state)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MIG-01 | Existing kubectl-applied Jellyfin resources deleted and recreated under HelmRelease ownership (field manager conflict resolved) | Ownership transfer strategy documented; delete-and-reconcile is the clean approach; upgrade.force is the fallback |
| MIG-02 | Existing kubectl-applied Pi-hole resources deleted and recreated under HelmRelease ownership | Same as MIG-01; Pi-hole has an additional blocker: `workloads=true` node label must be applied first (see Blockers) |
| MIG-03 | `prune: true` re-enabled on the apps Kustomization after Flux owns all workload resources | Single-field change to `flux/flux-system/apps-kustomization.yaml`; timing (after ownership transfer) is critical |
| MIG-04 | Raw manifests in `k8s/jellyfin/` and `k8s/pihole/` deleted from the repo | `git rm -r` the two directories; once Flux is the owner, these files serve no purpose and are noise |
</phase_requirements>

---

## Summary

Phase 3 completes the GitOps migration. Flux controllers are already running (Phase 2 complete), the apps Kustomization is live with `prune: false`, and both HelmReleases exist in `flux/apps/`. The problem is that the live workloads — Jellyfin's Deployment/Service/PVC/IngressRoute and Pi-hole's DaemonSet/Service/IngressRoute — were applied imperatively via `kubectl apply` and carry kubectl's field manager. Helm/Flux has a different field manager. The cluster's resources have two potential owners, causing field manager conflicts that prevent Flux's HelmRelease from fully reconciling.

The cleanest resolution is a controlled delete-and-let-Flux-own approach: delete the raw kubectl-managed resources, then reconcile the HelmRelease so Flux installs them fresh with Helm as the sole field manager. For Jellyfin, this means a brief outage (~30–60 seconds for pod scheduling). For Pi-hole, the node label blocker must be resolved first, and the DNS/DHCP interruption window needs to be understood. After both HelmReleases reach `READY=True`, enabling `prune: true` on the apps Kustomization and deleting `k8s/jellyfin/` and `k8s/pihole/` from the repo completes the migration.

An alternative approach using `upgrade.force: true` in the HelmRelease spec allows Flux to forcibly take ownership without pre-deletion. This is less disruptive but can leave orphaned field manager entries and is best treated as a fallback if the delete approach causes unexpected issues.

**Primary recommendation:** Delete kubectl-managed resources per-namespace, trigger immediate Flux reconciliation, verify `READY=True`, then enable prune and remove raw manifests — in that exact order.

---

## Current State Assessment

This section captures the as-is cluster state that Phase 3 must transition FROM.

### What Flux already sees

Both HelmReleases exist in `flux/apps/` and are being reconciled by the apps Kustomization. However, because the live resources are already present with kubectl's field manager, Flux's Helm controller cannot fully "own" them. HelmRelease status may show:
- `upgrade retries exhausted` — Helm sees the resources but cannot reconcile fields it doesn't own
- Or the HelmReleases may show as READY (because Helm can apply most fields via SSA and win on delta reconciliation) but with potential drift on fields owned by kubectl

Per the Phase 2 summary, at bootstrap time:
- Pi-hole pod was **Pending** (pre-existing condition, 3d4h) — likely due to missing `homelab/node-group=workloads` label on nodes
- Jellyfin pod was **Running**

### Resource inventory: kubectl-owned resources to transfer

**Jellyfin namespace (`k8s/jellyfin/`):**
- `Namespace: jellyfin`
- `Deployment: jellyfin` (namespace: jellyfin)
- `Service: jellyfin` (namespace: jellyfin)
- `PersistentVolumeClaim: jellyfin-config` (namespace: jellyfin)
- `IngressRoute: jellyfin` (namespace: jellyfin) — Traefik CRD

**Pi-hole namespace (`k8s/pihole/`):**
- `Namespace: pihole`
- `DaemonSet: pihole` (namespace: pihole)
- `Service: pihole-web` (namespace: pihole) — ClusterIP on port 8080
- `IngressRoute: pihole` (namespace: pihole) — Traefik CRD
- Note: `k8s/pihole/service-dns.yaml` was already deleted from git (visible in git status as ` D k8s/pihole/service-dns.yaml`) — the LoadBalancer DNS service; this is a live resource the chart does NOT include (chart only has `service-web.yaml`)

### What the Helm charts include

**`charts/jellyfin/templates/`:** deployment, service, ingress (IngressRoute), namespace, pvc — complete overlap with `k8s/jellyfin/`

**`charts/pihole/templates/`:** daemonset, service-web, ingress (IngressRoute), namespace — does NOT include a DNS LoadBalancer service (that was the deleted `service-dns.yaml`)

### Critical gap: Pi-hole chart has no DNS Service

The raw `k8s/pihole/` had a `service-dns.yaml` (LoadBalancer for port 53 UDP/TCP) that is already deleted from git. The chart does NOT have this service. If this DNS LoadBalancer service is still live on the cluster, deleting it during ownership transfer will remove DNS from the LAN. This needs investigation before Phase 3 executes.

### Node label blocker

Pi-hole's DaemonSet uses `nodeAffinity` requiring `homelab/node-group=workloads`. According to `k3s-install.yaml`, node labels are applied via `make install-k3s`. The STATE.md confirms nodes are configured with `node_group: workloads` in `all.yaml`. The question is whether labels were actually applied — Pi-hole was Pending at Phase 2 completion. This must be resolved (apply labels via `make install-k3s` or targeted Ansible step) before Pi-hole ownership transfer.

---

## Architecture Patterns

### Pattern 1: Delete-then-Reconcile (Recommended)

**What:** Delete the kubectl-managed resources in a namespace. Flux's HelmRelease detects the resources are gone (or partially gone) and reinstalls from the Helm chart, becoming the sole field manager.

**Why this works:** Helm tracks releases via a Secret in the namespace (name: `sh.helm.release.v1.<name>.v1`). If the HelmRelease has never been installed by Flux's Helm controller (it exists in the cluster as an unattempted or failed install), deleting the live resources lets Flux do a clean `helm install` with Helm as the sole field manager from the start.

**Steps per workload:**
1. Scale down or delete the workload resources (Deployment/DaemonSet first to stop traffic, then others)
2. Force Flux to reconcile the HelmRelease immediately: `make flux-reconcile` or `flux reconcile hr <name>`
3. Watch HelmRelease status until `READY=True`
4. Verify workload is accessible

**For Jellyfin specifically:** Delete the Deployment (pod goes away), Service, IngressRoute. The PVC must NOT be deleted — it holds Jellyfin's config and cannot be recreated by Helm (Helm does not delete PVCs on uninstall by default, but we need to keep the existing one). The chart will reference the same PVC name (`jellyfin-config`) so Flux will bind to the existing PVC.

**For Pi-hole specifically:** Delete DaemonSet, Service(s), IngressRoute. The DaemonSet deletion causes DNS/DHCP interruption on the LAN. Keep the window short.

### Pattern 2: upgrade.force (Fallback)

**What:** Set `upgrade.force: true` in the HelmRelease spec. This tells Helm to delete and recreate resources during upgrade, forcibly taking ownership.

**When to use:** If delete-then-reconcile leaves orphaned Helm release Secrets that cause "release already exists" errors, or if the HelmRelease is stuck in an error state after cleanup.

**How to configure:**
```yaml
spec:
  upgrade:
    force: true
    cleanupOnFail: true
```

This is already set: `cleanupOnFail: true` exists in both HelmReleases. Adding `force: true` to upgrade is the only addition needed for this fallback.

### Pattern 3: Helm Annotation Adoption (Alternative, more complex)

**What:** Add Helm ownership annotations to existing resources so Helm thinks it already owns them, then run a forced reconciliation.

**Annotations needed:**
```bash
kubectl annotate <resource> meta.helm.sh/release-name=<name> meta.helm.sh/release-namespace=flux-system
kubectl label <resource> app.kubernetes.io/managed-by=Helm
```

**Why to avoid:** Requires annotating every resource individually, error-prone, leaves field manager confusion. Not recommended for this project.

### Pattern 4: Prune Enablement (after ownership transfer)

**What:** Change `prune: false` to `prune: true` in `flux/flux-system/apps-kustomization.yaml`.

**Critical timing:** Only enable prune AFTER both HelmReleases are `READY=True`. If prune is enabled while kubectl-managed resources still exist and the HelmRelease hasn't taken ownership, Flux may delete resources it cannot recreate.

**Effect after enablement:** Any resource that was in `flux/apps/` (or transitively applied by the Kustomization) that is removed from git will be pruned from the cluster on next reconcile. This is the desired end state: git is the sole source of truth.

**How to enable:**
```yaml
# flux/flux-system/apps-kustomization.yaml
spec:
  prune: true  # was false
```

---

## Critical Blockers (Must Resolve Before Phase 3)

### Blocker 1: Pi-hole node labels

Pi-hole DaemonSet requires `homelab/node-group=workloads` on nodes. If this label is not present, the Pi-hole pod cannot schedule and the HelmRelease will never reach `READY=True`.

**Verify current state:**
```bash
kubectl get nodes --show-labels --kubeconfig ~/.kube/config-pi-k3s | grep homelab
```

**Fix if missing:** `make install-k3s` re-applies node labels (idempotent). This is safe to run. Alternatively, the label can be applied via the Ansible playbook's label task.

### Blocker 2: DNS Service gap (investigate before execution)

`k8s/pihole/service-dns.yaml` exists on disk in the working tree as deleted (`git status` shows ` D`). This means the file is staged for deletion but may still be live on the cluster. The Pi-hole chart does NOT include a DNS LoadBalancer service.

**Questions to answer before executing:**
1. Is the `pihole-dns` LoadBalancer Service currently live on the cluster?
2. If yes, was it applied via `make deploy` from the old manifest?
3. If yes, does removing it break LAN DNS (since Pi-hole uses `hostNetwork: true`, LAN DNS might work via host IP without the LoadBalancer)?

**Hypothesis:** With `hostNetwork: true`, Pi-hole binds port 53 directly on the host IP. The LoadBalancer service was an additional klipper-lb exposure. Removing the LoadBalancer may not break DNS if clients were configured to point at node IPs directly. Must verify before proceeding.

### Blocker 3: Jellyfin PVC preservation

The `jellyfin-config` PVC holds Jellyfin's library database and configuration. It must NOT be deleted during ownership transfer. The Helm chart will reference the same PVC name, so the existing PV binding will be preserved as long as the PVC object itself is not deleted.

**Approach:** During deletion, skip the PVC. Delete only: Deployment, Service, IngressRoute. Let Flux's helm install create a new PVC spec — but since a PVC with that name already exists, Helm will adopt it (PVCs are not replaced on `helm install` if they already exist and match the release).

**Risk:** If the chart's PVC spec differs from the existing PVC (e.g., different storage class, access modes), the install will fail. Verify the chart's PVC template matches the live PVC spec.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Force Flux to reconcile immediately | Don't edit HelmRelease timestamps | `flux reconcile hr <name> --kubeconfig ...` | Built-in CLI command |
| Check field manager ownership | Don't parse YAML manually | `kubectl get <res> -o yaml --show-managed-fields` | Native kubectl output |
| Verify HelmRelease health | Don't kubectl describe every resource | `flux get helmreleases -A --kubeconfig ...` | Flux-native status |
| Apply node labels | Don't run kubectl label directly | `make install-k3s` (Ansible handles this idempotently) | CLAUDE.md: all cluster ops via make |
| Enable prune after ownership | Don't use kubectl patch | Edit `flux/flux-system/apps-kustomization.yaml` and push to main | Flux reconciles from git |

---

## Common Pitfalls

### Pitfall 1: Enabling prune before ownership transfer completes

**What goes wrong:** If `prune: true` is set while kubectl-managed resources exist AND the HelmRelease is not yet `READY`, Flux may delete resources on next reconcile that it doesn't yet own via Helm — removing them from the cluster without Helm being able to reinstall them.

**How to avoid:** Gate `prune: true` change strictly after `flux get helmreleases -A` shows `READY=True` for both workloads.

**Warning signs:** HelmRelease stuck in `install retries exhausted` AND prune is enabled.

### Pitfall 2: Deleting the Jellyfin PVC

**What goes wrong:** Jellyfin's library metadata, settings, and scan database are stored in the config PVC. If deleted, all library data is lost and Jellyfin starts fresh (re-scan required, which takes hours).

**How to avoid:** During the delete step, explicitly do NOT delete the PVC. Delete Deployment, Service, IngressRoute only.

### Pitfall 3: Pi-hole DNS/DHCP interruption window

**What goes wrong:** Deleting the Pi-hole DaemonSet stops DNS and DHCP on the LAN. Devices with DHCP leases will retain their IPs temporarily, but new requests fail. If the interruption window is too long, LAN connectivity may degrade.

**How to avoid:** Pre-stage: verify node labels are applied, verify chart values match live config, test `helm template` renders correctly. Execute the delete + reconcile in one fast sequence to minimize downtime. Have the `flux reconcile` command ready to run immediately after delete.

**Expected window:** ~30–90 seconds for Flux to detect changes, schedule the DaemonSet pod, and for the Pi-hole container to start.

### Pitfall 4: Helm release Secret conflict ("release already exists")

**What goes wrong:** If Flux's Helm controller previously attempted and partially completed an install, there may be a Helm release Secret (`sh.helm.release.v1.<name>.v1`) in the namespace. Trying to install again causes "release already exists" error.

**How to avoid:** Check for existing Helm release Secrets before proceeding:
```bash
kubectl get secrets -n jellyfin --kubeconfig ~/.kube/config-pi-k3s | grep helm.release
kubectl get secrets -n pihole --kubeconfig ~/.kube/config-pi-k3s | grep helm.release
```

If one exists, Helm will do an upgrade (not install), which is fine. If it doesn't exist and the resources are still there, use `upgrade.force: true` or delete resources first.

### Pitfall 5: flux_version mismatch in all.yaml

The STATE.md notes that Flux installed v2.8.3 but `all.yaml` still has `flux_version: "v2.4.0"`. This doesn't affect Phase 3 execution, but should be noted: the `make bootstrap-flux` target uses a dynamic version detection now so this is likely harmless. Still worth updating `flux_version` in `all.yaml` to `v2.8.3` for accuracy.

### Pitfall 6: Pi-hole chart missing DNS service (k8s/pihole/service-dns.yaml)

**What goes wrong:** The deleted-from-git `service-dns.yaml` may still be a live resource on the cluster. When `k8s/pihole/` is removed from the repo (MIG-04), if the DNS Service is still cluster-live and prune is enabled, Flux will attempt to prune it — but since it wasn't applied by Flux it may be left as an orphan or cause confusion.

**How to avoid:** Before MIG-04, explicitly check if `pihole-dns` Service exists on cluster. If it does and it's needed, it should be added to the Pi-hole chart before MIG-04. If it's not needed (hostNetwork covers DNS), delete it manually and proceed.

---

## Code Examples

### Check current HelmRelease status
```bash
# Source: Flux CLI documentation
flux get helmreleases -A --kubeconfig ~/.kube/config-pi-k3s
```

### Check field managers on a resource
```bash
# Source: kubectl documentation
kubectl get deployment jellyfin -n jellyfin \
  -o yaml --show-managed-fields \
  --kubeconfig ~/.kube/config-pi-k3s
```

### Check for existing Helm release Secrets
```bash
kubectl get secrets -n jellyfin --kubeconfig ~/.kube/config-pi-k3s | grep helm.release
kubectl get secrets -n pihole --kubeconfig ~/.kube/config-pi-k3s | grep helm.release
```

### Delete Jellyfin resources (preserve PVC)
```bash
# Delete workload + networking resources — NOT the PVC
kubectl delete deployment jellyfin -n jellyfin --kubeconfig ~/.kube/config-pi-k3s
kubectl delete service jellyfin -n jellyfin --kubeconfig ~/.kube/config-pi-k3s
kubectl delete ingressroute jellyfin -n jellyfin --kubeconfig ~/.kube/config-pi-k3s
# DO NOT: kubectl delete pvc jellyfin-config -n jellyfin
```

### Delete Pi-hole resources
```bash
kubectl delete daemonset pihole -n pihole --kubeconfig ~/.kube/config-pi-k3s
kubectl delete service pihole-web -n pihole --kubeconfig ~/.kube/config-pi-k3s
kubectl delete ingressroute pihole -n pihole --kubeconfig ~/.kube/config-pi-k3s
```

### Force immediate Flux reconciliation
```bash
# Source: Flux CLI documentation
flux reconcile helmrelease jellyfin -n flux-system --kubeconfig ~/.kube/config-pi-k3s
flux reconcile helmrelease pihole -n flux-system --kubeconfig ~/.kube/config-pi-k3s
```

### Enable prune on apps Kustomization
```yaml
# flux/flux-system/apps-kustomization.yaml — change one field
spec:
  prune: true  # was: false
```
After committing and pushing this change, Flux picks it up on next sync (within 10 minutes, or force with `make flux-reconcile`).

### Verify node labels
```bash
kubectl get nodes --show-labels --kubeconfig ~/.kube/config-pi-k3s | grep homelab
```

### Remove raw manifests from repo (MIG-04)
```bash
git rm -r k8s/jellyfin/ k8s/pihole/
git commit -m "chore: remove kubectl-managed raw manifests — Flux owns all workloads"
git push origin main
```

### Add upgrade.force if needed (fallback)
```yaml
# flux/apps/jellyfin.yaml — add to spec.upgrade
spec:
  upgrade:
    force: true
    cleanupOnFail: true
```

---

## Execution Order

The order within Phase 3 is critical:

1. **Pre-flight checks** — Verify node labels, check HelmRelease current status, check for DNS service gap
2. **Jellyfin ownership transfer (MIG-01)** — Delete kubectl resources, reconcile, verify READY=True and accessibility
3. **Pi-hole ownership transfer (MIG-02)** — Apply node labels if needed, delete kubectl resources, reconcile, verify READY=True and accessibility
4. **Enable prune (MIG-03)** — Change `prune: false` → `prune: true` in apps-kustomization, push to main, verify reconcile
5. **Remove raw manifests (MIG-04)** — `git rm -r k8s/jellyfin/ k8s/pihole/`, commit, push

**Why this order matters:**
- Doing Jellyfin first is safer (no network-critical DNS dependency, just media playback)
- Pi-hole ownership transfer interrupts LAN DNS; keeping this step focused reduces risk
- Prune MUST come after both workloads are Flux-owned, not before
- Raw manifest removal comes last — they're harmless in git while prune is still false, and removing them before prune is enabled avoids any edge case where Flux might try to prune non-Flux-owned resources

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual verification via Flux CLI + HTTP checks |
| Config file | None — no automated test suite in this repo |
| Quick run command | `flux get helmreleases -A --kubeconfig ~/.kube/config-pi-k3s` |
| Full suite command | See Phase Requirements → Test Map below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIG-01 | Jellyfin HelmRelease READY=True, no field manager conflicts | smoke | `flux get hr jellyfin -n flux-system --kubeconfig ~/.kube/config-pi-k3s` | N/A — CLI output |
| MIG-01 | Jellyfin accessible at http://jellyfin.local | manual | `curl -s -o /dev/null -w "%{http_code}" http://jellyfin.local` | N/A |
| MIG-02 | Pi-hole HelmRelease READY=True | smoke | `flux get hr pihole -n flux-system --kubeconfig ~/.kube/config-pi-k3s` | N/A |
| MIG-02 | Pi-hole web UI accessible | manual | `curl -s -o /dev/null -w "%{http_code}" http://192.168.1.100/pihole` (or via Traefik route) | N/A |
| MIG-03 | prune: true active on apps Kustomization | smoke | `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.prune}' --kubeconfig ~/.kube/config-pi-k3s` | N/A |
| MIG-04 | k8s/jellyfin/ and k8s/pihole/ absent from repo | unit | `ls k8s/` — must not show jellyfin or pihole | N/A |

### Wave 0 Gaps

None — this phase has no automated test infrastructure to scaffold. All verification is via Flux CLI commands and manual HTTP checks. No test files need to be created before execution.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual kubectl apply for all resources | Flux HelmRelease GitOps | Phase 2 complete | Push to main deploys |
| prune: false (guard against deletion) | prune: true (full GitOps) | Phase 3 goal | Git is sole source of truth |
| Raw manifests in k8s/ | Helm charts in charts/ | Phase 1 complete | Parameterized, versioned |
| Field manager: kubectl | Field manager: helm | Phase 3 goal | No more SSA conflicts |

---

## Open Questions

1. **Is the `pihole-dns` LoadBalancer Service live on the cluster?**
   - What we know: `k8s/pihole/service-dns.yaml` is deleted from git (git status shows ` D`). The Pi-hole chart has no equivalent template.
   - What's unclear: Was this service ever applied to the cluster via `make deploy`? Is it still live? Does removing it break LAN DNS?
   - Recommendation: First task in Phase 3 should verify: `kubectl get svc pihole-dns -n pihole --kubeconfig ~/.kube/config-pi-k3s`. If it exists and LAN DNS depends on it, the chart needs a dns-service template before proceeding with ownership transfer.

2. **Do node labels `homelab/node-group=workloads` currently exist on agent nodes?**
   - What we know: `k3s-install.yaml` applies them via `kubectl label node`. STATE.md notes Pi-hole was Pending at Phase 2 (pre-existing 3d4h).
   - What's unclear: Were labels applied during the last `make install-k3s`? Are they present now?
   - Recommendation: Pre-flight check with `kubectl get nodes --show-labels` before Pi-hole ownership transfer. Fix via `make install-k3s` if missing.

3. **What is the current HelmRelease status for jellyfin and pihole?**
   - What we know: Bootstrap completed successfully. HelmReleases exist in flux/apps/ and the apps Kustomization is active.
   - What's unclear: Whether Flux's Helm controller has already attempted install (which would create Helm release Secrets) or is waiting/failing.
   - Recommendation: `flux get helmreleases -A` at the start of Phase 3 to determine current state before any deletion.

---

## Sources

### Primary (HIGH confidence)
- [Flux HelmReleases docs](https://fluxcd.io/flux/components/helm/helmreleases/) — upgrade.force, serverSideApply, cleanupOnFail behavior
- [Flux Helm Releases guide](https://fluxcd.io/flux/guides/helmreleases/) — HelmRelease authoring patterns
- [Flux Troubleshooting Cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/) — debug commands
- [Flux FAQ](https://fluxcd.io/flux/faq/) — resource management and ownership semantics
- Direct inspection of repo files: `flux/apps/`, `flux/flux-system/apps-kustomization.yaml`, `charts/`, `k8s/` — HIGH confidence, directly read

### Secondary (MEDIUM confidence)
- [fluxcd/helm-controller issue #593](https://github.com/fluxcd/helm-controller/issues/593) — confirmation that Flux 2.4+ supports adopting existing resources; matches this project's Flux v2.8.3
- [Flux Helm Operator migration guide](https://fluxcd.io/flux/migration/helm-operator-migration/) — upgrade-first vs delete-first migration strategies

### Tertiary (LOW confidence)
- WebSearch results on field manager conflict patterns — cross-referenced with official docs, elevated to MEDIUM for SSA and `upgrade.force` claims

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Flux v2.8.3 confirmed installed, HelmRelease CRDs confirmed at v2 (helm.toolkit.fluxcd.io/v2)
- Architecture (ownership transfer pattern): HIGH — documented in official Flux sources; repo state directly inspected
- Pitfalls: HIGH for PVC and prune-ordering risks (repo-verified); MEDIUM for DNS service gap (requires live cluster verification)
- Open questions: Require live cluster verification before execution

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable tooling, 30-day window)
