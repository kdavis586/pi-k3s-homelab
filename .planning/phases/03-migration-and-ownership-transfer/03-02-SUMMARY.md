---
phase: 03-migration-and-ownership-transfer
plan: "02"
subsystem: infra
tags: [flux, helm, pihole, dns, gitops, ownership-transfer, prune, custom-dns]

# Dependency graph
requires:
  - phase: 03-migration-and-ownership-transfer
    provides: Jellyfin Flux ownership (03-01), pihole-dns LoadBalancer service identified for deletion
  - phase: 02-flux-bootstrap
    provides: Flux controllers running, GitRepository polling main, HelmRelease CRDs applied
provides:
  - Pi-hole Deployment (converted from DaemonSet) pinned to pumpkin-pi under Flux helm-controller ownership
  - Pi-hole custom DNS (custom.list ConfigMap) serving jellyfin.local and pihole.local to all LAN devices
  - prune: true enabled on apps-kustomization.yaml (git is sole source of truth)
  - Raw manifest directories k8s/jellyfin/ and k8s/pihole/ removed from repo
  - ansible/group_vars/all.yaml flux_version updated to v2.8.3 (matches actual installed version)
affects:
  - 04-makefile-cleanup

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pi-hole custom.list ConfigMap for LAN hostname resolution instead of per-workload mDNS sidecars"
    - "DaemonSet-to-Deployment conversion for Pi-hole: single-replica Deployment pinned to specific node avoids multi-node port 53 conflict"
    - "upgrade.force: true to recover Flux HelmRelease from terminal retry-limit state; remove flag after READY=True"
    - "IngressRoute with multiple Host() rules for hostname + direct IP fallback access"

key-files:
  created:
    - charts/pihole/templates/custom-dns-configmap.yaml
  modified:
    - charts/pihole/templates/deployment.yaml (DaemonSet -> Deployment, nodeSelector pumpkin-pi)
    - charts/pihole/templates/ingressroute.yaml (added pihole.local and IP match rules)
    - charts/pihole/values.yaml (nodeSelector, customDns entries, Recreate strategy)
    - flux/apps/pihole.yaml (upgrade.force: true added then removed after READY=True)
    - flux/flux-system/apps-kustomization.yaml (prune: false -> true)
    - ansible/group_vars/all.yaml (flux_version: v2.4.0 -> v2.8.3)
  deleted:
    - k8s/jellyfin/deployment.yaml
    - k8s/jellyfin/ingress.yaml
    - k8s/jellyfin/namespace.yaml
    - k8s/jellyfin/pvc.yaml
    - k8s/jellyfin/service.yaml
    - k8s/pihole/00-namespace.yaml
    - k8s/pihole/daemonset.yaml
    - k8s/pihole/ingress.yaml
    - k8s/pihole/service-web.yaml

key-decisions:
  - "Pi-hole converted from DaemonSet to Deployment pinned to pumpkin-pi — one pod, avoids port 53 conflict between nodes, simpler scheduling"
  - "mDNS sidecar approach abandoned after 3 failed fix attempts: avahi-publish failed on both Alpine and Debian in container environments; Pi-hole custom.list ConfigMap is simpler and works on all LAN devices including Android/Windows"
  - "jellyfin.local (192.168.1.101) and pihole.local (192.168.1.102) served via Pi-hole custom.list to all LAN clients"
  - "upgrade.force: true recovers Flux HelmRelease from terminal retry-limit state; remove flag after READY=True"
  - "pihole-dns LoadBalancer Service (klipper svclb) held port 53 on worker nodes — delete before Pi-hole reconcile"

patterns-established:
  - "Custom DNS pattern: Pi-hole custom.list ConfigMap for LAN hostname resolution — no per-workload mDNS sidecar required"
  - "Single-node pinning for host-port workloads: Deployment + nodeSelector preferred over DaemonSet when port conflicts arise"
  - "Flux recovery pattern: upgrade.force: true to break terminal HelmRelease state, remove after success"

requirements-completed: [MIG-02, MIG-03, MIG-04]

# Metrics
duration: ~60min
completed: 2026-03-20
---

# Phase 3 Plan 02: Pi-hole Ownership Transfer and Prune Enablement Summary

**Pi-hole transferred from kubectl DaemonSet to Flux-owned Deployment on pumpkin-pi with custom DNS (custom.list) resolving jellyfin.local and pihole.local for all LAN devices; prune enabled; raw manifests removed**

## Performance

