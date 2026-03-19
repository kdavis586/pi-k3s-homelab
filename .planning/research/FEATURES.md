# Feature Research

**Domain:** Flux CD GitOps migration on K3s homelab
**Researched:** 2026-03-18
**Confidence:** HIGH — Flux documentation is current and well-structured; homelab patterns well-documented

## Feature Landscape

### Table Stakes (GitOps Does Not Work Without These)

Features that must exist for GitOps to function at all. Missing any of these means Flux is installed
but not operating as GitOps — the cluster converges by manual kubectl, not by git push.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Flux bootstrap via Ansible | Installs all Flux controllers on the cluster; self-manages its own upgrades via Git | LOW | `flux bootstrap github` or equivalent embedded in `make install-k3s`; pushes Flux manifests to repo |
| SSH deploy key auth | Flux must authenticate to the repo to pull manifests; SSH scoped to this repo only | LOW | PROJECT.md specifies SSH deploy key approach over broad PAT |
| GitRepository CRD | Defines the repo Flux watches (url, branch, interval); already stubbed in `gotk-sync.yaml` | LOW | Existing stub uses HTTPS, needs updating to SSH with secretRef |
| Kustomization CRD pointing to `./k8s` | Tells Flux which path to reconcile; already stubbed in `gotk-sync.yaml` with `prune: true` | LOW | The stub is already 90% correct; path `./k8s` is right |
| Helm Controller installed | Required to reconcile HelmRelease resources; not installed by default with basic flux install | LOW | Installed automatically by `flux bootstrap`; needed for local chart approach |
| Jellyfin Helm chart (`charts/jellyfin/`) | Raw manifests in `k8s/jellyfin/` must become a chart Flux's HelmRelease references | MEDIUM | Must preserve: nodeSelector for apple-pi, exFAT mount options, Recreate strategy |
| Pi-hole Helm chart (`charts/pihole/`) | Raw manifests in `k8s/pihole/` must become a chart; DaemonSet with hostNetwork is the tricky part | MEDIUM | Must preserve: hostNetwork, NET_ADMIN capability, nodeAffinity for workloads label |
| HelmRelease CRDs for each app | Flux's mechanism to declaratively manage Helm chart releases; references local charts via GitRepository | LOW | One HelmRelease per app; `spec.chart.spec.sourceRef` points to the flux-system GitRepository |
| `make deploy` removed | Eliminating the manual deploy path is what makes GitOps authoritative; dual paths create drift | LOW | Makefile target deleted or replaced with a git-push reminder |
| Kustomization `prune: true` | Removes cluster resources that are deleted from git; without this, deletions don't propagate | LOW | Already set in existing `gotk-sync.yaml` stub |

### Differentiators (Homelab-Valuable, Not Strictly Required)

Features that improve the homelab GitOps experience without being blockers to basic operation.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Health checks on Kustomizations | Flux waits until deployments are actually ready before marking reconciliation complete; surfaces broken rollouts in `flux get` output | LOW | Add `spec.healthChecks` entries for Jellyfin Deployment and Pi-hole DaemonSet |
| Dependency ordering (dependsOn) | Ensures infrastructure (namespaces, storage config) reconciles before workloads that depend on it | LOW | Pi-hole must not start before its namespace exists; local-path-config before Jellyfin PVC |
| Reconciliation interval tuning | Default 10m is fine for production; 1m is useful while iterating during migration | LOW | Already set to 1m on GitRepository, 10m on Kustomization in existing stub — good defaults |
| `flux get` / `flux logs` observability | CLI commands for checking reconciliation status and errors without kubectl | LOW | Already available once Flux is bootstrapped; no additional setup needed |
| Helm values from ConfigMap/Secret | Externalizes chart configuration from the HelmRelease spec; useful if values grow large | MEDIUM | Overkill for this homelab — inline values in HelmRelease are sufficient |
| Notification controller alerts (Discord/Slack) | Push notification when a reconciliation fails or a deployment rolls out | MEDIUM | Nice-to-have for homelab ops awareness; requires webhook secret and Provider + Alert CRDs |
| Flux self-upgrade via Git | Once bootstrapped, bumping Flux version is a git commit, not a manual command | LOW | This comes for free from `flux bootstrap`; no extra work required |
| Separate Kustomizations per app | Fine-grained reconciliation control — Jellyfin and Pi-hole reconcile independently, failure in one doesn't block the other | LOW | Split the single `path: ./k8s` Kustomization into `path: ./k8s/jellyfin` and `path: ./k8s/pihole` with `dependsOn: flux-system` |
| `reconcileStrategy: Revision` on HelmCharts | Re-evaluates local charts whenever the git revision changes (i.e., on every commit); without this, chart changes are ignored until version bump | LOW | Required for local charts in same repo; set on the HelmRelease's chart spec |

