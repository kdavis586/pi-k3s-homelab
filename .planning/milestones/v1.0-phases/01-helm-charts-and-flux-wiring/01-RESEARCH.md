# Phase 1: Helm Charts and Flux Wiring - Research

**Researched:** 2026-03-18
**Domain:** Helm chart authoring + Flux CD HelmRelease / Kustomization CRDs
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHART-01 | Jellyfin Helm chart at `charts/jellyfin/` with Deployment, Service, Ingress, PVC, Namespace | Helm chart structure section; existing manifest analysis |
| CHART-02 | Jellyfin chart preserves `nodeSelector: kubernetes.io/hostname: apple-pi`, `Recreate` strategy, exFAT-compatible volume (no `fsGroup`) | Existing deployment.yaml fully analysed; constraints documented |
| CHART-03 | Pi-hole Helm chart at `charts/pihole/` with DaemonSet, Services, Ingress, Namespace | Helm chart structure section; existing manifest analysis |
| CHART-04 | Pi-hole chart preserves `hostNetwork: true`, `NET_ADMIN` capability, `FTLCONF_webserver_port=8080` | Existing daemonset.yaml fully analysed; constraints documented |
| CHART-05 | Both charts have `reconcileStrategy: Revision` configured | HelmRelease spec.chart.spec.reconcileStrategy documented |
| FLUX-01 | HelmRelease CRD at `flux/apps/jellyfin.yaml` referencing `./charts/jellyfin` | HelmRelease YAML structure documented with local path pattern |
| FLUX-02 | HelmRelease CRD at `flux/apps/pihole.yaml` referencing `./charts/pihole` | Same as FLUX-01 |
| FLUX-03 | Kustomization for `flux/apps/` exists with `dependsOn: flux-system` | Flux Kustomization CRD structure and dependsOn pattern documented |
</phase_requirements>

---

## Summary

Phase 1 is a pure git-authoring task — no cluster interaction required. The goal is to produce Helm chart artifacts and Flux CRD manifests that are syntactically valid and structurally correct, so that when Flux bootstraps in Phase 2 it can immediately reconcile them. All source material exists: the raw `k8s/jellyfin/` and `k8s/pihole/` manifests provide the exact container config, environment variables, volume mounts, and constraints that must be preserved.

The two charts are structurally different workload types. Jellyfin is a `Deployment` (single replica, `Recreate` strategy, pinned to `apple-pi` via `nodeSelector`) and Pi-hole is a `DaemonSet` (runs on every node with label `homelab/node-group: workloads`, `hostNetwork: true`). The Flux wiring consists of two `HelmRelease` CRDs in `flux/apps/` plus one Flux `Kustomization` in `flux/apps/kustomization.yaml` that loads them.

The critical Flux subtlety for this phase: `reconcileStrategy: Revision` lives inside `spec.chart.spec` of the `HelmRelease`, not at the top-level spec. Without it, Flux ignores chart file changes unless `Chart.yaml` version is bumped — which defeats GitOps for local charts.

**Primary recommendation:** Author charts as thin wrappers around the existing raw manifests, preserving every constraint verbatim. Use `spec.chart.spec.reconcileStrategy: Revision` in HelmRelease; use a Flux `Kustomization` (not a plain `kustomization.yaml`) for `flux/apps/` with `dependsOn` pointing to the `flux-system` Kustomization.

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Helm | v3.x (3.14+) | Chart templating engine | Industry standard; `helm template` used for local validation |
| Flux helm-controller | v2 API | Manages HelmRelease lifecycle | Ships with Flux CD; native GitOps Helm management |
| Flux kustomize-controller | v1 API | Applies Flux Kustomization CRDs | Ships with Flux CD; orchestrates resource ordering |

### Supporting

| Resource Kind | API Version | Purpose | When to Use |
|--------------|------------|---------|-------------|
| `HelmRelease` | `helm.toolkit.fluxcd.io/v2` | Flux-managed Helm install | Every chart deployed via Flux |
| `Kustomization` (Flux) | `kustomize.toolkit.fluxcd.io/v1` | Batch-applies manifests from a path | Grouping HelmRelease files under one sync unit |
| `HelmChart` | `source.toolkit.fluxcd.io/v1` | Auto-created by helm-controller | Created implicitly from HelmRelease spec.chart |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `spec.chart.spec` inline (auto-creates HelmChart) | Explicit standalone `HelmChart` CR | Inline is simpler; standalone only needed when multiple HelmReleases share one chart |
| Local path `./charts/jellyfin` | Published OCI/Helm registry | Local is correct for this project (out-of-scope per REQUIREMENTS.md) |
| Single Flux `Kustomization` for apps | Per-app Kustomizations | Single is fine for Phase 1; per-app is a v2 requirement (OBS-03) |