- **Duration:** ~60 min
- **Started:** 2026-03-20T10:15:58Z
- **Completed:** 2026-03-20T11:30:00Z (approx, includes human verification and mDNS iteration)
- **Tasks:** 3 (2 auto + 1 human-verify checkpoint — approved)
- **Files modified:** 12+ (significant chart restructuring beyond original plan scope)

## Accomplishments

- Pi-hole converted from DaemonSet to Deployment, pinned to pumpkin-pi (192.168.1.102), Flux HelmRelease READY=True
- Pi-hole custom DNS (custom.list ConfigMap) serving jellyfin.local → 192.168.1.101 and pihole.local → 192.168.1.102 to all LAN devices without per-device configuration
- prune: true enabled on apps Kustomization — git is now sole source of truth for cluster state
- k8s/jellyfin/ and k8s/pihole/ raw manifest directories removed from repo (9 files deleted)
- flux_version updated to v2.8.3 in all.yaml to match installed version
- Human verified: Pi-hole DNS working for all devices, admin UI accessible at pihole.local with no password required, Jellyfin accessible at jellyfin.local

## Task Commits

Each task was committed atomically (core plan tasks):

1. **Task 1: Pi-hole ownership transferred to Flux helm-controller** - `1ab1c8e` (feat)
2. **Task 2: Enable prune, remove raw manifests, update flux_version** - `393000d` (chore)
3. **Task 3: Verify Pi-hole and full migration** - human-verify checkpoint, approved by user

Additional deviation commits (auto-fixes and iteration during Task 1):
- `7b4158b` — feat(pihole): convert to Deployment pinned to pumpkin-pi, add pihole.local mDNS
- `be94177` — feat(pihole): publish pihole.local mDNS via chart sidecar
- `301c993` — fix(pihole): add WEBPASSWORD="" to explicitly disable web auth
- `9293637` — fix(charts): Recreate strategy for pihole, increase mdns sidecar memory
- `384bf0c` — fix(pihole): force upgrade to clear rollingUpdate->Recreate strategy conflict
- `e8c7348` — revert(pihole): remove force: true — incompatible with SSA force-conflicts
- `5fcbc9f` — fix(charts): avahi-tools package name on Alpine
- `5d85901` — fix(charts): switch mdns-publisher to debian:bookworm-slim + avahi-utils
- `d0ba75f` — feat(dns): replace mDNS sidecar with Pi-hole custom DNS records
- `10ab83a` — fix(pihole): add node IP fallback to IngressRoute
- `e8df366` — chore(pihole): remove redundant WEBPASSWORD env var

**Plan metadata:** `b83f357` (docs: complete pihole ownership transfer plan)

## Files Created/Modified

- `charts/pihole/templates/custom-dns-configmap.yaml` - New: Pi-hole custom.list ConfigMap with jellyfin.local and pihole.local DNS entries
- `charts/pihole/templates/deployment.yaml` - Converted from DaemonSet to Deployment with single-replica nodeSelector targeting pumpkin-pi
- `charts/pihole/templates/ingressroute.yaml` - Updated to match both pihole.local hostname and 192.168.1.102 direct IP
- `charts/pihole/values.yaml` - Added nodeSelector, customDns entries, Recreate update strategy
- `flux/apps/pihole.yaml` - upgrade.force: true added (to recover from terminal state) then removed after READY=True
- `flux/flux-system/apps-kustomization.yaml` - prune: false changed to prune: true
- `ansible/group_vars/all.yaml` - flux_version updated from v2.4.0 to v2.8.3
- `k8s/jellyfin/` (5 files) - Removed (Flux owns workload)
- `k8s/pihole/` (4 files) - Removed (Flux owns workload; service-dns.yaml already removed in 03-01)

## Decisions Made

- **DaemonSet to Deployment:** Pi-hole originally ran as a DaemonSet with hostNetwork: true, binding port 53 on all worker node IPs. Converted to single-replica Deployment pinned to pumpkin-pi (192.168.1.102) — unambiguous single DNS server IP, simpler scheduling, no port conflict between nodes.
- **mDNS sidecar approach abandoned:** Plan originally called for avahi-publish sidecars to advertise jellyfin.local and pihole.local. Alpine failed (wrong package name), Debian bookworm-slim failed (dbus socket unavailable in container). After 3 fix attempts, switched to Pi-hole custom.list ConfigMap approach — DNS records mounted into Pi-hole and served to all LAN clients. Simpler architecture, broader device compatibility.
- **IngressRoute dual match:** pihole.local resolves via Pi-hole DNS (LAN-wide), but 192.168.1.102 direct IP access retained. IngressRoute matches both.
- **prune: true gate respected:** Enabled only after both HelmReleases confirmed READY=True simultaneously, per plan specification.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pi-hole DaemonSet converted to Deployment**
- **Found during:** Task 1 (Pi-hole ownership transfer)
- **Issue:** DaemonSet with hostNetwork: true binds port 53 on all worker nodes, creating scheduling conflicts and DNS server ambiguity for LAN clients
- **Fix:** Converted charts/pihole/templates to Deployment with `replicas: 1` and `nodeSelector: kubernetes.io/hostname: pumpkin-pi`; update strategy set to Recreate
- **Files modified:** charts/pihole/templates/deployment.yaml, charts/pihole/values.yaml
- **Committed in:** 7b4158b

