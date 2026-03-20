---
phase: 03-migration-and-ownership-transfer
verified: 2026-03-20T12:00:00Z
status: human_needed
score: 7/7 automated must-haves verified
gaps: []
human_verification:
  - test: "Open http://jellyfin.local in a browser on the LAN"
    expected: "Jellyfin web UI loads with existing media library intact (not a fresh empty instance)"
    why_human: "Network service accessibility and media library state cannot be verified programmatically from dev machine"
  - test: "Open http://pihole.local or http://192.168.1.102/admin on a LAN device"
    expected: "Pi-hole admin UI loads — no password required (WEBPASSWORD disabled)"
    why_human: "Network service accessibility cannot be verified programmatically from dev machine"
  - test: "On any LAN device (not the cluster nodes), ping or browse to a public domain"
    expected: "DNS resolution works — Pi-hole is serving as LAN resolver via custom.list"
    why_human: "DNS resolution behavior on LAN clients requires a device on the LAN to test"
  - test: "Run: make flux-status (or flux get helmreleases -A --kubeconfig ~/.kube/config-pi-k3s)"
    expected: "Both jellyfin and pihole HelmReleases show READY=True, no errors"
    why_human: "Live cluster state requires kubectl/flux access; cannot be verified from static codebase analysis"
---

# Phase 3: Migration and Ownership Transfer — Verification Report

**Phase Goal:** Jellyfin and Pi-hole are fully owned by Flux HelmReleases; no kubectl-applied resources remain; pruning is enabled
**Verified:** 2026-03-20T12:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Both Jellyfin and Pi-hole HelmReleases show READY=True with no field manager conflicts | ? HUMAN NEEDED | HelmRelease manifests are correct and `upgrade.force` removed — live cluster state requires human confirmation |
| 2 | Jellyfin accessible at http://jellyfin.local; Pi-hole web UI accessible after migration | ? HUMAN NEEDED | Commits document approval by human; cannot re-verify network access statically |
| 3 | `prune: true` is enabled on the apps Kustomization | VERIFIED | `flux/flux-system/apps-kustomization.yaml` line 13: `prune: true` |
| 4 | `k8s/jellyfin/` and `k8s/pihole/` directories no longer exist in the repo | VERIFIED | Both dirs absent from working tree; git confirms deletion in commit `393000d` |

**Automated score:** 2/2 statically verifiable truths confirmed. 2/4 truths require live cluster (human needed).

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `flux/apps/jellyfin.yaml` | HelmRelease referencing `./charts/jellyfin` | VERIFIED | Exists, 20 lines, references `chart: ./charts/jellyfin`, no `upgrade.force` |
| `flux/apps/pihole.yaml` | HelmRelease referencing `./charts/pihole` | VERIFIED | Exists, 20 lines, references `chart: ./charts/pihole`, no `upgrade.force` |
| `flux/flux-system/apps-kustomization.yaml` | Kustomization with `prune: true` | VERIFIED | Exists, `prune: true` confirmed on line 13 |
| `charts/pihole/templates/configmap-custom-dns.yaml` | Custom DNS ConfigMap for LAN hostnames | VERIFIED | File exists at `charts/pihole/templates/configmap-custom-dns.yaml`, templates `localDns` values into Pi-hole `custom.list` |
| `charts/pihole/templates/deployment.yaml` | Deployment (not DaemonSet) pinned to pumpkin-pi | VERIFIED | Exists, kind=Deployment, `nodeSelector: kubernetes.io/hostname: pumpkin-pi`, `strategy.type: Recreate` |
| `charts/pihole/values.yaml` | nodeSelector + localDns entries | VERIFIED | Contains `nodeSelector.hostname: pumpkin-pi` and `localDns` entries for jellyfin.local (192.168.1.101) and pihole.local (192.168.1.102) |

