# Stack Research

**Domain:** Flux CD GitOps on K3s with local Helm charts
**Researched:** 2026-03-18
**Confidence:** HIGH (verified against official Flux docs and GitHub releases)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Flux CD | v2.8.3 (latest patch as of 2026-03-16) | GitOps reconciliation engine | Current stable series; v2.8 adds Helm v4 support and CEL health checks. The four default controllers cover this project's full needs without optional extras. |
| flux CLI | v2.8.3 (matches controller version) | Bootstrap and operational tooling | CLI version must match controller series to avoid API drift. Used for `flux bootstrap` and `flux reconcile` during development. |
| Helm | v3.x (bundled inside helm-controller) | Chart rendering | No separate Helm installation needed — helm-controller ships Helm v3 internally. Helm v4 support added in Flux v2.8 but uses v3 by default; no migration required for new charts. |
| K3s | v1.34+ (existing cluster) | Kubernetes runtime | Already provisioned. Flux has no K3s-specific constraints; the existing cluster requires no changes for Flux installation. |

### Flux Controllers (installed by `flux bootstrap`)

| Controller | Purpose | Required For This Project |
|------------|---------|--------------------------|
| source-controller | Fetches GitRepository artifacts, builds HelmChart objects from local paths | YES — drives all chart sourcing |
| kustomize-controller | Applies Kustomization resources (the `flux-system` sync + per-app Kustomizations) | YES — Flux's own bootstrap manifests require it |
| helm-controller | Reconciles HelmRelease resources, runs install/upgrade/rollback | YES — core of the Helm-based deployment model |
| notification-controller | Routes events to alert providers (Slack, GitHub commit status, etc.) | YES (default) — installed by bootstrap; can be ignored if no alerting is configured |
| image-reflector-controller | Scans image registries for new tags | NO — out of scope (no automated image updates planned) |
| image-automation-controller | Opens PRs / updates manifests when new images are found | NO — out of scope |

The four default controllers (`source-controller,kustomize-controller,helm-controller,notification-controller`) are installed automatically by `flux bootstrap`. No `--components` flag needed unless you want to add the image automation controllers later.

### Local Helm Chart Pattern

This project uses charts stored in `charts/` inside the same repository that Flux watches. The pattern is:

1. **One shared `GitRepository`** (created by `flux bootstrap`, lives in `flux-system`) — points to `main` branch of this repo.
2. **One `HelmRelease` per app**, each with an inline `spec.chart.spec` that references the shared `GitRepository` and a relative path to the chart directory.

No separate `HelmChart` CRD needs to be created manually — the helm-controller generates it automatically from the `spec.chart.spec` template inside a `HelmRelease`.

```yaml
# Example: charts/jellyfin/  (Chart.yaml lives here)
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: jellyfin
  namespace: jellyfin
spec:
  interval: 10m
  chart:
    spec:
      chart: ./charts/jellyfin          # path relative to repo root
      reconcileStrategy: Revision       # re-render on any git change, not just version bump
      sourceRef:
        kind: GitRepository
        name: flux-system               # the GitRepository bootstrap created
        namespace: flux-system
  values:
    nodeSelector:
      kubernetes.io/hostname: apple-pi
```

`reconcileStrategy: Revision` is critical for local charts — without it, helm-controller only re-renders when `Chart.yaml` version is bumped. With `Revision`, any commit that touches the chart directory triggers a reconcile.

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Helm CLI (local) | v3.17+ | Lint and template-test charts locally before push | During chart authoring — `helm lint charts/jellyfin`, `helm template` |
| kubectl (local) | existing | Read-only cluster inspection, `flux` CLI prerequisite | Diagnostics; never for applying cluster state post-bootstrap |
| flux CLI (local) | v2.8.3 | Bootstrap, `flux reconcile`, `flux logs`, `flux get` | Bootstrap step and debugging reconciliation failures |

## Installation

```bash
# Install flux CLI on macOS
curl -s https://fluxcd.io/install.sh | sudo bash
# or via Homebrew
brew install fluxcd/tap/flux

# Verify prerequisites against existing cluster
flux check --pre --kubeconfig ~/.kube/config-pi-k3s

# Bootstrap (SSH deploy key mode — no PAT needed after initial setup)
flux bootstrap github \
  --token-auth=false \
  --owner=kdavis586 \
  --repository=pi-k3s-homelab \
  --branch=main \
  --path=k8s/flux-system \
  --kubeconfig ~/.kube/config-pi-k3s

# Install Helm CLI for local chart development
brew install helm
```

