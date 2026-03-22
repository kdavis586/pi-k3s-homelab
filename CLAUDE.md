# CLAUDE.md — Context for AI assistants

This file provides context for Claude Code sessions working in this repo.
Read `prompt.md` for the project overview and `STATE.md` for current status.

---

## Workflow

Single source of truth: `ansible/group_vars/all.yaml`
After any change to that file: `make generate` to propagate to all configs.

```bash
make generate       # Render all Jinja2 templates -> cloud-init files, inventory
make setup          # Ansible: base OS setup + USB mount + avahi (idempotent)
make install-k3s    # Ansible: install K3s server then agents (idempotent)
make bootstrap-flux # Bootstrap Flux CD onto cluster (one-time, requires bw unlocked)
make status         # kubectl get nodes + pods + svc + pvc
make flux-status    # Show Flux reconciliation state for all resources
make flux-sync      # Force immediate git sync (instead of waiting for 1-min poll)
make flux-retry     # Reset failed HelmRelease and retry
make ssh-<name>     # e.g. make ssh-the-bakery, make ssh-apple-pi
```

### CRITICAL: Use make for everything

**All setup, deployment, and re-deployment of changes must go through `make` commands.**
Never run `kubectl` or `ansible` commands directly — not even "just this once".

The only exceptions are physical setup steps: SD card preparation and physical networking.
Everything else goes through `make`.

- Wrong: `kubectl apply -f ...`, `kubectl label ...`, `ansible-playbook ...`
- Right: encode the change in Helm charts/values, commit, and push to main

`make setup` can appear to hang in the terminal even after completing — this is a known quirk.
The `cloud-init status --wait` step uses `timeout 300 ... || true` to avoid blocking indefinitely.

### Deploying workloads (GitOps)

Flux CD watches the `main` branch and reconciles within 60 seconds of a push:
```bash
git add charts/jellyfin/  # or whatever changed
git commit -m "feat: ..."
git push origin main
make flux-status          # watch reconciliation
```

To trigger an immediate sync without waiting for the poll interval:
```bash
make flux-sync            # force immediate sync
make flux-status          # confirm READY=True
```

If a HelmRelease fails and hits max retries:
```bash
make flux-retry           # reset failure count and retry all HelmReleases
```

Diagnostic commands (run directly, these are read-only):
```bash
flux get all                  # all Flux resources across namespaces
flux get kustomizations -A    # Kustomization reconciliation status
flux get helmreleases -A      # HelmRelease status
flux get sources git -A       # GitRepository polling status
flux logs                     # Flux controller event stream
```

---

## K3s / Ubuntu gotchas

### Cluster nodes must use static DNS, not DHCP-assigned DNS

The router advertises Pi-hole's IPs as the LAN DNS server via DHCP. If cluster nodes
accepted that, a Pi-hole pod restart would be unable to resolve Docker Hub to pull its
own image — a chicken-and-egg deadlock.

**Fix (applied via `base-setup.yaml`):** A netplan override at
`/etc/netplan/99-dns-override.yaml` pins every node to `8.8.8.8` and `1.1.1.1`,
ignoring whatever DNS DHCP assigns. Nodes always resolve via external DNS directly;
Pi-hole serves client devices only.

### systemd-resolved stub listener breaks containerd image pulls
k3s installs iptables rules that intercept loopback port 53 traffic, silently breaking
the systemd-resolved stub listener at `127.0.0.53`. Ubuntu's default `/etc/resolv.conf`
points at the stub, so containerd uses it for image pulls — which then fail with
`lookup <host>: Try again` even though DNS itself is healthy (resolvectl still works).

**Fix (already applied via `base-setup.yaml`):**
- Drop `/etc/systemd/resolved.conf.d/nostub.conf` with `DNSStubListener=no`
- Repoint `/etc/resolv.conf` → `/run/systemd/resolve/resolv.conf` (real upstream IPs, not stub)
- Restart systemd-resolved

This is a [documented k3s/Ubuntu prerequisite](https://docs.k3s.io/advanced#additional-os-preparations).
Symptom if it regresses: pods stuck in `ImagePullBackOff` and `dig @127.0.0.53` returns
"connection refused" while `resolvectl query <host>` succeeds.

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
Config data uses a **static PV** pinned to `/mnt/usb-storage/jellyfin-config` (see `charts/jellyfin/templates/pv.yaml`).
Media files live at `/mnt/usb-storage/media` — mounted directly into the Jellyfin container
via `hostPath` (not a PVC) so files copied there are immediately visible to Jellyfin.

### Storage pattern: why static PV, not dynamic provisioning

**All stateful workloads must use static PV + hostPath + `persistentVolumeReclaimPolicy: Retain`.
Do not use dynamic provisioning (local-path-provisioner) for any data you care about.**

Kubernetes dynamic provisioning was designed for cloud storage backends (EBS, GCE PD, Azure Disk)
where the storage exists as a durable service independent of the cluster. Deleting a PVC triggers
the cloud provider to remove a cloud volume — but that volume was replicated and snapshotable.
The PVC → PV → storage API implies that durability guarantee.

`local-path-provisioner` breaks that assumption. Its implementation is `mkdir` on create and
`rm -rf` on delete. There is no storage service behind it — just a directory on a local disk.
It was built to make K3s demos work out of the box, not for production data.

This setup makes dynamic provisioning even less appropriate:
- All stateful workloads are pinned to apple-pi anyway — the "schedule to any node" benefit doesn't apply
- There is one physical USB drive with no replication or snapshots
- exFAT provides no filesystem-level durability features

The static PV + hostPath pattern is the honest model: a directory on a disk that Kubernetes
should treat as precious and never touch. The `k8s-volumes` directory and `local-path-config`
ConfigMap exist in the repo but are not used — do not introduce workloads that depend on them.

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

For ongoing uploads, two options:

**Samba (easiest — no credentials, guest access):**
- macOS: Finder → Go → Connect to Server → `smb://apple-pi.local/media`
- Windows: File Explorer → `\\apple-pi\media`

**rsync:**
```bash
rsync -av --progress ~/path/to/media/ ubuntu@192.168.1.101:/mnt/usb-storage/media/
```

---

## DNS / Jellyfin access

Custom hostnames are served via Pi-hole DNS (not mDNS). `.home` was chosen over `.local`
because `.local` is reserved for mDNS — macOS and browsers route `.local` via Bonjour
multicast, bypassing Pi-hole entirely.

- All clients: `http://jellyfin.home` — requires DHCP lease from Pi-hole
- Direct IP fallback: `http://192.168.1.101`
- Pi-hole admin: `http://pihole.home:8080`
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
| `charts/jellyfin/` | Jellyfin Helm chart (deployed by Flux) |
| `charts/pihole/` | Pi-hole Helm chart (deployed by Flux) |
| `flux/apps/` | HelmRelease CRDs for Flux to deploy |
| `flux/flux-system/` | Flux bootstrap manifests (do not edit manually) |
| `STATE.md` | Current cluster state and any blockers |
| `SETUP.md` | Human-readable end-to-end setup guide |