**Note:** SUMMARY.md refers to the custom DNS file as `custom-dns-configmap.yaml` but the actual file is `charts/pihole/templates/configmap-custom-dns.yaml`. The file exists and is correct; this is a naming inconsistency in the SUMMARY only, not a functional issue.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `flux/apps/jellyfin.yaml` | `charts/jellyfin/` | `spec.chart.spec.chart: ./charts/jellyfin` | WIRED | Pattern confirmed in file |
| `flux/apps/pihole.yaml` | `charts/pihole/` | `spec.chart.spec.chart: ./charts/pihole` | WIRED | Pattern confirmed in file |
| `flux/flux-system/apps-kustomization.yaml` | `flux/apps/` | `spec.path: ./flux/apps`, `prune: true` | WIRED | Path and prune both confirmed |
| `charts/pihole/templates/configmap-custom-dns.yaml` | `charts/pihole/templates/deployment.yaml` | `volumeMounts.name: custom-dns` mounting `pihole-custom-dns` ConfigMap | WIRED | ConfigMap name `pihole-custom-dns` matches volume reference in deployment template |
| Flux helm-controller | jellyfin namespace resources | HelmRelease READY=True (live cluster) | HUMAN NEEDED | Cannot verify live controller state statically |
| Flux helm-controller | pihole namespace resources | HelmRelease READY=True (live cluster) | HUMAN NEEDED | Cannot verify live controller state statically |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MIG-01 | 03-01-PLAN.md | Existing kubectl-applied Jellyfin resources deleted and recreated under HelmRelease ownership | VERIFIED | `eaaf6c9` deleted Jellyfin Deployment/Service/IngressRoute; `flux/apps/jellyfin.yaml` exists with correct chart ref; no `upgrade.force` remaining; SUMMARY reports human-approved UI verification |
| MIG-02 | 03-02-PLAN.md | Existing kubectl-applied Pi-hole resources deleted and recreated under HelmRelease ownership | VERIFIED (human gate) | `1ab1c8e` committed; `flux/apps/pihole.yaml` correct; DaemonSet converted to Deployment; live READY=True requires human confirmation |
| MIG-03 | 03-02-PLAN.md | `prune: true` re-enabled on apps Kustomization after Flux owns all workload resources | VERIFIED | `flux/flux-system/apps-kustomization.yaml` line 13 contains `prune: true`; committed in `393000d` |
| MIG-04 | 03-02-PLAN.md | Raw manifests in `k8s/jellyfin/` and `k8s/pihole/` deleted from repo | VERIFIED | Neither directory exists in working tree; git confirms 9-file deletion in `393000d` (k8s/jellyfin/*.yaml, k8s/pihole/*.yaml); `k8s/pihole/service-dns.yaml` deleted in `eaaf6c9`; remaining `k8s/` contents are unrelated storage/template files |

**Orphaned requirements check:** No requirements mapped to Phase 3 in REQUIREMENTS.md beyond MIG-01 through MIG-04. All four are accounted for.

---

### Anti-Patterns Found

No anti-patterns found. Scanned: `flux/apps/jellyfin.yaml`, `flux/apps/pihole.yaml`, `flux/flux-system/apps-kustomization.yaml`, `charts/pihole/templates/configmap-custom-dns.yaml`, `charts/pihole/templates/deployment.yaml`, `charts/pihole/values.yaml`.

- No TODO/FIXME/placeholder comments
- No stub return values
- `upgrade.force: true` was correctly removed from both HelmReleases after successful transfer (confirmed absent)

---

### Human Verification Required

#### 1. Jellyfin web UI and media library

**Test:** Open `http://jellyfin.local` in a browser on any LAN device
**Expected:** Jellyfin web UI loads; existing media library is visible (confirms PVC jellyfin-config was preserved through ownership transfer — not a fresh empty instance)
**Why human:** Network service availability and PVC data integrity cannot be verified from static codebase analysis

#### 2. Pi-hole web UI accessibility

**Test:** Open `http://pihole.local` or `http://192.168.1.102/admin` on a LAN device
**Expected:** Pi-hole admin UI loads with no password prompt (WEBPASSWORD disabled via `FTLCONF_webserver_api_password: ""`)
**Why human:** Network accessibility requires a device on the LAN

#### 3. LAN DNS resolution via Pi-hole custom.list

**Test:** On any LAN device (not cluster nodes), navigate to `http://jellyfin.local` and `http://pihole.local`
**Expected:** Both hostnames resolve via Pi-hole custom DNS (192.168.1.101 and 192.168.1.102 respectively) without per-device configuration
**Why human:** DNS resolution behavior on LAN clients cannot be verified from the dev machine; Android/Windows devices are the key targets since mDNS was abandoned in favor of custom.list

#### 4. Live HelmRelease READY=True state

**Test:** Run `flux get helmreleases -A --kubeconfig ~/.kube/config-pi-k3s`
**Expected:** Both `jellyfin` and `pihole` rows show `READY=True` with no error messages
**Why human:** Live cluster state requires kubectl/flux access to the running cluster; this confirms Flux helm-controller ownership is active, not just that the manifest files are correct

---

### Gaps Summary

No automated gaps found. All statically verifiable must-haves are confirmed:

- Both HelmRelease manifests exist, reference correct chart paths, and have no stale `upgrade.force` flags
- `prune: true` is live in the apps Kustomization
- `k8s/jellyfin/` and `k8s/pihole/` are fully removed (committed, not just deleted locally)
- Pi-hole chart was correctly converted from DaemonSet to Deployment pinned to pumpkin-pi
- Custom DNS ConfigMap (`pihole-custom-dns`) is properly wired into the Pi-hole deployment via volume mount
- `flux_version` updated to `v2.8.3` in `ansible/group_vars/all.yaml`

The four items flagged for human verification are runtime/network checks that require a live cluster connection. SUMMARY.md documents human approval of the Task 2 and Task 3 checkpoints, which covers the Jellyfin UI and Pi-hole DNS tests. The live HelmRelease READY=True state is the primary outstanding check.

---

_Verified: 2026-03-20T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