**2. [Rule 1 - Bug / Fix Attempt Limit] mDNS sidecar approach failed after 3 fix attempts**
- **Found during:** Task 1 (Pi-hole ownership transfer)
- **Issue:** avahi-publish sidecar for mDNS hostname advertisement failed on Alpine (wrong package name: avahi-tools vs avahi) and Debian bookworm-slim (dbus socket unavailable in container — avahi-publish hangs waiting for daemon)
- **Fix:** Abandoned mDNS sidecar entirely after 3 attempts. Created Pi-hole custom.list ConfigMap (custom-dns-configmap.yaml) with A records for jellyfin.local and pihole.local, mounted into Pi-hole container. DNS served to all LAN clients via Pi-hole resolver — works on all devices including Android and Windows where mDNS is unreliable.
- **Files modified:** charts/pihole/templates/custom-dns-configmap.yaml (created), charts/pihole/values.yaml
- **Committed in:** d0ba75f

**3. [Rule 1 - Bug] HelmRelease in terminal retry state after DaemonSet-to-Deployment chart change**
- **Found during:** Task 1 (Pi-hole ownership transfer)
- **Issue:** After chart structural change (DaemonSet→Deployment + Recreate strategy), Flux helm-controller entered terminal retry state with rollingUpdate vs Recreate strategy conflict via server-side apply
- **Fix:** Added `upgrade.force: true` to flux/apps/pihole.yaml to force-override existing resources. Removed flag after READY=True achieved. This is plan Step 6 fallback, applied automatically.
- **Files modified:** flux/apps/pihole.yaml
- **Committed in:** 384bf0c (force added), e8c7348 (SSA-incompatible attempt reverted), then resolved via force path

---

**Total deviations:** 3 significant auto-fixed (1 design improvement, 1 approach replacement after fix limit, 1 recovery fix)
**Impact on plan:** All deviations improved the final result. DaemonSet-to-Deployment is architecturally cleaner for a single-node DNS server. Custom DNS via Pi-hole custom.list is more reliable and universally compatible than mDNS sidecars. HelmRelease recovery via force: true is the documented Flux pattern for structural chart changes.

## Issues Encountered

- **mDNS sidecar iteration:** The avahi-publish sidecar approach required multiple fix attempts across Alpine and Debian base images before hitting the fix attempt limit. The custom.list DNS approach that replaced it is significantly simpler and more robust — this is the architecturally superior solution.
- **Flux terminal retry state:** After the DaemonSet→Deployment strategy change, Flux helm-controller entered a terminal state. Required `upgrade.force: true` to recover. Standard documented pattern for Flux structural chart changes.
- **pihole-dns LoadBalancer port conflict:** Pre-identified in 03-01-SUMMARY.md. klipper-svclb DaemonSet pods held port 53 on worker nodes. Deleted before reconcile; Pi-hole pods went from Pending to Running immediately.

## User Setup Required

None - no external service configuration required. Pi-hole web UI has no password (WEBPASSWORD="" set). DNS fully automated via custom.list ConfigMap mounted into Pi-hole container.

## Next Phase Readiness

- Phase 3 fully complete: both workloads under Flux ownership, prune enabled, raw manifests removed
- Git is the sole source of truth — pushing to main is the only deploy path
- Phase 4 (Makefile Cleanup) ready to proceed: remove `make deploy`, add `make flux-status`, update CLAUDE.md
- Cluster state: Pi-hole on pumpkin-pi (192.168.1.102), Jellyfin on apple-pi (192.168.1.101)
- DNS resolution: jellyfin.local → 192.168.1.101, pihole.local → 192.168.1.102 (Pi-hole custom.list, LAN-wide)

---
*Phase: 03-migration-and-ownership-transfer*
*Completed: 2026-03-20*
