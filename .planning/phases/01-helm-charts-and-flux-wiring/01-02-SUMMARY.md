---
phase: 01-helm-charts-and-flux-wiring
plan: 02
subsystem: infra
tags: [helm, pihole, kubernetes, daemonset, traefik, ingressroute]

# Dependency graph
requires: []
provides:
  - charts/pihole/ Helm chart converting raw k8s/pihole/ manifests
  - DaemonSet template with hostNetwork, NET_ADMIN, nodeAffinity, all FTLCONF env vars
  - Traefik IngressRoute template for pihole.local
  - ClusterIP service template for pihole-web
  - Namespace template
affects: [flux-wiring, phase-02-flux-bootstrap]

# Tech tracking
tech-stack:
  added: [helm v4.1.3]
  patterns: [local helm chart in charts/ directory, hardcoded namespace in templates, values extraction from raw manifests]

key-files:
  created:
    - charts/pihole/Chart.yaml
    - charts/pihole/values.yaml
    - charts/pihole/templates/namespace.yaml
    - charts/pihole/templates/daemonset.yaml
    - charts/pihole/templates/service-web.yaml
    - charts/pihole/templates/ingress.yaml
  modified: []

key-decisions:
  - "Hardcode namespace: pihole in all templates (not Release.Namespace) — chart is single-purpose, namespace is not a deployment variable"
  - "Traefik IngressRoute uses traefik.io/v1alpha1 CRD (not standard networking.k8s.io/v1 Ingress) — required for K3s bundled Traefik"
  - "Env vars iterated via range over .Values.env map — order differs from original but all vars present"

patterns-established:
  - "Chart scaffold: Chart.yaml + values.yaml with all configurable values extracted from source manifests"
  - "DaemonSet affinity: nodeAffinity.key + nodeAffinity.values list in values.yaml, rendered via toYaml nindent"
  - "Resources block: toYaml .Values.resources | nindent 12 for clean indentation"

requirements-completed: [CHART-03, CHART-04]

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 1 Plan 2: Pi-hole Helm Chart Summary

**Pi-hole Helm chart with DaemonSet (hostNetwork, NET_ADMIN, nodeAffinity), Traefik IngressRoute CRD, and full FTLCONF env var extraction from existing raw manifests**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-19T02:50:45Z
- **Completed:** 2026-03-19T02:52:12Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created complete Helm chart at charts/pihole/ converting 4 raw manifests from k8s/pihole/
- Preserved every constraint: hostNetwork, dnsPolicy ClusterFirstWithHostNet, nodeAffinity for homelab/node-group=workloads, NET_ADMIN capability, all 10 FTLCONF env vars
- `helm template` and `helm lint` both exit 0 with all 6 required strings present in rendered output

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Pi-hole chart scaffold and values** - `57ad4fe` (feat)
2. **Task 2: Create Pi-hole Helm templates from existing manifests** - `6b475b5` (feat)

## Files Created/Modified
- `charts/pihole/Chart.yaml` - Chart metadata: apiVersion v2, version 0.1.0, appVersion 2026.02.0
- `charts/pihole/values.yaml` - All configurable values: image, hostNetwork, dnsPolicy, nodeAffinity, env (10 FTLCONF vars), resources, ingress host, service port
- `charts/pihole/templates/namespace.yaml` - Namespace pihole
- `charts/pihole/templates/daemonset.yaml` - DaemonSet with all constraints preserved via .Values references
- `charts/pihole/templates/service-web.yaml` - ClusterIP pihole-web on port 8080
- `charts/pihole/templates/ingress.yaml` - Traefik IngressRoute (traefik.io/v1alpha1) for pihole.local

## Decisions Made
- Hardcoded `namespace: pihole` in all templates rather than using `{{ .Release.Namespace }}` — the chart is single-purpose and the namespace is not intended to be overridable
- Used Traefik IngressRoute CRD (`traefik.io/v1alpha1`) matching the existing raw manifest — standard Kubernetes Ingress would not work with K3s bundled Traefik for this use case
- Installed helm via brew (Rule 3 auto-fix) — helm was not present on the machine and was required to verify the chart renders correctly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Installed helm CLI via brew**
- **Found during:** Task 2 (verify step)
- **Issue:** `helm` command not found on the machine — required for both `helm template` verification and `helm lint`
- **Fix:** Ran `brew install helm` (installed v4.1.3)
- **Files modified:** None (tool installation)
- **Verification:** `helm template charts/pihole` and `helm lint charts/pihole` both exit 0
- **Committed in:** N/A (tool install, not a code change)

---

**Total deviations:** 1 auto-fixed (1 blocking — missing tool)
**Impact on plan:** Necessary to satisfy verification requirements. No scope creep.

## Issues Encountered
- None during chart authoring. The helm template rendering handled env var map iteration correctly (alphabetical order, all 10 vars present).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- charts/pihole/ is a valid Helm chart ready for Flux HelmRelease wiring in Phase 2
- Chart passes `helm lint` with 0 failures (INFO-level icon warning only, not blocking)
- All constraints from raw manifests preserved — no behavioral change when deployed via Flux vs current raw kubectl apply

---
*Phase: 01-helm-charts-and-flux-wiring*
*Completed: 2026-03-19*

## Self-Check: PASSED

All created files found on disk. Both task commits verified in git history.