Note on `--token-auth=false`: This tells Flux to use an SSH deploy key rather than a GitHub PAT for ongoing Git polling. The initial `flux bootstrap github` still requires a `GITHUB_TOKEN` env var set for the one-time key registration, after which Flux polls via SSH only.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Local `charts/` in same repo via `GitRepository` | OCI registry (`OCIRepository`) | Use OCI when charts are shared across multiple clusters or teams, or when you want immutable versioned artifacts. For a single homelab repo, the added complexity of pushing to `ghcr.io` is not justified. |
| `GitRepository` sourceRef in HelmRelease | Standalone `HelmChart` CRD | Standalone `HelmChart` gives more control (e.g., cross-namespace references) but is verbose. The inline `spec.chart.spec` inside `HelmRelease` is idiomatic for same-repo charts and auto-manages the `HelmChart` lifecycle. |
| `flux bootstrap github` (SSH key) | `flux bootstrap git` (generic Git + SSH URL) | Use `flux bootstrap git` for non-GitHub remotes (GitLab, Gitea, self-hosted). Same repo is GitHub, so `bootstrap github` is the right command — it automates deploy key registration. |
| Default 4 controllers | Adding image automation controllers | Add image automation only when you want Flux to auto-bump image tags in manifests. This project tracks no automated image updates. |
| `reconcileStrategy: Revision` | Default version-based strategy | Default strategy is fine for charts published to a HelmRepository with explicit semver releases. For local charts in git, `Revision` is required to trigger on file changes, not just version bumps. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Flux v1 (WeaveFlux) | End-of-life since 2022; no active development, no security patches | Flux v2 (`fluxcd/flux2`) |
| `flux bootstrap` with `--token-auth` (PAT) for ongoing polling | PAT scopes are broad; SSH deploy key is scoped to read-only on this repo. PAT also expires and requires rotation. | `--token-auth=false` (SSH deploy key) |
| `HelmRepository` pointing to a local directory | `HelmRepository` is for remote HTTP/OCI chart registries. There is no way to point it at a local filesystem path. | `GitRepository` with relative `spec.chart.spec.chart` path |
| Pushing charts to `ghcr.io` (OCI) for a single-repo homelab | Adds a build/push CI step, registry authentication, and image management overhead with no benefit when all charts and clusters are in one repo | `GitRepository` with `charts/` directory |
| `image-reflector-controller` + `image-automation-controller` | Out of scope for this project; adds complexity and requires write access to the repo from the cluster | Not applicable here — manually bump image tags in `values.yaml` |
| Separate GitOps repo | Splits context across two repos for a project this size. Already explicitly called out of scope in `PROJECT.md`. | Mono-repo: infra + charts + Flux manifests all in `pi-k3s-homelab` |
| `HelmRelease` `spec.chartRef` (new in v2.4+) | References a pre-built `HelmChart` or `OCIRepository` object. More powerful but more indirection — requires separately managing the `HelmChart` CRD. | `spec.chart.spec` (inline chart template) for local charts |

## Stack Patterns by Variant

**If using charts that rarely change structure (only values change):**
- `reconcileStrategy: Revision` still recommended — no downside, and prevents surprise "why didn't my chart change deploy?" moments.

**If charts grow to have dependencies (`charts/jellyfin/Chart.yaml` `dependencies:`):**
- Run `helm dependency update charts/jellyfin` locally before pushing.
- Flux does NOT run `helm dependency update` automatically for `GitRepository`-sourced charts.
- Commit the `charts/jellyfin/charts/` vendored dependencies into the repo.

**If adding a third app beyond Jellyfin + Pi-hole:**
- Create `charts/<appname>/` with `Chart.yaml`, `templates/`, `values.yaml`.
- Add a `HelmRelease` in `k8s/<appname>/helmrelease.yaml` using the same `flux-system` `GitRepository` sourceRef pattern.
- No changes to Flux controllers or bootstrap needed.

**If migrating Pi-hole DaemonSet to Helm:**
- Pi-hole uses `hostNetwork: true` and a `DaemonSet`. Both are fully expressible in Helm chart templates.
- The DNS service that was previously `service-dns.yaml` (deleted per git status) should be handled by the Helm chart.
- Keep `hostNetwork: true` in the DaemonSet template and document it in `values.yaml`.

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| flux CLI v2.8.x | K3s v1.28+ | Flux v2.8 requires Kubernetes 1.28+ for server-side apply features in helm-controller. K3s v1.34 is well within range. |
| Helm v3.x (helm-controller bundled) | Existing K3s cluster | No separate Helm version management needed. helm-controller ships its own Helm binary. |
| `HelmRelease` API `helm.toolkit.fluxcd.io/v2` | Flux v2.3+ | The `v2` API (non-beta) has been stable since Flux v2.3.0. Use `v2`, not `v2beta1` or `v2beta2` — those are deprecated. |
| `source.toolkit.fluxcd.io/v1` (GitRepository) | Flux v2.1+ | `v1` GitRepository API is stable. Do not use `v1beta2`. |
| `kustomize.toolkit.fluxcd.io/v1` (Kustomization) | Flux v2.1+ | `v1` Kustomization API is stable. |

## Sources

- [Flux GitHub Releases — fluxcd/flux2](https://github.com/fluxcd/flux2/releases) — v2.8.3 latest confirmed (HIGH confidence)
- [Announcing Flux v2.8 GA — fluxcd.io](https://fluxcd.io/blog/2026/02/flux-v2.8.0/) — v2.8 feature set (HIGH confidence)
- [Manage Helm Releases — fluxcd.io](https://fluxcd.io/flux/guides/helmreleases/) — GitRepository + HelmRelease local chart pattern (HIGH confidence)
- [HelmCharts API — fluxcd.io](https://fluxcd.io/flux/components/source/helmcharts/) — `reconcileStrategy: Revision` behavior for GitRepository sources (HIGH confidence)
- [flux bootstrap command — fluxcd.io](https://fluxcd.io/flux/cmd/flux_bootstrap/) — default components list (HIGH confidence)
- [Bootstrap GitHub — fluxcd.io](https://fluxcd.io/flux/installation/bootstrap/github/) — SSH deploy key bootstrap flags (HIGH confidence)
- [Pi Cluster FluxCD — picluster.ricsanfre.com](https://picluster.ricsanfre.com/docs/fluxcd/) — Real-world K3s + Flux homelab implementation (MEDIUM confidence, community source)

---
*Stack research for: Flux CD GitOps migration on K3s Raspberry Pi homelab*
*Researched: 2026-03-18*
