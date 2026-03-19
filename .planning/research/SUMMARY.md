# Project Research Summary

**Project:** pi-k3s-homelab Flux CD GitOps Migration
**Domain:** GitOps — Flux CD v2 with local Helm charts on K3s (Raspberry Pi homelab)
**Researched:** 2026-03-18
**Confidence:** HIGH

## Executive Summary

This project migrates an existing K3s homelab cluster from imperative `kubectl apply` deployments to GitOps using Flux CD v2. The cluster already runs Jellyfin and Pi-hole as raw Kubernetes manifests managed via `make deploy`. The migration converts those manifests into local Helm charts stored in `charts/` within the same repository, then deploys them through Flux HelmRelease CRDs that reference a shared GitRepository source. The authoritative pattern for this scale — single repo, single cluster, single operator — is a mono-repo approach with `charts/` for chart sources and `flux/apps/` for HelmRelease manifests, bootstrapped via `flux bootstrap github` and wrapped in a `make bootstrap-flux` target.

The recommended stack is Flux CD v2.8.3 (latest stable) using the four default controllers installed by `flux bootstrap`. No optional controllers (image automation, OCI) are needed. Local chart sourcing via `GitRepository` with `reconcileStrategy: Revision` eliminates any need for a separate chart registry. The full GitOps loop — push to main, Flux polls within 1 minute, Helm reconciles, pods update — is achievable with zero infrastructure beyond what already exists.

The key risks are concentrated in the migration phase, not the steady-state. The most dangerous is `prune: true` causing Flux to delete live workloads on first reconcile because kubectl-applied resources have no Flux inventory entry. The correct mitigation is explicit: start with `prune: false`, confirm Flux owns all resources, then re-enable. A second class of risk is the K3s/Flux CRD namespace collision for `HelmChart` resources, which causes false diagnostic failures. Both risks are avoidable with documented procedures. Once GitOps is operational, the steady state is simple and well-understood.

## Key Findings

### Recommended Stack

Flux CD v2.8.3 is the correct version — it is current stable, supports Helm v3 (which helm-controller bundles internally), and has a stable API surface (`helm.toolkit.fluxcd.io/v2`, `source.toolkit.fluxcd.io/v1`, `kustomize.toolkit.fluxcd.io/v1`). No legacy beta API versions should be used. The four default controllers (`source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller`) are sufficient; image automation controllers are explicitly out of scope. The `flux bootstrap github` command with `--token-auth=false` generates all Flux manifests, registers an SSH deploy key, and commits to the repo — reducing manual YAML authoring to the HelmRelease files only.

**Core technologies:**
- **Flux CD v2.8.3**: GitOps reconciliation engine — current stable, full Helm support, K3s v1.34 compatible
- **flux CLI v2.8.3**: Bootstrap and diagnostics tooling — must match controller version to avoid API drift
- **Helm CLI v3.17+ (local only)**: Chart authoring and linting — not installed on cluster; helm-controller bundles its own binary
- **GitRepository + HelmRelease pattern**: Local chart sourcing — single repo, no registry, push-to-main deploys

### Expected Features

The MVP is fully defined and binary: either GitOps is operational (every P1 feature is present) or it is not. There are no partial GitOps states worth shipping.

**Must have (table stakes — GitOps does not work without these):**
- Flux bootstrap integrated into `make install-k3s` — cluster cannot self-manage without this
- SSH deploy key auth with correct `ssh://` URL format in GitRepository — HTTPS auth fails for ongoing polling
- `charts/jellyfin/` Helm chart preserving nodeSelector, exFAT volume, Recreate strategy
- `charts/pihole/` Helm chart preserving hostNetwork, NET_ADMIN capability, port 8080 env var
- HelmRelease CRDs for both apps with `reconcileStrategy: Revision`
- `make deploy` target removed — dual authority between make and Flux creates drift
- `prune: true` enabled after migration is confirmed

