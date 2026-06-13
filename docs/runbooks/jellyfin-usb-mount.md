# Jellyfin USB Mount Runbook

Use this when Jellyfin is healthy in Kubernetes but media/config on `/mnt/usb-storage`
is unavailable on `apple-pi`, or when the Jellyfin pod is stuck in `Init:0/1`.

## Expected State

- `apple-pi` hosts the USB drive and Jellyfin workload.
- The host mount point is `/mnt/usb-storage`.
- Jellyfin config lives on the static PV at `/mnt/usb-storage/jellyfin-config`.
- Jellyfin media is mounted directly from `/mnt/usb-storage/media`.
- The Jellyfin pod waits for the host mount before starting.

Repo sources of truth:

- `ansible/group_vars/all.yaml`
- `ansible/playbooks/base-setup.yaml`
- `charts/jellyfin/templates/deployment.yaml`
- `charts/jellyfin/templates/pv.yaml`

## Symptoms

- `kubectl get pods -n jellyfin` shows the pod in `Init:0/1`.
- Jellyfin logs repeat `Waiting for USB storage to be mounted...`.
- `findmnt /mnt/usb-storage` on `apple-pi` returns nothing.
- Media is missing from Jellyfin even though the pod is running.

## Triage

1. Check the pod state:

   ```bash
   kubectl get pods -n jellyfin -o wide
   kubectl logs -n jellyfin pod/<jellyfin-pod-name> -c wait-for-usb --tail=50
   ```

2. Check the host mount:

   ```bash
   ssh ubuntu@192.168.1.101 'lsblk -o NAME,FSTYPE,LABEL,UUID,MOUNTPOINTS; findmnt /mnt/usb-storage || true'
   ```

3. Check the host mount config:

   ```bash
   ssh ubuntu@192.168.1.101 'grep -n usb-storage /etc/fstab; sudo cat /etc/udev/rules.d/99-usb-storage-automount.rules'
   ```

## Root Cause Pattern

The common failure is device-name drift.

- The USB partition may appear as `/dev/sda1` today and `/dev/sdb1` tomorrow.
- If the repo or generated host config hardcodes the wrong `/dev/sdX1`, the udev rule never fires.
- Jellyfin then waits forever because `/mnt/usb-storage` never appears in `/proc/mounts`.

## Recovery

If the fstab entry is correct, remount the drive on `apple-pi`:

```bash
ssh ubuntu@192.168.1.101 'sudo mount -a'
```

Then verify:

```bash
ssh ubuntu@192.168.1.101 'findmnt /mnt/usb-storage'
kubectl get pods -n jellyfin -o wide
```

If the device letter changed, update `ansible/group_vars/all.yaml` so `usb_device`
matches the real partition, then regenerate and reapply host config:

```bash
make generate
make setup
```

## Permanent Fix

The repo should not rely on a stable `/dev/sdX1` name for reconnects.

- `ansible/playbooks/base-setup.yaml` now writes the udev rule using the filesystem UUID.
- That makes the reconnect logic survive USB renumbering after reboot or replug.
- `ansible/group_vars/all.yaml` remains the source of truth for the initial device path used by Ansible.

## Prevention

- After any USB storage change, verify `lsblk` on `apple-pi` before changing repo config.
- Keep the mount point and UUID-based fstab entry authoritative.
- If Jellyfin is waiting on USB, check the host mount first; the pod is usually not the problem.

