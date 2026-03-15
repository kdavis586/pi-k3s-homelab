# Pi K8s Cluster — Setup Guide

End-to-end instructions to go from bare hardware to a running K3s cluster with Jellyfin.

---

## Prerequisites

### Hardware
- 3x Raspberry Pi 4 Model B (2x 8GB, 1x 4GB)
- 3x PoE hats
- 1x TP-Link TL-SG605P (5-port unmanaged PoE switch)
- 1x ATT BGW320-500 gateway
- 3x microSD cards (2x 64GB for agents, 1x 32GB for server)
- 1x USB flash drive for Jellyfin media storage (plugged into apple-pi)

### Node assignments
| Hostname    | IP            | Role         | RAM | SD Card |
|-------------|---------------|--------------|-----|---------|
| the-bakery  | 192.168.1.100 | K3s server   | 4GB | 32GB    |
| apple-pi    | 192.168.1.101 | K3s agent    | 8GB | 64GB    |
| pumpkin-pi  | 192.168.1.102 | K3s agent    | 8GB | 64GB    |

### Mac tools required
```
brew install ansible
ansible-galaxy collection install community.general ansible.posix
```

### ATT BGW320-500 — IMPORTANT
**Only use ETH1, ETH3, or ETH4 for the switch.**
ETH2 is the multi-gig/passthrough port and does NOT serve LAN DHCP — devices behind it will never appear on your network.

---

## Step 1 — Flash SD cards

Use **Raspberry Pi Imager** to flash **Ubuntu Server 24.04 LTS (64-bit)** onto each card.
- Do NOT use Imager's built-in customization (no hostname, no SSH, no WiFi) — cloud-init handles all of that.

---

## Step 2 — Write cloud-init files to SD cards

Generate all config files from the single source of truth:
```bash
make generate
```

For each SD card, insert it into your Mac. The `system-boot` partition auto-mounts. Then run the matching command:

**the-bakery (32GB card):**
```bash
cp cloud-init/network-config-the-bakery.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-the-bakery.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-the-bakery.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && \
echo "the-bakery ready"
```

**apple-pi (64GB card):**
```bash
cp cloud-init/network-config-apple-pi.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-apple-pi.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-apple-pi.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && \
echo "apple-pi ready"
```

**pumpkin-pi (64GB card):**
```bash
cp cloud-init/network-config-pumpkin-pi.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-pumpkin-pi.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-pumpkin-pi.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && \
echo "pumpkin-pi ready"
```

---

## Step 3 — Physical setup

1. Insert SD cards into the correct Pis
2. Plug apple-pi's USB flash drive into a **blue USB 3.0 port**
3. Connect all Pis to PoE switch ports 1–3
4. Connect switch port 5 to ATT gateway **ETH1** (not ETH2)
5. Power on — the switch powers the Pis via PoE

**Do not unplug ethernet while Pis are booting** — this can corrupt dpkg mid-install.

---

## Step 4 — Wait for cloud-init

cloud-init runs package updates on first boot. This takes **5–10 minutes**.

Monitor progress:
```bash
sudo nmap -sn 192.168.1.0/24
```

Wait until `.100`, `.101`, `.102` all appear with `Raspberry Pi Trading` MACs.

Verify SSH access:
```bash
ssh ubuntu@192.168.1.100
```

---

## Step 5 — Run Ansible playbooks

```bash
make setup        # Base OS config + USB mount on apple-pi
make install-k3s  # Install K3s server + agents
make deploy       # Deploy Jellyfin to the cluster
```

Each command is idempotent — safe to re-run.

---

## Step 6 — Verify

```bash
ssh ubuntu@192.168.1.100 "kubectl get nodes"
# Expected:
# NAME         STATUS   ROLES           AGE   VERSION
# apple-pi     Ready    <none>          ...   v1.34.x+k3s1
# pumpkin-pi   Ready    <none>          ...   v1.34.x+k3s1
# the-bakery   Ready    control-plane   ...   v1.34.x+k3s1
```

---

## Re-running cloud-init (if config changes are needed)

To force cloud-init to re-run on next boot, increment `cloud_init_version` in `ansible/group_vars/all.yaml`, then `make generate` and re-copy files to the SD card(s). The changed `instance-id` in `meta-data` triggers a full re-run.

---

## Useful commands

```bash
make ssh-the-bakery     # SSH into server node
make ssh-apple-pi       # SSH into apple-pi
make ssh-pumpkin-pi     # SSH into pumpkin-pi
make status             # kubectl get nodes + pods
make logs               # Tail Jellyfin logs
```