**Should have (polish once GitOps is proven working):**
- Health checks on Kustomizations for meaningful `flux get` output
- `dependsOn` ordering to prevent ordering failures on reconcile
- Per-app Kustomizations for independent failure isolation
- Notification alerts to Discord/Slack for ops awareness

**Defer to v2+:**
- Image automation controller — not needed while Jellyfin uses `latest` and Pi-hole is intentionally pinned
- Helm values from ConfigMap — inline values in HelmRelease are sufficient at this scale
- Webhook receivers — 1m polling latency is acceptable; cluster is behind NAT anyway

### Architecture Approach

The canonical structure separates chart sources (`charts/`) from Flux configuration (`flux/`). Bootstrap writes `flux/flux-system/` (do not hand-edit). Hand-maintained HelmRelease objects live in `flux/apps/`. A root Kustomization points at `flux/flux-system/`; a second Kustomization for `flux/apps/` uses `dependsOn: flux-system` so app workloads only reconcile after Flux controllers are ready. The existing `k8s/` raw manifests are deleted once HelmReleases are confirmed healthy, eliminating the dual-authority conflict between Flux and `make generate`.

**Major components:**
1. **GitRepository `flux-system`** — polls `main` branch every 1m; single source serves both Kustomizations and HelmCharts
2. **Kustomization `apps`** — applies `flux/apps/*.yaml`; `prune: true`; depends on `flux-system`
3. **HelmRelease per app** — lives in `flux-system` namespace, deploys into `targetNamespace`; references `./charts/<app>` via GitRepository
4. **`charts/jellyfin/` and `charts/pihole/`** — self-contained Helm charts with all app-specific constraints expressed in values and templates

### Critical Pitfalls

1. **prune:true deletes live workloads on first reconcile** — Flux inventory is empty for kubectl-applied resources; Flux treats them as absent from git and removes them. Mitigation: set `prune: false` before first reconcile; enable only after Flux owns all resources.

2. **HelmRelease field manager conflict with existing resources** — kubectl owns field manager on live resources; helm-controller is rejected by server-side apply. Mitigation: delete raw Deployment/DaemonSet resources before creating HelmReleases, or add `upgrade.force: true` to HelmRelease spec.

3. **reconcileStrategy default silently ignores chart changes** — Default `ChartVersion` strategy only re-renders when `Chart.yaml` version increments; local chart template edits are invisible to Flux. Mitigation: set `reconcileStrategy: Revision` on every HelmRelease chart spec from the start.

4. **K3s HelmChart CRD ambiguity breaks diagnostics** — `kubectl get helmcharts` returns K3s's `helm.cattle.io` resources, not Flux's. Mitigation: always use `flux get sources chart -A` for Flux diagnostics; never `kubectl get helmcharts` bare.

5. **Jinja2-generated files in Flux's watch path create dual authority** — `make generate` writes to `./k8s/`; if Flux also watches `./k8s/`, both Helm controller and kustomize controller manage the same resources. Mitigation: delete raw manifests from `./k8s/jellyfin/` and `./k8s/pihole/` as part of migration; move Flux manifests to `./flux/`.

## Implications for Roadmap

Research identifies a clear 4-phase sequence driven by hard dependencies: Flux cannot bootstrap until charts exist; charts cannot be HelmReleased until the field manager conflict is resolved; cleanup cannot happen until GitOps is confirmed authoritative.

### Phase 1: Directory Structure and Chart Authoring

**Rationale:** Charts must exist in git before Flux bootstrap runs, or the first reconcile deploys nothing. This phase has no Flux dependency — it is pure file authoring work.
**Delivers:** `charts/jellyfin/` and `charts/pihole/` Helm charts committed to main; `flux/apps/` HelmRelease manifests authored; `flux/flux-system/` directory stub ready for bootstrap output.
**Addresses:** Jellyfin chart (P1), Pi-hole chart (P1), HelmRelease CRDs (P1)
**Avoids:** Pi-hole port 8080 conflict (must set `FTLCONF_webserver_port=8080` in chart values), exFAT volume ownership errors (must not use `chown` or `fsGroup` for exFAT-backed volumes), `reconcileStrategy` default (must set `Revision` at authoring time)
**Research flag:** Standard patterns — Helm chart authoring from existing manifests is well-documented. No additional research needed.

