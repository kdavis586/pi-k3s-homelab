# Architecture Research

**Domain:** GitOps — Flux CD with local Helm charts on K3s
**Researched:** 2026-03-18
**Confidence:** HIGH (verified against official Flux documentation)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Git Repository (main)                       │
│                                                                  │
│  charts/jellyfin/     charts/pihole/     flux/                   │
│  ├── Chart.yaml       ├── Chart.yaml     ├── flux-system/        │
│  ├── values.yaml      ├── values.yaml    │   ├── gotk-components │
│  └── templates/       └── templates/     │   ├── gotk-sync.yaml  │
│                                          │   └── kustomization   │
│                                          └── apps/               │
│                                              ├── jellyfin.yaml   │
│                                              └── pihole.yaml     │
└──────────────────────┬──────────────────────────────────────────┘
                       │ poll interval (1m)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Flux Controllers (flux-system namespace)       │
│                                                                  │
│  ┌──────────────────┐   ┌──────────────────┐                    │
│  │ source-controller│   │  helm-controller  │                    │
│  │                  │   │                   │                    │
│  │ GitRepository    │──▶│  HelmRelease      │                    │
│  │ HelmChart        │   │  (reconcile loop) │                    │
│  └──────────────────┘   └────────┬──────────┘                   │
│                                   │                              │
│  ┌─────────────────────────────── │ ──────────────────────────┐  │
│  │ kustomize-controller           │                           │  │
│  │                                │                           │  │
│  │ Kustomization ─────────────────┘                           │  │
│  └─────────────────────────────────────────────────────────── ┘  │
└────────────────────────────────────────────────────────────────-┘
                       │ apply
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    K3s Cluster                                    │
│                                                                  │
│  namespace: jellyfin        namespace: pihole                    │
│  ┌──────────────────┐       ┌──────────────────┐                 │
│  │ Deployment       │       │ DaemonSet        │                 │
│  │ Service          │       │ Service          │                 │
│  │ Ingress          │       │ Ingress          │                 │
│  │ PVC              │       └──────────────────┘                 │
│  └──────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Lives In |
|-----------|----------------|----------|
| GitRepository | Polls git repo on interval; exposes artifact to controllers | flux-system namespace |
| HelmChart | Packages chart from GitRepository artifact into tarball; created implicitly by HelmRelease | flux-system namespace |
| HelmRelease | Declares desired Helm release state; triggers helm install/upgrade via helm-controller | apps namespace |
| Kustomization | Applies a directory of manifests; used to bootstrap HelmReleases and their namespace prereqs | flux-system namespace |
| source-controller | Watches GitRepository and HelmChart objects; fetches and caches artifacts | flux-system pod |
| helm-controller | Watches HelmRelease objects; runs helm install/upgrade/rollback | flux-system pod |
| kustomize-controller | Watches Kustomization objects; applies kustomize-rendered manifests to cluster | flux-system pod |

## Recommended Project Structure

```
pi-k3s-homelab/
├── charts/                        # Local Helm chart sources
│   ├── jellyfin/
│   │   ├── Chart.yaml             # name, version (must bump to trigger reconcile)
│   │   ├── values.yaml            # defaults (nodeSelector, storage paths, image tag)
│   │   └── templates/
│   │       ├── namespace.yaml
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       └── pvc.yaml
│   └── pihole/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── namespace.yaml
│           ├── daemonset.yaml
│           ├── service-web.yaml
│           └── ingress.yaml
│
├── flux/                          # Flux CD configuration
│   ├── flux-system/               # Bootstrap output — do not hand-edit
│   │   ├── gotk-components.yaml   # Flux controller CRDs and deployments (generated)
│   │   ├── gotk-sync.yaml         # GitRepository + root Kustomization (generated)
│   │   └── kustomization.yaml     # Kustomize entry for flux-system itself (generated)
│   └── apps/                      # HelmRelease objects — hand-maintained
│       ├── kustomization.yaml     # Kustomize entry for apps/ dir
│       ├── jellyfin.yaml          # HelmRelease for Jellyfin chart
│       └── pihole.yaml            # HelmRelease for Pi-hole chart
│
├── ansible/                       # Unchanged — provisions nodes, installs K3s
├── cloud-init/                    # Unchanged — SD card boot configs
├── k8s/                           # Legacy — removed after Flux migration
│   └── storage/
│       └── local-path-config.yaml # May move to flux/apps/ or charts/
└── Makefile
```

