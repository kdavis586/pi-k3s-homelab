# Requirements: Pi-k3s Homelab GitOps Migration

**Defined:** 2026-03-18
**Core Value:** Push to main → cluster converges. No manual deploy steps after initial cluster setup.

## v1 Requirements

### Bootstrap

- [ ] **BOOT-01**: Flux CD v2 controllers are installed on the cluster via `make install-k3s` (or a dedicated `make bootstrap-flux` target called from it)
- [ ] **BOOT-02**: Flux authenticates to GitHub via SSH deploy key (not HTTPS token) — key generated and registered automatically by `flux bootstrap github`
- [ ] **BOOT-03**: GitRepository CRD polls the `main` branch of this repo on a 1-minute interval
- [ ] **BOOT-04**: Bootstrap-generated Flux manifests are committed to `flux/flux-system/` in this repo
- [ ] **BOOT-05**: First reconcile does not delete existing workloads (`prune: false` set before bootstrap)

### Helm Charts

- [x] **CHART-01**: Jellyfin Helm chart exists at `charts/jellyfin/` with all resources (Deployment, Service, Ingress, PVC, Namespace)
- [x] **CHART-02**: Jellyfin chart preserves `nodeSelector: kubernetes.io/hostname: apple-pi`, `Recreate` update strategy, and exFAT-compatible volume (no `fsGroup`/`chown`)
- [x] **CHART-03**: Pi-hole Helm chart exists at `charts/pihole/` with all resources (DaemonSet, Services, Ingress, Namespace)
- [x] **CHART-04**: Pi-hole chart preserves `hostNetwork: true`, `NET_ADMIN` capability, and `FTLCONF_webserver_port=8080` env var
- [ ] **CHART-05**: Both charts have `reconcileStrategy: Revision` configured so template changes deploy without version bumps

### Flux App Wiring

- [ ] **FLUX-01**: HelmRelease CRD for Jellyfin exists at `flux/apps/jellyfin.yaml` referencing `./charts/jellyfin`
- [ ] **FLUX-02**: HelmRelease CRD for Pi-hole exists at `flux/apps/pihole.yaml` referencing `./charts/pihole`
- [ ] **FLUX-03**: Kustomization for `flux/apps/` exists and depends on `flux-system` being healthy

### Migration

- [ ] **MIG-01**: Existing kubectl-applied Jellyfin resources are deleted and recreated under HelmRelease ownership (field manager conflict resolved)
- [ ] **MIG-02**: Existing kubectl-applied Pi-hole resources are deleted and recreated under HelmRelease ownership
- [ ] **MIG-03**: `prune: true` re-enabled on the apps Kustomization after Flux owns all workload resources
- [ ] **MIG-04**: Raw manifests in `k8s/jellyfin/` and `k8s/pihole/` are deleted from the repo

### Makefile Cleanup

- [ ] **MAKE-01**: `make deploy` target is removed — Flux is the sole deploy path
- [ ] **MAKE-02**: `make flux-status` (or similar) added for checking reconciliation state
- [ ] **MAKE-03**: CLAUDE.md updated — diagnostic commands reference `flux get` instead of `kubectl apply`

## v2 Requirements

### Observability

- **OBS-01**: Health checks configured on Kustomizations for meaningful `flux get all` output
- **OBS-02**: `dependsOn` ordering between app HelmReleases (Pi-hole before Jellyfin, if needed)
- **OBS-03**: Per-app Kustomizations for independent failure isolation
- **OBS-04**: Flux notification controller alerts to a channel (Discord/Slack) on reconcile failures

### Automation

- **AUTO-01**: Image automation controller to track and update container image tags
- **AUTO-02**: Webhook receiver to trigger immediate reconcile on push (vs 1-minute polling)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Secrets management (Sealed Secrets, SOPS) | Cluster is LAN-only, no sensitive secrets in use |
| Separate GitOps repo | Same-repo approach keeps everything co-located |
| OCI chart registry | Local `charts/` is sufficient; no external registry needed |
| Multi-tenancy / RBAC | Single-operator homelab |
| Image automation | Jellyfin uses `latest`; Pi-hole is intentionally pinned |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOOT-01 | Phase 2 | Pending |
| BOOT-02 | Phase 2 | Pending |
| BOOT-03 | Phase 2 | Pending |
| BOOT-04 | Phase 2 | Pending |
| BOOT-05 | Phase 2 | Pending |
| CHART-01 | Phase 1 | Complete |
| CHART-02 | Phase 1 | Complete |
| CHART-03 | Phase 1 | Complete |
| CHART-04 | Phase 1 | Complete |
| CHART-05 | Phase 1 | Pending |
| FLUX-01 | Phase 1 | Pending |
| FLUX-02 | Phase 1 | Pending |
| FLUX-03 | Phase 1 | Pending |
| MIG-01 | Phase 3 | Pending |
| MIG-02 | Phase 3 | Pending |
| MIG-03 | Phase 3 | Pending |
| MIG-04 | Phase 3 | Pending |
| MAKE-01 | Phase 4 | Pending |
| MAKE-02 | Phase 4 | Pending |
| MAKE-03 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-18 after initial definition*
