# Pitfalls Research

**Domain:** Flux CD GitOps migration on K3s (Raspberry Pi homelab)
**Researched:** 2026-03-18
**Confidence:** HIGH (multiple official Flux docs + verified community issues)

---

## Critical Pitfalls

### Pitfall 1: prune:true Deletes Everything on First Kustomization Reconcile

**What goes wrong:**
The existing `gotk-sync.yaml` has `prune: true` and `path: ./k8s`. The moment Flux reconciles this Kustomization, it compares what's in `./k8s` against its own inventory. Since Flux has never applied these resources itself (kubectl applied them), its inventory is empty. Flux sees all existing resources as "not in git" and deletes them — Jellyfin and Pi-hole disappear from the cluster.

**Why it happens:**
Flux's garbage collection works off its own inventory, not the live cluster state. Resources applied via `kubectl apply` have no Flux inventory entry. To Flux, they simply don't exist in git yet.

**How to avoid:**
Start with `prune: false` on all Kustomizations during the migration phase. Only enable `prune: true` after Flux has successfully applied (and thus inventoried) all resources at least once. This is a two-step process: first reconcile with pruning disabled, verify everything is owned by Flux, then re-enable pruning.

**Warning signs:**
- Flux reconcile succeeds but pods are suddenly missing
- `flux get kustomizations` shows zero or low resource counts on first sync
- Namespace resources disappear immediately after bootstrap

**Phase to address:**
Bootstrap / Flux installation phase — set `prune: false` before any reconciliation occurs; only enable after full migration is verified.

---

### Pitfall 2: HelmRelease Fails to Adopt kubectl-Applied Resources (Field Manager Conflict)

**What goes wrong:**
Converting the Jellyfin and Pi-hole raw manifests to HelmReleases while those resources already exist in the cluster (applied via `kubectl apply`) causes a field manager ownership conflict. Helm controller attempts server-side apply but finds fields already owned by the `kubectl` field manager. The HelmRelease enters a `upgrade retries exhausted` failure loop without touching the live workload.

**Why it happens:**
Kubernetes server-side apply tracks which controller "owns" each field. `kubectl apply` sets the manager to `kubectl`. Helm controller (Flux) tries to claim the same fields — the API server rejects the conflict unless forced.

**How to avoid:**
Before creating HelmReleases, delete the existing raw-manifest resources (or use `kubectl annotate` to pre-stamp them with Helm ownership metadata). The cleanest path for this cluster: `kubectl delete` the existing Deployments/DaemonSets in the `jellyfin` and `pihole` namespaces, then let the HelmRelease recreate them. Jellyfin has a Recreate strategy so downtime is brief. Alternatively, add `upgrade.force: true` to HelmRelease specs to force ownership transfer.

**Warning signs:**
- HelmRelease status shows `upgrade retries exhausted`
- `kubectl describe helmrelease` shows `Apply failed: ... field is owned by manager "kubectl"`
- Existing pods keep running unchanged while HelmRelease reports failure

**Phase to address:**
Helm chart authoring phase — plan for resource adoption before creating HelmRelease CRs; document the delete-then-recreate approach in the migration runbook.

---

### Pitfall 3: K3s HelmChart CRD Ambiguity Breaks Flux Diagnostics

**What goes wrong:**
K3s ships its own Helm controller with a `HelmChart` CRD under `helm.cattle.io/v1`. Flux creates `HelmChart` resources under `helm.toolkit.fluxcd.io/v1`. Running `kubectl get helmcharts` returns K3s HelmChart resources, not Flux ones. You'll see no entries and conclude Flux isn't working — but Flux's charts exist under the other API group and are reconciling fine. This wastes debugging time.

**Why it happens:**
kubectl resolves CRD shortnames by alphabetical preference when two CRDs share the same plural name. `helm.cattle.io` wins over `helm.toolkit.fluxcd.io` alphabetically.

**How to avoid:**
Always use fully qualified resource names when debugging: `kubectl get helmcharts.helm.toolkit.fluxcd.io -A` for Flux charts, or use `flux get sources chart -A` which avoids the ambiguity entirely. Add this note to any runbook or CLAUDE.md debugging section.