### Structure Rationale

- **charts/**: Helm chart sources kept separate from Flux config so chart authors can work without knowing Flux internals. Each chart is self-contained with its own `Chart.yaml` and defaults.
- **flux/flux-system/**: Bootstrap generates these files; they are committed to git but should not be hand-edited. Flux self-manages these via GitOps.
- **flux/apps/**: Hand-maintained HelmRelease objects. One file per app. These are what you edit to change values, image tags, or enable/disable features.
- **No clusters/ subdirectory needed**: Single homelab cluster — the standard `clusters/my-cluster/` pattern adds indirection without benefit. `flux/flux-system/` IS the cluster entry point.

## Architectural Patterns

### Pattern 1: Implicit HelmChart via Inline chart.spec

**What:** HelmRelease defines its chart source inline rather than requiring a separate HelmChart object. helm-controller creates the HelmChart automatically.

**When to use:** Always — for local charts in the same repo this is the standard approach.

**Trade-offs:** Slightly less visible (HelmChart object appears at runtime, not in git). In exchange, fewer files to maintain.

**Example:**
```yaml
# flux/apps/jellyfin.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: jellyfin
  namespace: flux-system        # HelmRelease lives here...
spec:
  interval: 10m
  targetNamespace: jellyfin     # ...but deploys into this namespace
  chart:
    spec:
      chart: ./charts/jellyfin  # Relative path from repo root
      sourceRef:
        kind: GitRepository
        name: flux-system       # The same GitRepository that watches this repo
        namespace: flux-system
      reconcileStrategy: Revision  # Trigger on any git change, not just Chart.yaml version
      interval: 1m
  values:
    storageNode: apple-pi
    usbMount: /mnt/usb-storage
```

### Pattern 2: Root Kustomization Points at flux/apps/

**What:** The root Kustomization (generated by bootstrap) points at `flux/flux-system/`. A second Kustomization object in `flux/apps/` recurses into the apps directory, applying all HelmRelease objects.

**When to use:** Cleaner than putting all HelmReleases directly in `flux/flux-system/`.

**Trade-offs:** One extra Kustomization object. Worth it for separation of bootstrap vs. app config.

**Example:**
```yaml
# flux/apps/kustomization.yaml  (a Kustomize kustomization.yaml, not a Flux Kustomization CRD)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - jellyfin.yaml
  - pihole.yaml
```

```yaml
# flux/flux-system/gotk-sync.yaml (the Flux Kustomization CRD)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m
  path: ./flux/flux-system    # Bootstrap points at itself
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
---
# A second Kustomization for apps (add this manually)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./flux/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: flux-system   # Apps deploy only after Flux itself is ready
```

### Pattern 3: reconcileStrategy: Revision for Local Charts

**What:** By default, helm-controller only rebuilds the HelmChart artifact when `Chart.yaml`'s `version` field changes. With `reconcileStrategy: Revision`, it rebuilds on every git commit.

**When to use:** Always for local charts in a homelab where you want push-to-main to trigger immediate reconciliation without manually bumping Chart.yaml versions.

**Trade-offs:** Slightly more reconciliation overhead (artifact rebuilt on every commit regardless of what changed). Acceptable at homelab scale.

## Data Flow

### GitOps Reconciliation Flow

```
[git push to main]
        |
        v
[source-controller polls GitRepository every 1m]
        |
        v  (new commit SHA detected)
[source-controller fetches repo, stores artifact]
        |
        v
[kustomize-controller sees Kustomization at ./flux/flux-system]
        |
        v  (applies Kustomization resources)
[kustomize-controller sees Kustomization at ./flux/apps]
        |
        v  (applies HelmRelease objects)
[helm-controller sees HelmRelease change]
        |
        v
[source-controller builds HelmChart from ./charts/jellyfin]
        |
        v  (chart tarball artifact ready)
[helm-controller runs: helm upgrade --install jellyfin ./chart.tgz --values ...]
        |
        v
[K3s applies rendered manifests → pods reconcile]
```

Total latency from push to pod update: 1-2 minutes (GitRepository poll interval + reconcile time).

### Bootstrap vs. Ongoing Flow

```
[One-time bootstrap]
flux bootstrap git
  --url=ssh://git@github.com/kdavis586/pi-k3s-homelab
  --branch=main
  --path=./flux/flux-system
  --private-key-file=~/.ssh/flux-deploy-key
        |
        v  (bootstrap writes to repo and pushes)
flux/flux-system/
  gotk-components.yaml   ← Flux controller Deployments, CRDs, RBAC
  gotk-sync.yaml         ← GitRepository + root Kustomization
  kustomization.yaml     ← Kustomize manifest list
        |
        v  (bootstrap applies gotk-components.yaml to cluster)
[Flux controllers running in flux-system namespace]
        |
        v  (Flux reads gotk-sync.yaml, starts reconciling)
[Normal GitOps loop takes over — no more bootstrap needed]
```

### What Bootstrap Does NOT Touch

- `charts/` directory — exists before bootstrap, not managed by bootstrap command
- `flux/apps/` — you create these; bootstrap only manages `flux/flux-system/`
- `ansible/`, `cloud-init/`, `Makefile` — untouched

## Build Order: What Must Exist Before Bootstrap

Bootstrap will fail if these preconditions are not met. This is the critical ordering constraint for the roadmap.

```
[1] K3s cluster running and healthy
    └── make install-k3s completes successfully
    └── kubectl get nodes shows all 3 nodes Ready

[2] SSH deploy key generated and added to GitHub
    └── ssh-keygen -t ed25519 -f ~/.ssh/flux-deploy-key -C "flux@pi-k3s-homelab"
    └── Public key added as deploy key on GitHub repo (read access sufficient)

[3] flux CLI installed on workstation
    └── brew install fluxcd/tap/flux  (or curl install script)
    └── flux check --pre  (validates cluster compatibility)

[4] flux/flux-system/ directory does NOT need to exist before bootstrap
    └── Bootstrap creates it and pushes to git

[5] charts/ and flux/apps/ should exist before bootstrap
    └── Otherwise first reconcile will succeed but deploy nothing
    └── OR: bootstrap first, add charts/ + flux/apps/ in follow-up commit

[6] Kubeconfig pointing at cluster
    └── KUBECONFIG=~/.kube/config-pi-k3s flux bootstrap git ...
```

The practical order for this project:
1. K3s already running (precondition met)
2. Convert `k8s/jellyfin/` manifests to `charts/jellyfin/` Helm chart
3. Convert `k8s/pihole/` manifests to `charts/pihole/` Helm chart
4. Write `flux/apps/jellyfin.yaml` and `flux/apps/pihole.yaml` HelmRelease objects
5. Generate SSH deploy key, add to GitHub
6. Run `make bootstrap-flux` (which wraps `flux bootstrap git`)
7. Verify Flux reconciles and workloads are running
8. Remove `make deploy` and `k8s/` raw manifests

## Anti-Patterns

### Anti-Pattern 1: Pointing flux-system Kustomization Directly at k8s/

**What people do:** Keep existing `k8s/` directory and point the root Kustomization at it — the existing `gotk-sync.yaml` stub already does this (`path: ./k8s`).

**Why it's wrong:** Raw kubectl manifests and Flux HelmRelease objects are different paradigms. Mixing them in one Kustomization makes ordering and dependency management brittle. Flux expects to own the namespace of objects it reconciles — manually-applied objects in the same namespace will conflict or get pruned.

**Do this instead:** Point the root Kustomization at `flux/flux-system/` and add a second Kustomization for `flux/apps/`. Delete `k8s/` raw manifests once HelmReleases are confirmed working.

### Anti-Pattern 2: Using ChartVersion reconcileStrategy for Local Charts

**What people do:** Leave reconcileStrategy at its default (`ChartVersion`) and forget to bump `version` in `Chart.yaml` when making template changes.

**Why it's wrong:** Flux will NOT rebuild the chart artifact if only templates change — only if `Chart.yaml`'s `version` field increments. This makes local chart iteration invisible to Flux; changes appear to do nothing.

**Do this instead:** Set `reconcileStrategy: Revision` in the HelmRelease's `chart.spec`. This triggers artifact rebuild on every git commit to the chart path.

### Anti-Pattern 3: HelmRelease Namespace != targetNamespace

**What people do:** Create HelmRelease in the `jellyfin` namespace (matching the app) and omit `targetNamespace`.

**Why it's wrong:** Flux best practice is to keep HelmRelease objects in `flux-system` (or a dedicated `flux` namespace) and use `targetNamespace` to deploy into the app namespace. If you delete the app namespace, you delete the HelmRelease, and Flux can't recreate it.

**Do this instead:** HelmRelease in `flux-system`, deploy via `targetNamespace: jellyfin`. The flux-system namespace persists independently of app namespaces.

### Anti-Pattern 4: Hand-Editing gotk-components.yaml

**What people do:** Directly edit `flux/flux-system/gotk-components.yaml` to change Flux controller settings.

**Why it's wrong:** This file is regenerated by `flux bootstrap` on every upgrade. Manual edits are overwritten. Flux upgrades become destructive.

**Do this instead:** Use Flux's `flux bootstrap` with flags, or create a Kustomization patch that overlays changes on top of the generated components.

## Integration Points

### flux bootstrap git → Existing Repo

| What bootstrap does | Impact on this repo |
|---------------------|---------------------|
| Generates `flux/flux-system/*.yaml` | New files committed and pushed |
| Creates `flux-system` namespace in cluster | Adds to cluster, no conflict |
| Deploys Flux controllers as Deployments | New pods in flux-system ns |
| Stores SSH private key as K8s Secret `flux-system/flux-system` | Cluster-only, not in git |
| Points GitRepository at `--url` and `--path` | Watches `./flux/flux-system` dir |

### GitRepository → HelmChart → HelmRelease Linkage

| Resource | Namespace | References |
|----------|-----------|------------|
| GitRepository `flux-system` | flux-system | External — SSH URL, branch: main |
| HelmChart `flux-system-jellyfin` | flux-system | GitRepository `flux-system`, path `./charts/jellyfin` |
| HelmRelease `jellyfin` | flux-system | HelmChart (created implicitly), targetNamespace: jellyfin |
| Kustomization `apps` | flux-system | GitRepository `flux-system`, path `./flux/apps` |

The GitRepository is reused by both the Kustomization (to sync HelmRelease YAML) and the HelmChart (to fetch the chart source). One GitRepository object serves both purposes.

### Makefile Integration

Bootstrap must be invokable via `make bootstrap-flux` per CLAUDE.md constraints. The Makefile target wraps:

```bash
KUBECONFIG=~/.kube/config-pi-k3s flux bootstrap git \
  --url=ssh://git@github.com/kdavis586/pi-k3s-homelab \
  --branch=main \
  --path=./flux/flux-system \
  --private-key-file=~/.ssh/flux-deploy-key
```

Post-bootstrap, `make deploy` should be removed. `make flux-reconcile` (wrapping `flux reconcile kustomization flux-system --with-source`) serves as the manual trigger.

## Sources

- [Manage Helm Releases — Flux official docs](https://fluxcd.io/flux/guides/helmreleases/) — HIGH confidence
- [HelmChart source object — Flux official docs](https://fluxcd.io/flux/components/source/helmcharts/) — HIGH confidence
- [Bootstrap for generic git servers — Flux official docs](https://fluxcd.io/flux/installation/bootstrap/generic-git-server/) — HIGH confidence
- [Repository structure guide — Flux official docs](https://fluxcd.io/flux/guides/repository-structure/) — HIGH confidence
- [Bootstrap for GitHub — Flux official docs](https://fluxcd.io/flux/installation/bootstrap/github/) — HIGH confidence

---
*Architecture research for: Flux CD GitOps on K3s with local Helm charts*
*Researched: 2026-03-18*