**Installation (Helm CLI for local validation only):**
```bash
brew install helm
```

---

## Architecture Patterns

### Recommended Directory Structure

```
charts/
├── jellyfin/
│   ├── Chart.yaml           # name: jellyfin, version: 0.1.0, type: application
│   ├── values.yaml          # Defaults matching current raw manifest values
│   └── templates/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml     # Traefik IngressRoute
│       └── pvc.yaml
└── pihole/
    ├── Chart.yaml           # name: pihole, version: 0.1.0, type: application
    ├── values.yaml          # Defaults matching current raw manifest values
    └── templates/
        ├── namespace.yaml
        ├── daemonset.yaml
        ├── service-web.yaml
        └── ingress.yaml     # Traefik IngressRoute

flux/
├── flux-system/             # Phase 2 territory — do not author here in Phase 1
└── apps/
    ├── kustomization.yaml   # Flux Kustomization CRD (not a plain kustomize file)
    ├── jellyfin.yaml        # HelmRelease for Jellyfin
    └── pihole.yaml          # HelmRelease for Pi-hole
```

### Pattern 1: Minimal Helm Chart for Existing Manifests

**What:** Convert raw YAML manifests 1-to-1 into Helm templates with values extracted for the fields most likely to change.
**When to use:** When preserving exact existing behavior is the primary goal and complex parameterization is not needed.

```yaml
# charts/jellyfin/Chart.yaml
apiVersion: v2
name: jellyfin
description: Jellyfin media server for pi-k3s homelab
type: application
version: 0.1.0
appVersion: "latest"
```

```yaml
# charts/jellyfin/values.yaml
image:
  repository: jellyfin/jellyfin
  tag: latest
  pullPolicy: IfNotPresent

nodeSelector:
  kubernetes.io/hostname: apple-pi

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 6Gi
    cpu: "4"

storage:
  configSize: 5Gi
  storageClassName: local-path
  mediaHostPath: /mnt/usb-storage/media

publishedServerUrl: "http://jellyfin.local"
```

### Pattern 2: HelmRelease with Local Chart Path

