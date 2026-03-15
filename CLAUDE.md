# CLAUDE.md — Context for AI assistants

This file provides context for Claude Code sessions working in this repo.
Read `prompt.md` for the project overview and `STATE.md` for current status.

---

## Workflow

Single source of truth: `ansible/group_vars/all.yaml`
After any change to that file: `make generate` to propagate to all configs.

```bash
make generate     # Render all Jinja2 templates → cloud-init files, inventory, k8s manifests
make setup        # Ansible: base OS setup + USB mount + avahi (idempotent)
make install-k3s  # Ansible: install K3s server then agents (idempotent)
make deploy       # kubectl apply all k8s manifests
make status       # kubectl get nodes + pods
make ssh-<name>   # e.g. make ssh-the-bakery, make ssh-apple-pi
```

`make setup` can appear to hang in the terminal even after completing — this is a known quirk.
The `cloud-init status --wait` step uses `timeout 300 ... || true` to avoid blocking indefinitely.

---

## Hardware gotchas discovered during initial setup

### TP-Link TL-SG605P Extend mode
The switch has a physical toggle on the back panel labeled "Extend". When ON, it hard-locks
affected ports to **10 Mbps** (trades speed for 250m PoE range). Keep this **OFF** — all
cables are short and 10 Mbps will cause Jellyfin buffering. Verified all three Pi ports
negotiate at 1000 Mbps with Extend OFF.

### ATT BGW320-500 ethernet ports
**ETH2 is the multi-gig passthrough port — do NOT connect the switch there.**
It does not serve LAN DHCP and devices behind it are completely invisible on the network.
Use ETH1, ETH3, or ETH4 for the PoE switch uplink.

### Raspberry Pi 4 ethernet interface name
The interface is `eth0`, not `end0`. An earlier refactor incorrectly changed the network-config
template to `end0` which broke all network config. The current template uses a wildcard match
(`name: "e*"` with DHCP) — confirmed working. Should be updated to a static `eth0` config
with the correct IPs once the cluster is stable.

### cloud-init re-run mechanism
cloud-init only runs once per `instance-id`. To force a re-run after SD card changes:
1. Increment `cloud_init_version` in `group_vars/all.yaml`
2. Run `make generate` — this updates the `meta-data` files with a new `instance-id`
3. Copy the new `network-config`, `user-data`, and `meta-data` files to the `system-boot` partition

SD card copy commands (run from repo root, one card at a time):
```bash
cp cloud-init/network-config-<node>.yaml /Volumes/system-boot/network-config && \
cp cloud-init/meta-data-<node>.yaml /Volumes/system-boot/meta-data && \
cp cloud-init/user-data-<node>.yaml /Volumes/system-boot/user-data && \
diskutil eject /Volumes/system-boot && echo "done"
```

### Do not unplug ethernet during boot
Unplugging ethernet while cloud-init is running `apt-get` corrupts dpkg state.
The `base-setup.yaml` playbook has a `dpkg --configure -a` repair step to recover from this.

### RAM reality check
Original spec said "1x 8GB Pi" but actual hardware is 2x 8GB + 1x 4GB:
- the-bakery (.100): 4GB — runs K3s control plane (correct, control plane is low-footprint)
- apple-pi (.101): 8GB — K3s agent, Jellyfin workload, USB storage
- pumpkin-pi (.102): 8GB — K3s agent

---

## Storage setup

128GB USB-C flash drive is attached to **apple-pi** at `/dev/sda1` (exFAT), mounted at `/mnt/usb-storage`.
Jellyfin is pinned to apple-pi via `nodeSelector: kubernetes.io/hostname: apple-pi`.
Config PVC is provisioned under `/mnt/usb-storage/k8s-volumes` via local-path-provisioner.
Media files live at `/mnt/usb-storage/media` — mounted directly into the Jellyfin container
via `hostPath` (not a PVC) so files copied there are immediately visible to Jellyfin.

exFAT does not support Unix ownership (`chown`). Permissions are set via mount options:
`uid=0,gid=0,umask=000` in fstab — do not add `owner`/`group` to Ansible file tasks on this mount.

Storage vars in `group_vars/all.yaml`:
```yaml
storage_node: apple-pi
usb_device: /dev/sda1
usb_fstype: exfat
usb_mount: /mnt/usb-storage
```

### Swapping the USB drive safely
```bash
kubectl --kubeconfig ~/.kube/config-pi-k3s scale deployment jellyfin -n jellyfin --replicas=0
ssh ubuntu@192.168.1.101 "sudo umount /mnt/usb-storage"
# unplug, copy files, replug
ssh ubuntu@192.168.1.101 "sudo mount -a"
kubectl --kubeconfig ~/.kube/config-pi-k3s scale deployment jellyfin -n jellyfin --replicas=1
```

---

## Media upload

Fastest for bulk: physically swap USB drive (see above).
For ongoing uploads: `rsync` directly to apple-pi:
```bash
rsync -av --progress ~/path/to/media/ ubuntu@192.168.1.101:/mnt/usb-storage/media/
```
Samba has been removed — rsync/scp is the preferred transfer method.

---

## mDNS / Jellyfin access

avahi-daemon runs on all nodes for `.local` hostname resolution.
A systemd service on the-bakery publishes `jellyfin.local` → `192.168.1.100` via mDNS.

- Apple devices: `http://jellyfin.local` — works with zero client configuration
- Android/Windows: `http://192.168.1.100` directly
- Always use `http://` prefix explicitly — browsers auto-upgrade bare hostnames to HTTPS

---

## cloud-init template notes

- `user-data.j2` — sets hostname, imports SSH keys from `gh:kdavis586`, installs base packages
- `network-config.j2` — uses `match: name: "e*"` + DHCP (diagnostic). Update to static `eth0`
  config once interface name is confirmed stable across reboots.
- `meta-data.j2` — sets `instance-id` using `cloud_init_version` to control re-runs

---

## K3s notes

- Kubeconfig is saved to `~/.kube/config-pi-k3s` by `make install-k3s`
- The `/healthz` endpoint returns 401 (not 200) without auth in K3s v1.34+ — this is normal.
  The playbook accepts both 200 and 401 as healthy.
- K3s comes with Traefik ingress and local-path-provisioner out of the box
- Traefik listens on ports 80/443 on all nodes via DaemonSet
- `~/.kube` directory must exist before running `make install-k3s` (`mkdir -p ~/.kube`)

---

## Key files

| File | Purpose |
|------|---------|
| `ansible/group_vars/all.yaml` | Single source of truth — edit this, then `make generate` |
| `ansible/inventory.yaml` | Generated — do not edit directly |
| `cloud-init/templates/` | Jinja2 templates for user-data, network-config, meta-data |
| `ansible/playbooks/base-setup.yaml` | OS prep, USB mount, avahi mDNS |
| `ansible/playbooks/k3s-install.yaml` | K3s install |
| `ansible/playbooks/generate-configs.yaml` | Template rendering |
| `k8s/jellyfin/` | Jellyfin manifests |
| `k8s/storage/local-path-config.yaml` | Configures local-path-provisioner storage paths |
| `STATE.md` | Current cluster state and any blockers |
| `SETUP.md` | Human-readable end-to-end setup guide |