### Anti-Features (Deliberately Out of Scope for This Homelab)

Features commonly added to Flux setups that create unnecessary complexity given this cluster is LAN-only,
single-operator, and has no sensitive secrets to protect.

| Feature | Why Requested | Why Problematic for This Homelab | Alternative |
|---------|---------------|----------------------------------|-------------|
| SOPS / Sealed Secrets | Encrypt secrets committed to git | Cluster is LAN-only, no secrets in use (Pi-hole has no password, no API keys), adds key management overhead | Keep secrets out of git entirely; hardcode the one non-sensitive value (empty password) directly in chart values |
| Separate GitOps repo (fleet-repo pattern) | Separation of app code from cluster state | Doubles the repo surface area with zero benefit for a single-operator homelab; PROJECT.md explicitly rejects this | Same-repo approach — `charts/` and `k8s/` live alongside Ansible |
| Published OCI / Helm registry | Publish charts to ghcr.io or similar before Flux consumes them | Adds a publish step to the deploy path, defeating the "push to main = deploy" simplicity | Local charts via GitRepository — Flux reads charts directly from the repo |
| `gitops` branch strategy (PR-gated deploys) | Protect main from untested changes | Single-operator homelab with no team; PR workflow is ceremony with no reviewer | Direct push to main; test changes by pushing a branch and temporarily pointing Flux at it if needed |
| Image Automation Controller | Automatically update image tags in git when new container images are published | Jellyfin is pinned to `latest` which already pulls new images on pod restart; Pi-hole is pinned to a specific version intentionally; automation commits would be noise | Manual image tag bumps in `group_vars/all.yaml` → `make generate` → git push |
| Multi-tenancy / RBAC lockdown | Restrict which namespaces different Flux Kustomizations can write to | Single-operator cluster; no untrusted tenants; adds RBAC complexity for zero security benefit | Default permissive setup is fine |
| Flux monitoring stack (Prometheus/Grafana) | Full observability dashboard for Flux metrics | Raspberry Pi RAM is constrained (4GB control plane); a full Prometheus stack consumes significant resources | `flux get all` and `flux logs` CLI commands provide sufficient observability for a homelab |
| Webhook receivers (push-based sync) | Trigger immediate reconciliation on git push via GitHub webhook | Requires inbound webhook from GitHub to the cluster — cluster is behind NAT, not internet-exposed | Polling interval (1m for GitRepository) is sufficient latency for a homelab |

## Feature Dependencies

```
[Flux Bootstrap]
    └──installs──> [Source Controller]
    └──installs──> [Kustomize Controller]
    └──installs──> [Helm Controller]
    └──installs──> [Notification Controller]
    └──creates──>  [GitRepository CRD (flux-system)]
    └──creates──>  [Kustomization CRD (flux-system)]

[GitRepository CRD]
    └──required by──> [HelmRelease (Jellyfin)]
    └──required by──> [HelmRelease (Pi-hole)]
    └──required by──> [Kustomization (app namespaces)]

[Jellyfin Helm Chart]
    └──required by──> [HelmRelease (Jellyfin)]

[Pi-hole Helm Chart]
    └──required by──> [HelmRelease (Pi-hole)]

[Kustomization (namespaces)] ──dependsOn──> [Flux Bootstrap]
[HelmRelease (Jellyfin)]     ──dependsOn──> [Kustomization (namespaces)]
[HelmRelease (Pi-hole)]      ──dependsOn──> [Kustomization (namespaces)]

[Health Checks] ──enhances──> [dependsOn ordering]
    (dependsOn only waits for Ready=True; health checks define what "ready" means)

[Notification Alerts] ──requires──> [Notification Controller] (already installed by bootstrap)
    └──requires──> [Provider CRD (webhook secret)]
    └──requires──> [Alert CRD]
```

### Dependency Notes

- **Flux Bootstrap must run first:** All other features depend on Flux controllers being present; this runs as part of `make install-k3s`.
- **Helm charts must exist before HelmRelease CRDs:** If Flux reconciles a HelmRelease pointing to a chart path that doesn't exist yet, it errors. Charts in `charts/jellyfin/` and `charts/pihole/` must be committed before bootstrap runs, or the initial reconcile will fail and self-heal once charts are added.
- **`reconcileStrategy: Revision` is required for local charts:** Without it, Flux only re-fetches the chart when the `spec.chart.spec.version` field changes. Since local charts have no published versions, the strategy must be set to `Revision` so any git commit triggers chart re-evaluation.
- **exFAT mount constraint flows into chart:** The Jellyfin chart's PVC and hostPath volume config must preserve `uid=0,gid=0,umask=000` fstab mount options — these are OS-level (Ansible), not chart-level, but the chart must not attempt `chown` or ownership-setting init containers.
- **SOPS conflicts with simplicity goal:** Introducing SOPS requires key management, age/gpg tooling, and decryption setup in Flux — this is incompatible with the "LAN-only, no secrets" constraint from PROJECT.md.