**What:** Reference a chart stored in the same GitRepository using a relative path. The `spec.chart.spec.chart` field accepts a relative path when `sourceRef.kind: GitRepository`.
**When to use:** Local charts in the same git repo (this project's pattern).

```yaml
# Source: https://fluxcd.io/flux/components/helm/helmreleases/
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: jellyfin
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: jellyfin
  chart:
    spec:
      chart: ./charts/jellyfin
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      reconcileStrategy: Revision
  install:
    createNamespace: false   # Namespace is in the chart itself
```

Key fields:
- `sourceRef.name: flux-system` — references the GitRepository Flux bootstrap creates for this repo
- `reconcileStrategy: Revision` — MUST be in `spec.chart.spec`, not top-level spec
- `targetNamespace` — the namespace where Helm deploys resources (can differ from HelmRelease namespace)
- `install.createNamespace: false` — namespace creation handled by the chart's own template

### Pattern 3: Flux Kustomization for apps/

**What:** A Flux `Kustomization` CRD (distinct from plain `kustomize.yaml`) that reconciles all HelmRelease files in `flux/apps/`. The `dependsOn` field blocks reconciliation until `flux-system` Kustomization is healthy.
**When to use:** Any time you group multiple Flux-managed resources under one sync unit with ordering guarantees.

```yaml
# Source: https://fluxcd.io/flux/components/kustomize/kustomizations/
# flux/apps/kustomization.yaml  -- THIS IS A FLUX Kustomization CRD, not a plain kustomize file
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  path: ./flux/apps
  prune: false          # Phase 1: prune disabled; Phase 3 will enable it
  dependsOn:
    - name: flux-system
      namespace: flux-system
```

**IMPORTANT:** The file at `flux/apps/kustomization.yaml` is a Flux `Kustomization` CRD (API group `kustomize.toolkit.fluxcd.io/v1`) — not a Kustomize overlay `kustomization.yaml` (API group `kustomize.config.k8s.io/v1beta1`). Do not confuse the two.

For `kustomize-controller` to load the HelmRelease files from `./flux/apps`, the directory also needs a plain `kustomization.yaml` listing the resources OR the controller must find raw manifests. The cleanest approach: include a `kustomize.config.k8s.io/v1beta1` Kustomization at `flux/apps/kustomization.yaml` listing `jellyfin.yaml` and `pihole.yaml` as resources — but this conflicts with the Flux CRD file of the same name. Resolution: the Flux Kustomization CRD goes in a parent directory (or is applied separately), and `flux/apps/kustomization.yaml` is the plain kustomize file. See the Pitfalls section.

### Anti-Patterns to Avoid

- **Putting `reconcileStrategy` at top-level `spec`:** It is invalid there. It belongs at `spec.chart.spec.reconcileStrategy`.
- **Using `prune: true` before Flux owns resources:** In Phase 1, `prune: false` must be set. Enabling prune before Flux owns existing resources would delete live workloads.
- **Copying the `k8s/flux-system/gotk-sync.yaml` stub** into the new `flux/` layout: The stub uses HTTPS and wrong path (`./k8s`). It will be superseded by Phase 2 bootstrap.
- **Including `fsGroup` or `securityContext` on the Jellyfin pod spec** due to exFAT: exFAT does not support Unix ownership; the existing manifest correctly omits `fsGroup` at the pod level.
- **Using `spec.targetNamespace` together with namespace template in chart** without setting `install.createNamespace: false`: If the chart already has a Namespace resource, Flux should not also try to create it.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Helm chart for Jellyfin | Custom Kubernetes operator | Helm chart template | Helm handles upgrade lifecycle, rollback, values override |
| Detecting chart source changes | Custom webhook / polling script | `reconcileStrategy: Revision` on HelmChart | Built into Flux source-controller; no extra infra |
| Ordering dependency between Flux resources | Manual apply scripts | `spec.dependsOn` on Kustomization/HelmRelease | Flux handles ordering natively with health checks |
| Namespace creation per-chart | Separate Ansible task | Namespace template inside chart | Helm lifecycle manages create/delete with the release |

**Key insight:** All wiring in this phase is declarative YAML. No scripts, no CLI automation, no cluster interaction. The only "tool" used is `helm template` for local validation.

---

## Common Pitfalls

### Pitfall 1: The Two `kustomization.yaml` Files

**What goes wrong:** Kustomize-controller loads a directory path by looking for a `kustomization.yaml` (plain Kustomize config) or raw manifests. The Flux `Kustomization` CRD itself is a different thing. When both are needed at the same path, developers write a single file with the wrong API group — either a plain kustomize file that Flux ignores or a Flux CRD that `kustomize build` rejects.

**Why it happens:** Both objects are conventionally named `kustomization.yaml`. The CRD uses `apiVersion: kustomize.toolkit.fluxcd.io/v1`; the plain file uses `apiVersion: kustomize.config.k8s.io/v1beta1`.

**How to avoid:**
- The Flux `Kustomization` CRD (`kustomize.toolkit.fluxcd.io/v1`) lives where Flux itself is told about it — it is applied to the cluster via bootstrap or another Kustomization, not placed in the target directory.
- The `flux/apps/` directory should contain a plain `kustomization.yaml` (Kustomize config) listing `jellyfin.yaml` and `pihole.yaml` as resources so kustomize-controller can process them.
- The Flux Kustomization CRD that points `path: ./flux/apps` must be committed somewhere that Flux processes — typically in the bootstrap-generated `flux/flux-system/` (Phase 2) or as a separate file.

**Warning signs:** `flux get kustomizations` shows `flux-system` as Ready but `apps` never appears; or `kustomize build flux/apps` errors with "unknown resource".

### Pitfall 2: reconcileStrategy in Wrong Location

**What goes wrong:** Chart file changes are deployed to git but the cluster does not update. `flux get helmreleases` shows the HelmRelease as `Ready` and `Reconciled` but at the old revision.

**Why it happens:** The default `reconcileStrategy` is `ChartVersion`. Flux watches for chart version bumps, not file changes. A local chart in git with static `version: 0.1.0` in `Chart.yaml` never triggers a new artifact.

**How to avoid:** Always set `spec.chart.spec.reconcileStrategy: Revision` in the HelmRelease for all local git-sourced charts. This tells the source-controller to produce a new HelmChart artifact on every commit, regardless of version.

**Warning signs:** `flux get helmcharts -A` shows `REVISION` not incrementing after a git push.

### Pitfall 3: Pi-hole nodeAffinity vs. nodeSelector

**What goes wrong:** The Pi-hole DaemonSet uses a `nodeAffinity` on label `homelab/node-group: workloads` (not a `nodeSelector`). This label is applied by `make install-k3s` to agent nodes. The chart must preserve this `affinity` block exactly; replacing it with a `nodeSelector` changes scheduling semantics.

**Why it happens:** DaemonSets with `nodeAffinity` only schedule pods on matching nodes. The current daemonset.yaml already has the correct `affinity` block. If the chart template omits it, Pi-hole runs on ALL nodes including the control plane.

**How to avoid:** Copy the `affinity` block verbatim from `k8s/pihole/daemonset.yaml` into the chart template. Confirmed: `make install-k3s` does apply `homelab/node-group=workloads` to agent nodes — this is not an unresolved gap.

**Warning signs:** Pi-hole pod appears on `the-bakery` (control plane, IP .100) which should only run control plane workloads.

### Pitfall 4: Traefik IngressRoute is a CRD, not standard Ingress

**What goes wrong:** Using `apiVersion: networking.k8s.io/v1 kind: Ingress` instead of Traefik's `traefik.io/v1alpha1 kind: IngressRoute`. Standard Ingress resources will not be served by Traefik in this cluster — or will require annotations that change routing semantics.

**Why it happens:** The existing manifests already use `IngressRoute` (Traefik CRD). A developer converting manifests to Helm templates might "standardize" to a plain Ingress.

**How to avoid:** Preserve `apiVersion: traefik.io/v1alpha1 kind: IngressRoute` in both chart ingress templates. Do not replace with standard `networking.k8s.io/v1 Ingress`.

**Warning signs:** `http://jellyfin.local` returns 404 after migration; `http://pihole.local` unreachable.

### Pitfall 5: `helm template` Namespace Mismatch

**What goes wrong:** `helm template` passes locally but resources land in the wrong namespace when Flux applies them.

**Why it happens:** `helm template` uses a default namespace (usually `default`) if not passed `--namespace`. But when Flux applies via `targetNamespace`, it overrides the release namespace — which can conflict with hardcoded namespace in templates.

**How to avoid:** Keep `metadata.namespace` hardcoded in chart templates (e.g., `namespace: jellyfin`) rather than `{{ .Release.Namespace }}`. This ensures the namespace is predictable regardless of how the chart is invoked.

---

## Existing Manifest Analysis

This section documents every constraint from the existing raw manifests that the Helm chart templates must preserve exactly.

### Jellyfin Constraints (from `k8s/jellyfin/`)

| Field | Value | Reason |
|-------|-------|--------|
| `spec.strategy.type` | `Recreate` | Jellyfin cannot run multiple instances sharing one config PVC |
| `spec.template.spec.nodeSelector` | `kubernetes.io/hostname: apple-pi` | USB drive attached to apple-pi only |
| Volume `media` type | `hostPath` (not PVC) | exFAT USB does not support PVC permissions; `hostPath` gives direct access |
| Volume `config` storageClass | `local-path` | local-path-provisioner paths configured to USB on apple-pi |
| `securityContext` | absent (no fsGroup) | exFAT does not support Unix ownership — fsGroup chown would fail |
| Ingress kind | `traefik.io/v1alpha1 IngressRoute` | Cluster uses Traefik; routes on port 80 (`web` entrypoint) |
| Ingress match | `Host("jellyfin.local") || Host("192.168.1.100") || Host("192.168.1.101") || Host("192.168.1.102")` | mDNS hostname + all three node IPs |
| Image | `jellyfin/jellyfin:latest` | Pinned to latest; no version in use |
| PVC size | 5Gi | Config volume (metadata, thumbnails) |

### Pi-hole Constraints (from `k8s/pihole/`)

| Field | Value | Reason |
|-------|-------|--------|
| `spec.template.spec.hostNetwork` | `true` | Required for DHCP broadcasts (255.255.255.255:67 cannot be DNAT'd) |
| `spec.template.spec.dnsPolicy` | `ClusterFirstWithHostNet` | Required when hostNetwork is true and cluster DNS needed |
| `securityContext.capabilities.add` | `[NET_ADMIN]` | Required for DHCP server operation |
| `FTLCONF_webserver_port` env | `"8080"` | Traefik intercepts port 80 on host when hostNetwork enabled |
| nodeAffinity | `homelab/node-group: workloads` | Only schedule on agent nodes (applied by make install-k3s) |
| Image | `pihole/pihole:2026.02.0` | Explicitly pinned version |
| Service name | `pihole-web` | Used by IngressRoute; must match |
| Ingress match | `Host("pihole.local")` | mDNS hostname (Avahi publishes it from the-bakery) |

---

## Code Examples

Verified patterns from official sources and existing repo manifests:

### HelmRelease for Jellyfin (complete)

```yaml
# Source: https://fluxcd.io/flux/components/helm/helmreleases/ + https://fluxcd.io/flux/components/source/helmcharts/
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: jellyfin
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: jellyfin
  chart:
    spec:
      chart: ./charts/jellyfin
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      reconcileStrategy: Revision
  install:
    createNamespace: false
  upgrade:
    cleanupOnFail: true
```

### HelmRelease for Pi-hole (complete)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: pihole
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: pihole
  chart:
    spec:
      chart: ./charts/pihole
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      reconcileStrategy: Revision
  install:
    createNamespace: false
  upgrade:
    cleanupOnFail: true
```

### Flux Kustomization CRD pointing to flux/apps/ (to be placed in flux/flux-system/ during Phase 2)

```yaml
# Source: https://fluxcd.io/flux/components/kustomize/kustomizations/
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  path: ./flux/apps
  prune: false
  dependsOn:
    - name: flux-system
      namespace: flux-system
```

### Plain kustomize config at flux/apps/kustomization.yaml (for kustomize-controller to discover HelmRelease files)

```yaml
# Source: https://kustomize.io / required by kustomize-controller
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin.yaml
  - pihole.yaml
```

### Minimal Chart.yaml

```yaml
apiVersion: v2
name: jellyfin
description: Jellyfin media server
type: application
version: 0.1.0
appVersion: "latest"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `helm.toolkit.fluxcd.io/v2beta1` HelmRelease | `helm.toolkit.fluxcd.io/v2` | Flux v2.2+ (2023) | `v2beta1` is deprecated; use `v2` |
| `kustomize.toolkit.fluxcd.io/v1beta2` | `kustomize.toolkit.fluxcd.io/v1` | Flux v2.0 (2023) | Use `v1` |
| `source.toolkit.fluxcd.io/v1beta2` GitRepository | `source.toolkit.fluxcd.io/v1` | Flux v2.0 (2023) | Use `v1` |
| Separate `HelmChart` CR + `HelmRelease` chartRef | Inline `spec.chart` in HelmRelease | Always available | Inline is simpler for one-chart-one-release pattern |

**Deprecated/outdated in this repo:**
- `k8s/flux-system/gotk-sync.yaml` stub: uses HTTPS URL and `./k8s` path — will be replaced by Phase 2 bootstrap; must not be applied during Phase 1.

---

## Open Questions

1. **Where does the Flux Kustomization CRD for `flux/apps/` get committed?**
   - What we know: The Flux `Kustomization` pointing at `flux/apps/` must be loaded by Flux. In a bootstrapped cluster, Flux reads from the bootstrap Kustomization (at `flux/flux-system/`).
   - What's unclear: In Phase 1 (pre-bootstrap), this CRD has nowhere to be applied from. It can be committed to `flux/flux-system/` now, but the path `flux/flux-system/` doesn't exist until Phase 2 bootstrap writes to it.
   - Recommendation: Commit the Flux `Kustomization` CRD for `apps` into `flux/flux-system/apps-kustomization.yaml` during Phase 1. Phase 2 bootstrap will write its own files to `flux/flux-system/` and the apps Kustomization will coexist. This keeps Phase 1 artifacts complete and self-consistent.

2. **Does `targetNamespace` in HelmRelease conflict with hardcoded namespace in chart templates?**
   - What we know: `targetNamespace` overrides the Helm release namespace, but resources with explicit `metadata.namespace` in templates keep their explicit namespace.
   - What's unclear: Whether Flux/helm-controller raises an error if a template's namespace differs from `targetNamespace`.
   - Recommendation: Hardcode namespace in templates (e.g., `namespace: jellyfin`) and set `targetNamespace: jellyfin` to match. Avoid `{{ .Release.Namespace }}` in templates to eliminate ambiguity.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `helm template` (built-in Helm CLI) |
| Config file | None — invoked directly |
| Quick run command | `helm template charts/jellyfin --debug > /dev/null && helm template charts/pihole --debug > /dev/null` |
| Full suite command | `helm template charts/jellyfin && helm template charts/pihole && helm lint charts/jellyfin && helm lint charts/pihole` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHART-01 | Jellyfin chart renders without error | smoke | `helm template charts/jellyfin` | Wave 0 |
| CHART-02 | nodeSelector, Recreate strategy, no fsGroup in rendered output | unit (grep) | `helm template charts/jellyfin \| grep -E 'Recreate\|apple-pi'` | Wave 0 |
| CHART-03 | Pi-hole chart renders without error | smoke | `helm template charts/pihole` | Wave 0 |
| CHART-04 | hostNetwork, NET_ADMIN, FTLCONF_webserver_port in rendered output | unit (grep) | `helm template charts/pihole \| grep -E 'hostNetwork\|NET_ADMIN\|8080'` | Wave 0 |
| CHART-05 | reconcileStrategy: Revision in HelmRelease files | unit (grep) | `grep -r 'reconcileStrategy: Revision' flux/apps/` | Wave 0 |
| FLUX-01 | flux/apps/jellyfin.yaml is valid YAML and references ./charts/jellyfin | unit (grep) | `grep 'chart: ./charts/jellyfin' flux/apps/jellyfin.yaml` | Wave 0 |
| FLUX-02 | flux/apps/pihole.yaml is valid YAML and references ./charts/pihole | unit (grep) | `grep 'chart: ./charts/pihole' flux/apps/pihole.yaml` | Wave 0 |
| FLUX-03 | Kustomization has dependsOn flux-system | unit (grep) | `grep -A2 'dependsOn' flux/flux-system/apps-kustomization.yaml` | Wave 0 |

### Sampling Rate

- **Per task commit:** `helm template charts/jellyfin > /dev/null && helm template charts/pihole > /dev/null`
- **Per wave merge:** `helm lint charts/jellyfin && helm lint charts/pihole` plus grep-based constraint checks
- **Phase gate:** All smoke + unit checks green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `charts/jellyfin/` — does not exist yet; create in Wave 1
- [ ] `charts/pihole/` — does not exist yet; create in Wave 1
- [ ] `flux/apps/jellyfin.yaml` — does not exist yet; create in Wave 1
- [ ] `flux/apps/pihole.yaml` — does not exist yet; create in Wave 1
- [ ] `flux/flux-system/apps-kustomization.yaml` — does not exist yet; create in Wave 1
- [ ] Helm CLI: `brew install helm` — verify available before running template checks

---

## Sources

### Primary (HIGH confidence)

- [Flux HelmRelease API v2](https://fluxcd.io/flux/components/helm/helmreleases/) — spec.chart.spec structure, reconcileStrategy field, targetNamespace behavior
- [Flux HelmChart source API](https://fluxcd.io/flux/components/source/helmcharts/) — reconcileStrategy values and semantics
- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/) — dependsOn structure, spec.path behavior
- [Flux Helm Releases guide](https://fluxcd.io/flux/guides/helmreleases/) — end-to-end GitRepository + HelmRelease pattern
- [Helm Charts documentation](https://helm.sh/docs/topics/charts/) — Chart.yaml structure, templates/ directory behavior
- Existing repo manifests: `k8s/jellyfin/deployment.yaml`, `k8s/pihole/daemonset.yaml` — ground truth for preserved constraints

### Secondary (MEDIUM confidence)

- [Flux fluxcd/flux2 Discussion #3300](https://github.com/fluxcd/flux2/discussions/3300) — community confirmation that reconcileStrategy: Revision is required for local charts
- [Flux fluxcd/flux2 Discussion #4882](https://github.com/fluxcd/flux2/discussions/4882) — community confirmation of pitfall: no redeploy without Revision strategy

### Tertiary (LOW confidence)

- None — all critical claims verified against official docs.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Flux API versions verified against official docs; Helm structure is stable
- Architecture: HIGH — Patterns derive directly from official Flux guides and existing repo manifests
- Pitfalls: HIGH — reconcileStrategy location verified in API reference; namespace/kustomization.yaml distinctions verified; Pi-hole affinity confirmed in Ansible playbook

**Research date:** 2026-03-18
**Valid until:** 2026-09-18 (Flux APIs are stable; Helm v3 chart structure is stable)