### Phase 2: Flux Bootstrap

**Rationale:** Bootstrap requires charts to exist (Phase 1 complete) and the live cluster to not be destroyed on first reconcile. This phase is the highest-risk step.
**Delivers:** Flux controllers running in `flux-system`; GitRepository polling `main` via SSH; `make bootstrap-flux` target in Makefile; bootstrap-generated files committed.
**Addresses:** Flux bootstrap in make (P1), SSH deploy key auth (P1), GitRepository CRD (P1)
**Avoids:** All bootstrap-phase pitfalls — prune:true deletion, SSH/HTTPS URL mismatch, K3s CRD ambiguity in diagnostics, CRD ordering race on Pi hardware (document 5-minute wait, add `dependsOn`)
**Research flag:** Well-documented bootstrap procedure. The `flux bootstrap github` command handles most complexity. No additional research needed.

### Phase 3: Migration and Ownership Transfer

**Rationale:** With Flux running but `prune: false`, this phase transfers ownership of live workloads from kubectl to Helm controller. The critical action is deleting existing raw resources before HelmReleases apply them.
**Delivers:** Jellyfin and Pi-hole running under HelmRelease control; Flux inventory contains all workload resources; `prune: true` re-enabled; `k8s/jellyfin/` and `k8s/pihole/` raw manifests deleted.
**Addresses:** Field manager conflict resolution, `prune: true` activation, raw manifest cleanup
**Avoids:** Jinja2 dual-authority conflict (raw manifests deleted, `make generate` no longer writes to Flux's watch path), orphaned resource accumulation (prune re-enabled)
**Research flag:** Well-understood migration pattern. No additional research needed.

### Phase 4: Makefile Cleanup and Polish

**Rationale:** Once GitOps is confirmed authoritative, the imperative path must be removed and observability improved. This phase has no risk — it is cleanup.
**Delivers:** `make deploy` removed; `make flux-reconcile` added; health checks on Kustomizations; `dependsOn` ordering finalized; CLAUDE.md diagnostic commands updated.
**Addresses:** `make deploy` removal (P1), health checks (P2), per-app Kustomizations (P2)
**Avoids:** No new pitfalls — this phase only removes footguns
**Research flag:** No research needed — these are configuration-only changes to already-running Flux.

### Phase Ordering Rationale

- **Charts before bootstrap** is a hard dependency: Flux reconciles on first run; empty `charts/` means successful reconcile with no workloads deployed, creating confusion.
- **Bootstrap before migration** is obvious, but the key insight from pitfall research is that `prune: false` must be set in Phase 2 and only lifted in Phase 3 after ownership transfer is confirmed.
- **Migration before cleanup** ensures no audit gap: `make deploy` is only removed once GitOps is proven to be the sole deployment path, not before.
- The 4-phase structure maps directly to the pitfall-to-phase mapping from PITFALLS.md: pitfalls cluster into "bootstrap phase" (Pitfalls 1, 3, 4, 7, 8) and "chart authoring phase" (Pitfalls 2, 5, 6), confirming the split.

### Research Flags

Phases with standard patterns (no additional research needed):
- **Phase 1:** Helm chart authoring from existing manifests is fully documented; all app-specific constraints (exFAT, hostNetwork, port 8080) are already known from CLAUDE.md and the existing manifests.
- **Phase 2:** `flux bootstrap github` is a single well-documented command; SSH deploy key registration is automated by the bootstrap command itself.
- **Phase 3:** Resource ownership transfer via delete-then-reconcile is a documented pattern; no unknowns.
- **Phase 4:** Pure cleanup; no research needed.

No phases require `/gsd:research-phase` during planning. All necessary patterns are covered by official Flux documentation at HIGH confidence.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Flux release notes and changelog confirm v2.8.3 versions; all API versions verified against official docs |
| Features | HIGH | Feature set derived from official Flux docs; homelab scope is well-constrained and community-validated |
| Architecture | HIGH | Directory structure and component wiring verified against official Flux repository structure guide |
| Pitfalls | HIGH | Pitfalls sourced from official Flux FAQ, troubleshooting docs, and verified GitHub discussions; most are directly reproducible |

**Overall confidence:** HIGH

### Gaps to Address

- **Existing `gotk-sync.yaml` stub**: The stub in `k8s/flux-system/` uses `path: ./k8s` and an HTTPS URL. This file must be superseded by bootstrap output at `flux/flux-system/`. Validate during Phase 2 that bootstrap correctly overwrites this stub rather than creating a duplicate Kustomization pointing at the wrong path.
- **`make install-k3s` integration point**: Research confirms bootstrap belongs in `make install-k3s`, but the exact Ansible task or Makefile target structure needs to be determined during Phase 2 planning. The constraint is that `flux bootstrap` requires a GITHUB_TOKEN env var for the one-time key registration — this must be handled in the Makefile, not hardcoded in Ansible.
- **Pi-hole DaemonSet scheduling**: The existing manifest uses `nodeAffinity` for a `workloads` label. This constraint must be preserved in the Helm chart and validated after HelmRelease deployment. The exact node label state should be confirmed before Phase 1 chart authoring.

## Sources

### Primary (HIGH confidence)
- [Flux GitHub Releases — fluxcd/flux2](https://github.com/fluxcd/flux2/releases) — v2.8.3 version confirmation
- [Announcing Flux v2.8 GA — fluxcd.io](https://fluxcd.io/blog/2026/02/flux-v2.8.0/) — feature set and Helm v4 support
- [Manage Helm Releases — fluxcd.io](https://fluxcd.io/flux/guides/helmreleases/) — GitRepository + HelmRelease local chart pattern
- [HelmCharts API — fluxcd.io](https://fluxcd.io/flux/components/source/helmcharts/) — reconcileStrategy: Revision behavior
- [Bootstrap GitHub — fluxcd.io](https://fluxcd.io/flux/installation/bootstrap/github/) — SSH deploy key bootstrap
- [Repository structure guide — fluxcd.io](https://fluxcd.io/flux/guides/repository-structure/) — flux/ directory layout
- [Flux CD Kustomization — prune field](https://fluxcd.io/flux/components/kustomize/kustomizations/) — prune behavior and inventory
- [Flux CD Troubleshooting Cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/) — diagnostic commands
- [Flux CD FAQ — drift detection and ownership](https://fluxcd.io/flux/faq/) — field manager conflict behavior

### Secondary (MEDIUM confidence)
- [Pi Cluster FluxCD — picluster.ricsanfre.com](https://picluster.ricsanfre.com/docs/fluxcd/) — Real-world K3s + Flux homelab validation
- [GitOps with FluxCD for home cluster — andi95.de 2025](https://blog.andi95.de/en/2025/03/gitops-with-fluxcd-for-my-home-kubernetes-cluster/) — Homelab pattern confirmation
- [Building a Home GitOps Lab: K3s + FluxCD on Raspberry Pi — medium.com](https://medium.com/@afaqbabar/building-a-home-gitops-lab-k3s-fluxcd-on-raspberry-pi-7b72cb9a6394) — Pi-specific patterns
- [Flux Discussion #4882 — local Helm charts and reconcileStrategy](https://github.com/fluxcd/flux2/discussions/4882) — Confirmed reconcileStrategy: Revision requirement
- [Flux Discussion #2282 — CRD ordering and dependsOn](https://github.com/fluxcd/flux2/discussions/2282) — Pi bootstrap race condition pattern

---
*Research completed: 2026-03-18*
*Ready for roadmap: yes*