## MVP Definition

### Launch With (v1 — GitOps is operational)

- [ ] Flux bootstrap integrated into `make install-k3s` — cluster self-manages from git
- [ ] SSH deploy key created and registered; GitRepository uses `secretRef`
- [ ] `charts/jellyfin/` Helm chart created from existing manifests
- [ ] `charts/pihole/` Helm chart created from existing manifests
- [ ] HelmRelease for Jellyfin — references local chart, preserves nodeSelector and exFAT constraints
- [ ] HelmRelease for Pi-hole — references local chart, preserves hostNetwork and NET_ADMIN
- [ ] `reconcileStrategy: Revision` set on both HelmRelease chart specs
- [ ] `make deploy` target removed from Makefile
- [ ] `kustomization prune: true` confirmed (already in stub)

### Add After Validation (v1.x — polish once GitOps is proven working)

- [ ] Health checks on Kustomizations — add once initial reconcile is stable and we want better status reporting
- [ ] Dependency ordering (`dependsOn`) — add if health checks reveal ordering issues during reconcile
- [ ] Separate Kustomizations per app — add if a failure in one app's reconcile is blocking the other
- [ ] Notification alerts to Discord/Slack — add once the novelty of watching `flux get` wears off

### Future Consideration (v2+ — only if homelab needs evolve)

- [ ] Image automation — only relevant if pinned image tags become a maintenance burden
- [ ] Helm values from ConfigMap — only if HelmRelease values sections grow unwieldy
- [ ] Webhook receivers — only if 1m polling latency becomes genuinely frustrating

## Feature Prioritization Matrix

| Feature | Homelab Value | Implementation Cost | Priority |
|---------|--------------|---------------------|----------|
| Flux bootstrap in make install-k3s | HIGH | LOW | P1 |
| SSH deploy key auth | HIGH | LOW | P1 |
| GitRepository CRD (SSH) | HIGH | LOW | P1 |
| Jellyfin Helm chart | HIGH | MEDIUM | P1 |
| Pi-hole Helm chart | HIGH | MEDIUM | P1 |
| HelmRelease for Jellyfin | HIGH | LOW | P1 |
| HelmRelease for Pi-hole | HIGH | LOW | P1 |
| reconcileStrategy: Revision | HIGH | LOW | P1 |
| Remove make deploy | HIGH | LOW | P1 |
| Health checks | MEDIUM | LOW | P2 |
| dependsOn ordering | MEDIUM | LOW | P2 |
| Per-app Kustomizations | MEDIUM | LOW | P2 |
| Notification alerts | LOW | MEDIUM | P3 |
| Image automation | LOW | MEDIUM | P3 |
| Helm values from ConfigMap | LOW | LOW | P3 |

**Priority key:**
- P1: Must have — without this, GitOps is not operational
- P2: Should have — add once P1 is stable
- P3: Nice to have — defer until P2 is stable

## Sources

- [Flux Installation docs — bootstrap vs install](https://fluxcd.io/flux/installation/) — HIGH confidence (official)
- [Managing Helm Releases with Flux](https://fluxcd.io/flux/guides/helmreleases/) — HIGH confidence (official)
- [Helm Releases CRD reference](https://fluxcd.io/flux/components/helm/helmreleases/) — HIGH confidence (official)
- [Kustomization health checks and dependsOn](https://fluxcd.io/flux/components/kustomize/kustomizations/) — HIGH confidence (official)
- [Flux Notification Controller](https://fluxcd.io/flux/components/notification/) — HIGH confidence (official)
- [Flux end-to-end workflow](https://fluxcd.io/flux/flux-e2e/) — HIGH confidence (official)
- [Image Automation guide](https://fluxcd.io/flux/guides/image-update/) — HIGH confidence (official)
- [GitOps with FluxCD for home cluster — andi95.de 2025](https://blog.andi95.de/en/2025/03/gitops-with-fluxcd-for-my-home-kubernetes-cluster/) — MEDIUM confidence (community, recent)
- [Building a Home GitOps Lab: K3s + FluxCD on Raspberry Pi](https://medium.com/@afaqbabar/building-a-home-gitops-lab-k3s-fluxcd-on-raspberry-pi-7b72cb9a6394) — MEDIUM confidence (community)

---
*Feature research for: Flux CD GitOps migration on K3s homelab*
*Researched: 2026-03-18*