**Warning signs:**
- `kubectl get helmcharts -A` shows only K3s system charts (traefik, coredns, local-path-provisioner) but no application charts
- You conclude HelmCharts weren't created when they actually were
- `flux get sources chart -A` shows items that `kubectl get helmcharts -A` doesn't

**Phase to address:**
Bootstrap phase — document the correct diagnostic commands before any troubleshooting is attempted.

---

### Pitfall 4: GitRepository Uses HTTPS While Repo Is Private — Flux Reconcile Hangs

**What goes wrong:**
The existing `gotk-sync.yaml` specifies `url: https://github.com/kdavis586/pi-k3s-homelab` with no `secretRef`. If this repo is or becomes private, Flux's source controller will fail to clone and hang in `GitFetchFailed` indefinitely. If it's public, HTTPS works — but the intended auth method is SSH deploy key, and these two are not interchangeable: switching from HTTPS to SSH requires changing the URL format to `ssh://git@github.com/kdavis586/pi-k3s-homelab`, not just adding a secretRef to the existing HTTPS URL.

**Why it happens:**
SSH secrets contain a private key — they only work with `ssh://` URLs. HTTPS secrets contain a username/password or token. Mixing URL scheme and secret type silently fails rather than giving a clear error.

**How to avoid:**
When using SSH deploy key auth: use `ssh://git@github.com/owner/repo` URL format, create a Kubernetes Secret in `flux-system` namespace containing the SSH private key, and reference it via `secretRef`. Run `flux bootstrap git --url=ssh://git@github.com/...` to generate the correct manifests rather than hand-authoring the GitRepository.

**Warning signs:**
- `flux get sources git` shows `GitFetchFailed: authentication required`
- The GitRepository status shows 401 or "repository not found" errors
- SSH key was created but GitRepository URL still starts with `https://`

**Phase to address:**
Bootstrap phase — validate the URL scheme matches the auth method before running `make install-k3s`.

---

### Pitfall 5: Local Helm Chart Changes Don't Trigger Reconcile (reconcileStrategy Default)

**What goes wrong:**
After converting workloads to local Helm charts in `charts/jellyfin/` and `charts/pihole/`, editing chart templates and pushing to main produces no cluster change. The HelmRelease appears healthy but is running stale chart content. This is silent — no error, no event, nothing.

**Why it happens:**
For HelmCharts sourced from a GitRepository, the default `reconcileStrategy` is `ChartVersion`. Flux only considers the chart updated when the `version:` field in `Chart.yaml` increments. A commit that changes template files without bumping the chart version is invisible to Flux's helm controller.

