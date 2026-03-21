---
phase: quick
plan: 260321-ik3
subsystem: helm-charts
tags: [helm, flux, conventions, labels, gitops]
dependency_graph:
  requires: []
  provides:
    - standard app.kubernetes.io labels on all chart resources
    - _helpers.tpl patterns for future chart additions
    - Flux-managed namespace lifecycle (createNamespace: true)
  affects:
    - charts/jellyfin
    - charts/pihole
    - flux/apps
tech_stack:
  added: []
  patterns:
    - Helm named templates (_helpers.tpl) for label reuse
    - app.kubernetes.io/* label set (name, instance, version, managed-by)
    - helm.sh/chart label for chart version tracking
    - Flux install.createNamespace: true replaces in-chart Namespace resources
key_files:
  created:
    - charts/jellyfin/templates/_helpers.tpl
    - charts/jellyfin/.helmignore
    - charts/pihole/templates/_helpers.tpl
    - charts/pihole/.helmignore
  modified:
    - charts/jellyfin/templates/deployment.yaml
    - charts/jellyfin/templates/service.yaml
    - charts/jellyfin/templates/ingress.yaml
    - charts/jellyfin/templates/pvc.yaml
    - charts/pihole/templates/deployment.yaml
    - charts/pihole/templates/service-web.yaml
    - charts/pihole/templates/ingress.yaml
    - charts/pihole/templates/configmap-custom-dns.yaml
    - flux/apps/jellyfin.yaml
    - flux/apps/pihole.yaml
  deleted:
    - charts/jellyfin/templates/namespace.yaml
    - charts/pihole/templates/namespace.yaml
decisions:
  - "_helpers.tpl fullname returns chart name directly — single-instance homelab chart, avoids release-name prefix on all resources"
  - "selectorLabels uses only name+instance (immutable subset) while labels adds version, managed-by, helm.sh/chart"
  - "Namespace resources deleted from charts; Flux createNamespace: true handles lifecycle"
metrics:
  duration: 96s
  completed_date: "2026-03-21T20:26:07Z"
  tasks_completed: 2
  files_changed: 14
---

# Phase quick Plan 260321-ik3: Align Project Structure and Conventions Summary

**One-liner:** Standard `app.kubernetes.io/*` labels, `_helpers.tpl` scaffolding, and Flux-managed namespaces added to both Helm charts.

## What Was Built

Both Helm charts (jellyfin, pihole) were aligned with Helm and Flux community conventions:

1. `_helpers.tpl` added to each chart defining `name`, `fullname`, `chart`, `labels`, and `selectorLabels` named templates following the standard `helm create` scaffold pattern.

2. All template files in both charts now use `include "*.labels"` for `metadata.labels` and `include "*.selectorLabels"` for `spec.selector.matchLabels` and pod template labels — replacing hardcoded `app: jellyfin` / `app: pihole`.

3. `namespace.yaml` removed from both charts. Flux HelmReleases updated to `install.createNamespace: true`, which is the standard Flux convention for namespace lifecycle.

4. `.helmignore` added to both charts with standard entries.

All existing functionality preserved: nodeSelector pinning, Recreate strategy with comments, initContainer (USB wait), liveness/readiness probes, hostNetwork + NET_ADMIN for Pi-hole DHCP, hardcoded `namespace: jellyfin` / `namespace: pihole` (per project decision).

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Add _helpers.tpl and .helmignore to both charts | 473190e | 4 created |
| 2 | Update templates with standard labels; delete namespace.yaml; update Flux HelmReleases | b2c2ef7 | 10 modified, 2 deleted |

## Verification Results

- `helm template test charts/jellyfin` renders 7 resources, all with `app.kubernetes.io/name: jellyfin`
- `helm template test charts/pihole` renders 5 resources, all with `app.kubernetes.io/name: pihole`
- Both charts have `app.kubernetes.io/managed-by: Helm` on all resources
- `charts/jellyfin/templates/namespace.yaml` — deleted
- `charts/pihole/templates/namespace.yaml` — deleted
- `flux/apps/jellyfin.yaml` — `createNamespace: true`
- `flux/apps/pihole.yaml` — `createNamespace: true`

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- charts/jellyfin/templates/_helpers.tpl — FOUND
- charts/pihole/templates/_helpers.tpl — FOUND
- charts/jellyfin/.helmignore — FOUND
- charts/pihole/.helmignore — FOUND
- charts/jellyfin/templates/namespace.yaml — correctly absent
- charts/pihole/templates/namespace.yaml — correctly absent
- Commits 473190e and b2c2ef7 — FOUND
