# Roadmap: Pi-k3s Homelab GitOps Migration

## Overview

The cluster already runs Jellyfin and Pi-hole via raw Kubernetes manifests deployed with `make deploy`. This roadmap migrates that cluster to GitOps: raw manifests are converted to Helm charts, Flux CD is bootstrapped to watch the main branch, live workloads are handed off from kubectl to Helm controller ownership, and the imperative deploy path is removed. When complete, pushing to main is the only way to deploy changes.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Helm Charts and Flux Wiring** - Author Jellyfin and Pi-hole Helm charts; write HelmRelease CRDs
- [ ] **Phase 2: Flux Bootstrap** - Install Flux controllers on cluster; wire GitRepository to main branch via SSH
- [ ] **Phase 3: Migration and Ownership Transfer** - Hand off live workloads from kubectl to Flux; enable pruning
- [ ] **Phase 4: Makefile Cleanup** - Remove imperative deploy path; add flux diagnostics; update docs

## Phase Details

### Phase 1: Helm Charts and Flux Wiring
**Goal**: All chart and HelmRelease artifacts exist in git such that Flux can deploy both workloads on first reconcile
**Depends on**: Nothing (first phase)
**Requirements**: CHART-01, CHART-02, CHART-03, CHART-04, CHART-05, FLUX-01, FLUX-02, FLUX-03
**Success Criteria** (what must be TRUE):
  1. `charts/jellyfin/` contains a complete Helm chart that renders a Deployment with `nodeSelector: kubernetes.io/hostname: apple-pi`, `Recreate` update strategy, and no `fsGroup` on the volume
  2. `charts/pihole/` contains a complete Helm chart that renders a DaemonSet with `hostNetwork: true`, `NET_ADMIN` capability, and `FTLCONF_webserver_port=8080` env var
  3. `flux/apps/jellyfin.yaml` and `flux/apps/pihole.yaml` exist as HelmRelease CRDs referencing `./charts/jellyfin` and `./charts/pihole` respectively, both with `reconcileStrategy: Revision`
  4. A Kustomization for `flux/apps/` exists and declares `dependsOn: flux-system`
  5. `helm template` runs successfully against both charts with no errors
**Plans:** 2/3 plans executed

Plans:
- [ ] 01-01-PLAN.md — Jellyfin Helm chart (Chart.yaml, values.yaml, 5 templates)
- [ ] 01-02-PLAN.md — Pi-hole Helm chart (Chart.yaml, values.yaml, 4 templates)
- [ ] 01-03-PLAN.md — Flux wiring (HelmRelease CRDs, Kustomization files, phase validation)

### Phase 2: Flux Bootstrap
**Goal**: Flux CD controllers are running on the cluster and reconciling from the main branch of this repository via SSH deploy key
**Depends on**: Phase 1
**Requirements**: BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05
**Success Criteria** (what must be TRUE):
  1. `make bootstrap-flux` (or equivalent) installs Flux controllers and registers an SSH deploy key without requiring manual kubectl commands
  2. `flux get sources git -n flux-system` shows the GitRepository for this repo polling main at a 1-minute interval with READY=True
  3. Flux-generated manifests are committed to `flux/flux-system/` in this repo
  4. Jellyfin and Pi-hole continue running after first reconcile (workloads are not deleted — `prune: false` is in effect)
**Plans**: TBD

### Phase 3: Migration and Ownership Transfer
**Goal**: Jellyfin and Pi-hole are fully owned by Flux HelmReleases; no kubectl-applied resources remain; pruning is enabled
**Depends on**: Phase 2
**Requirements**: MIG-01, MIG-02, MIG-03, MIG-04
**Success Criteria** (what must be TRUE):
  1. `flux get helmreleases -A` shows both Jellyfin and Pi-hole HelmReleases with READY=True and no field manager conflicts
  2. Jellyfin is accessible at `http://jellyfin.local` and Pi-hole web UI is accessible after migration — workloads were not interrupted by ownership transfer
  3. `prune: true` is enabled on the apps Kustomization — resources removed from git are removed from the cluster on next reconcile
  4. `k8s/jellyfin/` and `k8s/pihole/` directories no longer exist in the repo
**Plans**: TBD

### Phase 4: Makefile Cleanup
**Goal**: The imperative deploy path is gone; `make` provides only cluster management and diagnostic targets; docs reflect GitOps as the sole deploy path
**Depends on**: Phase 3
**Requirements**: MAKE-01, MAKE-02, MAKE-03
**Success Criteria** (what must be TRUE):
  1. `make deploy` no longer exists — running it returns an error or is absent from the Makefile
  2. A `make flux-status` (or equivalent) target exists and shows current Flux reconciliation state without requiring direct `kubectl` invocation
  3. CLAUDE.md documents `flux get` commands for diagnostics and does not reference `kubectl apply` for deploying workloads
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Helm Charts and Flux Wiring | 2/3 | In Progress|  |
| 2. Flux Bootstrap | 0/TBD | Not started | - |
| 3. Migration and Ownership Transfer | 0/TBD | Not started | - |
| 4. Makefile Cleanup | 0/TBD | Not started | - |
