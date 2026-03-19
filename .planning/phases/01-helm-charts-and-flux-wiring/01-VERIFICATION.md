---
phase: 01-helm-charts-and-flux-wiring
verified: 2026-03-18T00:00:00Z
status: passed
score: 13/13 must-haves verified
re_verification: false
---

# Phase 1: Helm Charts and Flux Wiring — Verification Report

**Phase Goal:** All chart and HelmRelease artifacts exist in git such that Flux can deploy both workloads on first reconcile
**Verified:** 2026-03-18
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `charts/jellyfin/` contains a complete Helm chart that renders a Deployment with `nodeSelector: kubernetes.io/hostname: apple-pi`, `Recreate` update strategy, and no `fsGroup` | VERIFIED | `helm template` renders Deployment with `type: Recreate`, `kubernetes.io/hostname: apple-pi`, and confirmed no `fsGroup` in output |
| 2 | `charts/pihole/` contains a complete Helm chart that renders a DaemonSet with `hostNetwork: true`, `NET_ADMIN` capability, and `FTLCONF_webserver_port=8080` | VERIFIED | `helm template` renders DaemonSet with all three constraints confirmed in rendered output |
| 3 | `flux/apps/jellyfin.yaml` and `flux/apps/pihole.yaml` exist as HelmRelease CRDs referencing `./charts/jellyfin` and `./charts/pihole` with `reconcileStrategy: Revision` | VERIFIED | Both files present; `reconcileStrategy: Revision` confirmed inside `spec.chart.spec` (correct location, not top-level `spec`) |
| 4 | A Kustomization for `flux/apps/` exists and declares `dependsOn: flux-system` | VERIFIED | `flux/flux-system/apps-kustomization.yaml` present with `dependsOn: [{name: flux-system}]` and `prune: false` |
| 5 | `helm template` runs successfully against both charts with no errors | VERIFIED | Both charts exit 0; `helm lint` reports 0 failures on each |
| 6 | Jellyfin chart renders hostPath media volume (not PVC) | VERIFIED | `helm template` output contains `hostPath: path: /mnt/usb-storage/media, type: DirectoryOrCreate` |
| 7 | Jellyfin chart renders Traefik IngressRoute with multi-host match | VERIFIED | `apiVersion: traefik.io/v1alpha1` and `Host('jellyfin.local') || Host('192.168.1.100') || Host('192.168.1.101') || Host('192.168.1.102')` in rendered output |
| 8 | Pi-hole DaemonSet has `dnsPolicy: ClusterFirstWithHostNet` | VERIFIED | Confirmed in rendered output |
| 9 | Pi-hole DaemonSet has nodeAffinity for `homelab/node-group: workloads` | VERIFIED | `key: homelab/node-group`, `operator: In`, value `workloads` in rendered output |
| 10 | Pi-hole chart exposes all 4 ports (53/UDP, 53/TCP, 67/UDP, 8080/TCP) | VERIFIED | containerPorts 53, 53, 67, 8080 present in rendered DaemonSet |
| 11 | Templates use `.Values.` references (not hardcoded values) | VERIFIED | Deployment has 6 `.Values.` references; DaemonSet has 9 |
| 12 | No `Release.Namespace` usage in any chart template | VERIFIED | Grep across both charts returns clean — all templates hardcode `namespace: jellyfin` or `namespace: pihole` |
| 13 | Plain kustomize config lists both HelmRelease files as resources | VERIFIED | `flux/apps/kustomization.yaml` uses `kustomize.config.k8s.io/v1beta1` and lists `jellyfin.yaml` and `pihole.yaml` |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `charts/jellyfin/Chart.yaml` | Chart metadata with `name: jellyfin` | VERIFIED | `apiVersion: v2`, `name: jellyfin` present |
| `charts/jellyfin/values.yaml` | Default values with `apple-pi`, `local-path`, `cpu: "4"` | VERIFIED | All three present |
| `charts/jellyfin/templates/deployment.yaml` | Deployment preserving Recreate, nodeSelector, probes | VERIFIED | All constraints present; 6 `.Values.` references |
| `charts/jellyfin/templates/service.yaml` | ClusterIP service port 8096 | VERIFIED | Rendered as `kind: Service, namespace: jellyfin` |
| `charts/jellyfin/templates/ingress.yaml` | Traefik IngressRoute for jellyfin.local | VERIFIED | `traefik.io/v1alpha1` with multi-host match |
| `charts/jellyfin/templates/pvc.yaml` | PVC `jellyfin-config` using `local-path` | VERIFIED | Rendered with `claimName: jellyfin-config` |
| `charts/jellyfin/templates/namespace.yaml` | Namespace `jellyfin` | VERIFIED | `kind: Namespace, name: jellyfin` |
| `charts/pihole/Chart.yaml` | Chart metadata with `name: pihole` | VERIFIED | `apiVersion: v2`, `name: pihole` present |
| `charts/pihole/values.yaml` | Values with `hostNetwork: true`, `FTLCONF_webserver_port`, `homelab/node-group` | VERIFIED | All three present |
| `charts/pihole/templates/daemonset.yaml` | DaemonSet with hostNetwork, NET_ADMIN, nodeAffinity | VERIFIED | All constraints present; 9 `.Values.` references |
| `charts/pihole/templates/service-web.yaml` | ClusterIP service `pihole-web` port 8080 | VERIFIED | `name: pihole-web, namespace: pihole` |
| `charts/pihole/templates/ingress.yaml` | Traefik IngressRoute for pihole.local | VERIFIED | `traefik.io/v1alpha1`, `Host('pihole.local')` |
| `charts/pihole/templates/namespace.yaml` | Namespace `pihole` | VERIFIED | `kind: Namespace, name: pihole` |
| `flux/apps/jellyfin.yaml` | HelmRelease CRD with `reconcileStrategy: Revision` | VERIFIED | `helm.toolkit.fluxcd.io/v2`, `reconcileStrategy: Revision` inside `spec.chart.spec` |
| `flux/apps/pihole.yaml` | HelmRelease CRD with `reconcileStrategy: Revision` | VERIFIED | `helm.toolkit.fluxcd.io/v2`, `reconcileStrategy: Revision` inside `spec.chart.spec` |
| `flux/apps/kustomization.yaml` | Plain kustomize listing both HelmRelease files | VERIFIED | `kustomize.config.k8s.io/v1beta1` with `jellyfin.yaml` and `pihole.yaml` |
| `flux/flux-system/apps-kustomization.yaml` | Flux Kustomization CRD with `dependsOn` and `prune: false` | VERIFIED | `kustomize.toolkit.fluxcd.io/v1`, `prune: false`, `dependsOn: [{name: flux-system}]` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `charts/jellyfin/templates/deployment.yaml` | `charts/jellyfin/values.yaml` | `.Values.` references | WIRED | 6 `.Values.` references in deployment template |
| `charts/jellyfin/templates/pvc.yaml` | `charts/jellyfin/templates/deployment.yaml` | `claimName: jellyfin-config` | WIRED | PVC name `jellyfin-config` matches volume reference in Deployment |
| `charts/pihole/templates/daemonset.yaml` | `charts/pihole/values.yaml` | `.Values.` references | WIRED | 9 `.Values.` references in daemonset template |
| `charts/pihole/templates/service-web.yaml` | `charts/pihole/templates/daemonset.yaml` | `selector: app: pihole` | WIRED | Service selects `app: pihole`; DaemonSet labels include `app: pihole` |
| `flux/apps/jellyfin.yaml` | `charts/jellyfin/` | `spec.chart.spec.chart: ./charts/jellyfin` | WIRED | Exact path reference confirmed |
| `flux/apps/pihole.yaml` | `charts/pihole/` | `spec.chart.spec.chart: ./charts/pihole` | WIRED | Exact path reference confirmed |
| `flux/flux-system/apps-kustomization.yaml` | `flux/apps/` | `spec.path: ./flux/apps` | WIRED | Path confirmed; `flux/apps/kustomization.yaml` lists both HelmRelease files |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CHART-01 | 01-01-PLAN.md | Jellyfin Helm chart exists at `charts/jellyfin/` with all 5 resources | SATISFIED | All 5 resource kinds render: Namespace, PVC, Service, Deployment, IngressRoute |
| CHART-02 | 01-01-PLAN.md | Jellyfin chart preserves nodeSelector apple-pi, Recreate strategy, no fsGroup | SATISFIED | All three constraints confirmed in `helm template` output |
| CHART-03 | 01-02-PLAN.md | Pi-hole Helm chart exists at `charts/pihole/` with all resources | SATISFIED | All 4 resource kinds render: Namespace, Service, DaemonSet, IngressRoute |
| CHART-04 | 01-02-PLAN.md | Pi-hole chart preserves hostNetwork, NET_ADMIN, FTLCONF_webserver_port=8080 | SATISFIED | All three constraints confirmed in `helm template` output |
| CHART-05 | 01-03-PLAN.md | Both charts have `reconcileStrategy: Revision` | SATISFIED | Confirmed inside `spec.chart.spec` in both HelmRelease files (critical placement) |
| FLUX-01 | 01-03-PLAN.md | HelmRelease CRD for Jellyfin at `flux/apps/jellyfin.yaml` | SATISFIED | File exists, references `./charts/jellyfin`, `targetNamespace: jellyfin` |
| FLUX-02 | 01-03-PLAN.md | HelmRelease CRD for Pi-hole at `flux/apps/pihole.yaml` | SATISFIED | File exists, references `./charts/pihole`, `targetNamespace: pihole` |
| FLUX-03 | 01-03-PLAN.md | Kustomization for `flux/apps/` with `dependsOn: flux-system` | SATISFIED | `flux/flux-system/apps-kustomization.yaml` with `prune: false` and `dependsOn: [{name: flux-system}]` |

No orphaned requirements for Phase 1 — REQUIREMENTS.md traceability table maps exactly CHART-01 through CHART-05 and FLUX-01 through FLUX-03 to Phase 1, all accounted for.

### Anti-Patterns Found

None. No TODO/FIXME/placeholder comments, no stub implementations, no empty handlers found in any chart or flux file.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None found | — | — |

### Human Verification Required

None required. All must-haves are verifiable from the codebase via `helm template`, `helm lint`, and file content inspection. The charts are not yet deployed to the live cluster (that is Phase 2 and Phase 3 work), so no runtime verification is needed for this phase's goal.

### Gaps Summary

No gaps. All 13 truths verified, all 17 artifacts substantive and wired, all 8 key links confirmed, all 8 requirement IDs satisfied.

---

_Verified: 2026-03-18_
_Verifier: Claude (gsd-verifier)_