**How to avoid:**
Set `reconcileStrategy: Revision` on HelmChart specs (via the HelmRelease's `chart.spec.reconcileStrategy` field). This triggers reconciliation on any GitRepository revision change, regardless of chart version. For a homelab with no versioning discipline, this is the correct default.

**Warning signs:**
- Push to main, `flux get kustomizations` shows the GitRepository updated, but `flux get helmreleases` shows no new revision
- Chart templates clearly changed but pods haven't restarted
- `flux get sources chart` shows an old revision timestamp despite recent commits

**Phase to address:**
Helm chart authoring phase — include `reconcileStrategy: Revision` in the HelmRelease template from the start.

---

### Pitfall 6: Traefik Port 80 Conflict Breaks Pi-hole Web UI on hostNetwork Pods

**What goes wrong:**
Pi-hole uses `hostNetwork: true`. When the Pi-hole pod runs on a node that also runs Traefik (all nodes via DaemonSet), Traefik's iptables rules intercept port 80 traffic at the node level. This is already handled in the existing manifest by using `FTLCONF_webserver_port: 8080`. If the Helm chart migration omits this env var or resets it to the default (80), Pi-hole's web UI silently breaks — the pod starts healthy but HTTP requests to port 80 are hijacked by Traefik and return a 404 from the wrong upstream.

**Why it happens:**
`hostNetwork: true` means the pod shares the node's network namespace. Traefik's iptables rules apply at the node level regardless of Kubernetes networking. Any process on the host binding port 80 competes with Traefik.

**How to avoid:**
The Helm chart values for Pi-hole must expose `webserverPort` as a configurable value, default it to `8080`, and carry the `FTLCONF_webserver_port` env var through to the container spec. Include this in chart values validation during authoring.

**Warning signs:**
- Pi-hole pod is Running but web UI returns unexpected responses
- `flux get helmreleases` shows healthy but accessing Pi-hole web UI fails
- Traefik logs show 404s for Pi-hole paths

**Phase to address:**
Pi-hole Helm chart authoring — explicitly validate port configuration in chart values and test Pi-hole web UI access after first HelmRelease deployment.

---

### Pitfall 7: Flux Kustomization Watches `./k8s` — Jinja2-Generated Files Create Dual-Authority Conflict

**What goes wrong:**
The current `gotk-sync.yaml` points Flux at `path: ./k8s`. Some files in `./k8s` are generated by `make generate` from Jinja2 templates in `ansible/`. After migration, if someone runs `make generate` and commits changed files under `./k8s`, Flux will attempt to reconcile those generated files. But if those files are plain manifests (not HelmRelease CRs), Flux applies them directly — bypassing the Helm chart layer. Two conflicting authorities now manage the same workloads: Helm controller via HelmRelease, and kustomize controller via raw YAML.

**Why it happens:**
`make generate` was designed before GitOps existed in this repo. The generated output still lives where Flux watches. The migration removes `make deploy` but `make generate` still commits files to Flux's watch path.

**How to avoid:**
During migration, either: (a) move all Flux HelmRelease/Kustomization CRs to a new path (e.g., `./k8s/flux/`) and update the Kustomization `path` accordingly, so generated manifests under `./k8s/jellyfin/` are not in Flux's reconcile scope; or (b) delete all raw manifests from `./k8s/jellyfin/` and `./k8s/pihole/` after converting to Helm charts, making `make generate` output charts rather than raw YAML. Option (b) is cleaner — it eliminates the parallel authority entirely.

**Warning signs:**
- Helm controller shows HelmRelease healthy but kustomize controller also shows resources from the same namespace
- `kubectl get deployment jellyfin -n jellyfin -o yaml` shows both Helm labels and kubectl annotations
- Running `make generate` after deployment causes unexpected pod restarts

**Phase to address:**
Flux bootstrap phase — finalize the directory structure before committing any HelmRelease CRs; ensure `path:` in the Kustomization points only at Flux-owned files.

---

### Pitfall 8: Flux Bootstrap Ordering — CRDs Not Ready When Kustomization Applies CRs

**What goes wrong:**
On a fresh cluster install (or re-bootstrap after disaster), Flux installs its own controllers first, which include CRDs for `HelmRelease`, `GitRepository`, etc. The Kustomization at `./k8s` immediately tries to apply HelmRelease CRs. If the Helm controller hasn't finished starting up, the API server returns `no matches for kind HelmRelease` and the Kustomization fails. Flux retries, but on Raspberry Pi 4s with limited RAM the retry window can be several minutes.

**Why it happens:**
Flux bootstrap is designed to be idempotent, but the first application of the `flux-system` Kustomization happens before the Helm controller pod reaches `Ready`. The kustomize controller applies CRs before the CRDs they depend on are fully established.

**How to avoid:**
This is generally self-healing — Flux retries and eventually succeeds once controllers are ready. However, to reduce noise: use `dependsOn` in app-level Kustomizations to express that app workloads depend on the `flux-system` Kustomization. Also: on Pi hardware, give the cluster 3-5 minutes after bootstrap before assessing health.

**Warning signs:**
- `flux get kustomizations` shows `ReconciliationFailed: no matches for kind HelmRelease` immediately after bootstrap
- Errors clear after 5-10 minutes as controllers finish starting
- Running `kubectl get pods -n flux-system` shows controllers still in `ContainerCreating`

**Phase to address:**
Bootstrap phase — document the expected delay on Pi hardware; add `dependsOn: [{name: flux-system}]` to app Kustomizations.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `prune: false` permanently | No accidental deletions | Orphaned resources accumulate silently; Flux no longer owns cluster state | Never — enable pruning after initial migration is confirmed |
| Leave Jinja2-generated files in Flux's watch path | Avoids refactoring `make generate` | Dual authority between Flux and make; reconcile conflicts on every `make generate` | Never — resolve path boundaries before enabling Flux |
| Use `reconcileStrategy: ChartVersion` (default) | No accidental reconciles | Local chart changes silently don't deploy; forces artificial version bumps | Never for a homelab with local charts |
| Skip deleting old kubectl-applied resources | No service downtime during migration | HelmRelease enters `upgrade retries exhausted` loop; chart is never actually applied | Only if using `upgrade.force: true` and accepting the risk |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| K3s HelmChart CRD | `kubectl get helmcharts` returns K3s charts, not Flux charts | Use `kubectl get helmcharts.helm.toolkit.fluxcd.io -A` or `flux get sources chart -A` |
| Traefik (K3s built-in) + Pi-hole hostNetwork | Pi-hole binds port 80, Traefik intercepts it | Set `FTLCONF_webserver_port=8080` in chart values; already done in existing manifest — must carry through to Helm chart |
| exFAT mount + Helm chart volume spec | Using `chown` or Unix ownership in chart init containers fails silently on exFAT | Preserve `uid=0,gid=0,umask=000` mount options; never add `defaultMode`, `fsGroup`, or `runAsUser` to volumes backed by exFAT |
| SSH deploy key + HTTPS URL | Create SSH key secret but leave GitRepository URL as `https://` | URL must be `ssh://git@github.com/...` when using SSH key auth |
| Flux Kustomization `prune: true` + renaming Kustomization | Renaming a Kustomization triggers deletion of all its managed resources before recreation | Always set `prune: false` before renaming a Kustomization, sync, then re-enable |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Flux reconcile interval too short on Pi hardware | Excessive CPU usage on `the-bakery` (4GB control plane); scheduler contention | Keep default `interval: 10m` for Kustomizations; `1m` is acceptable for GitRepository source only | Immediately on Pi 4 with 4GB RAM under load |
| Jellyfin `image: latest` tag | Flux doesn't detect image updates without Image Automation (out of scope) | Pin image to a specific version tag; document update process | Every time the latest tag points to a new image after a node restart |
| Large Helm chart values file in GitRepository | Slows chart reconciliation; increases git clone size | Keep values lean; extract large config blobs to ConfigMaps separately | Not an issue at homelab scale |

---

## "Looks Done But Isn't" Checklist

- [ ] **Flux bootstrap:** `flux get kustomizations -A` shows `Ready=True` — verify it's not stuck in retry loop. Check `flux get helmreleases -A` separately; kustomization health does not imply HelmRelease health.
- [ ] **SSH auth:** Deploy key added to GitHub repo with read-only access — verify Flux can actually pull by checking `flux get sources git -A` shows `Fetched revision: main/...`.
- [ ] **Pi-hole hostNetwork:** Pod is Running — verify DNS actually resolves from a non-cluster device (`nslookup google.com 192.168.1.101`) and DHCP leases are being issued.
- [ ] **Jellyfin node affinity:** Pod is Running — verify it scheduled on `apple-pi` specifically (`kubectl get pod -n jellyfin -o wide`) and not on another node that lacks the USB mount.
- [ ] **exFAT volume:** Jellyfin pod starts — verify `/media` directory inside the container is readable (`kubectl exec -n jellyfin ... -- ls /media`); a wrong mount option silently mounts an empty directory.
- [ ] **prune: true enabled:** Enabled after migration — verify by removing a test ConfigMap from git and confirming Flux deletes it from the cluster within one reconcile interval.
- [ ] **make deploy removed:** Confirm `make deploy` target is deleted from Makefile and no CI/CD path calls `kubectl apply` directly.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| prune:true deletes live workloads | MEDIUM | Immediately `kubectl apply -f k8s/jellyfin/` and `k8s/pihole/` to restore; set `prune: false` on Kustomization; replan migration |
| HelmRelease field manager conflict | LOW | Delete conflicting resources (`kubectl delete deployment jellyfin -n jellyfin`); HelmRelease recreates them on next reconcile |
| GitRepository auth failure (wrong URL scheme) | LOW | Edit GitRepository URL from `https://` to `ssh://`; commit and push; Flux picks up change |
| K3s re-bootstrap wipes flux-system namespace | MEDIUM | Re-run `flux bootstrap git ...` (idempotent); Flux re-applies its own manifests and re-reconciles app state from git |
| Local chart changes not deploying | LOW | Add `reconcileStrategy: Revision` to HelmRelease chart spec; force reconcile with `flux reconcile helmrelease <name> -n <ns>` |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| prune:true deletes existing resources | Phase 1: Flux Bootstrap | Confirm `prune: false` in all Kustomizations before first reconcile |
| HelmRelease field manager conflict | Phase 2–3: Helm Chart Authoring | Delete raw resources before creating HelmRelease; verify HelmRelease reaches `Ready` state |
| K3s HelmChart CRD ambiguity | Phase 1: Flux Bootstrap | Document `flux get sources chart` as the canonical diagnostic command |
| GitRepository HTTPS vs SSH URL mismatch | Phase 1: Flux Bootstrap | Validate `flux get sources git` shows fetched revision, not auth error |
| reconcileStrategy default prevents chart updates | Phase 2–3: Helm Chart Authoring | Include `reconcileStrategy: Revision` in HelmRelease template; push a trivial chart change to verify redeploy |
| Traefik/Pi-hole port 80 conflict | Phase 3: Pi-hole Helm Chart | Access Pi-hole web UI at port 8080 after first HelmRelease deployment |
| Jinja2-generated files in Flux watch path | Phase 1: Flux Bootstrap | Finalize directory layout; confirm `./k8s/jellyfin/*.yaml` raw manifests are removed from Flux path before enabling |
| Bootstrap ordering / CRD race on Pi hardware | Phase 1: Flux Bootstrap | Add `dependsOn: [{name: flux-system}]` to app Kustomizations; wait 5 min after bootstrap before assessing |

---

## Sources

- [Flux CD Kustomization — prune field](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux CD FAQ — drift detection and ownership](https://fluxcd.io/flux/faq/)
- [Flux CD Troubleshooting Cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/)
- [Flux CD Manage Helm Releases](https://fluxcd.io/flux/guides/helmreleases/)
- [Flux CD Helm Releases API](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux CD bootstrap git command](https://fluxcd.io/flux/cmd/flux_bootstrap_git/)
- [K3s Helm Chart Management — helm.cattle.io CRD](https://deepwiki.com/k3s-io/k3s/4.3-network-policy-controller)
- [Flux CD resource ownership model (SSA + field managers)](https://oneuptime.com/blog/post/2026-03-05-flux-cd-resource-ownership/view)
- [Flux CD garbage collection behavior](https://oneuptime.com/blog/post/2026-03-05-flux-cd-garbage-collection/view)
- [Flux Discussion #4882 — local Helm charts don't redeploy without reconcileStrategy: Revision](https://github.com/fluxcd/flux2/discussions/4882)
- [Flux Discussion #964 — SSH key overwrite on multi-cluster bootstrap](https://github.com/fluxcd/flux2/issues/964)
- [Flux Discussion #2282 — CRD ordering and dependsOn](https://github.com/fluxcd/flux2/discussions/2282)
- [Flux Discussion #4931 — prune:true delete behavior](https://github.com/fluxcd/flux2/discussions/4931)
- [GitOps anti-patterns — mixing imperative and declarative](https://platformengineering.org/blog/gitops-architecture-patterns-and-anti-patterns)

---
*Pitfalls research for: Flux CD GitOps migration on K3s (Raspberry Pi homelab)*
*Researched: 2026-03-18*
