# Session Handoff — 2026-03-21

## Current Cluster State

- **All 3 nodes**: Ready
- **Flux**: Reconciled on commit `908f1c7`
- **Jellyfin**: Scaled to 0 (intentional — user left mid-session)
- **Pi-hole**: Running on pumpkin-pi (.102)

## What Happened This Session

1. Ran `/gsd:quick` — aligned charts with Helm industry standards (`_helpers.tpl`, `.helmignore`, `app.kubernetes.io/*` labels, moved namespace mgmt to charts)
2. README updated: mermaid diagram simplified to hardware-only, services table added, mDNS references removed (jellyfin.internal resolved via Pi-hole DNS, not avahi)
3. Makefile: `flux-reconcile` renamed to `flux-sync`, `flux-retry` added
4. **Incident**: label change (app: → app.kubernetes.io/name:) made Deployment selector immutable → Helm upgrade failed → deleted namespaces → local-path-provisioner wiped Jellyfin config data before it could be copied
5. **Fix applied**: Jellyfin now uses static PV (`persistentVolumeReclaimPolicy: Retain`) pinned to `/mnt/usb-storage/jellyfin-config` — data survives namespace/PVC deletion from here on

## Jellyfin Status

- Pod scaled to 0
- Static PV `jellyfin-config` is Bound, pointing to `/mnt/usb-storage/jellyfin-config`
- Config data was lost in the incident — **needs first-run wizard on next startup**
- Media files (`/mnt/usb-storage/media/`) are untouched

## To Resume Jellyfin

```bash
kubectl --kubeconfig ~/.kube/config-pi-k3s scale deployment jellyfin -n jellyfin --replicas=1
```

Then navigate to `http://jellyfin.internal` or `http://192.168.1.101` and complete the setup wizard. Point libraries at `/media/movies` and `/media/shows`.

## Open Questions (user wants to follow up)

- TBD — user left mid-session

## Cluster Access

```bash
make status         # node/pod overview
make flux-status    # Flux reconciliation state
make flux-sync      # force git pull + apply
make flux-retry     # reset failed HelmReleases
```
