# Setup Guide

End-to-end steps to go from bare hardware to a running K3s cluster with Jellyfin.
See [README](README.md) for hardware overview, network topology, and node assignments.

---

## Prerequisites

Install Ansible on your Mac:
```bash
brew install ansible
ansible-galaxy collection install community.general ansible.posix
```

---

## Step 1 — Flash SD cards

Use **Raspberry Pi Imager** to flash **Ubuntu Server 24.04 LTS (64-bit)** onto each card.

> **Do not use Imager's built-in customization** (no hostname, no SSH, no WiFi) — cloud-init handles all of that.

---

## Step 2 — Write cloud-init files

Generate all configs from the single source of truth:
```bash
make generate
```

For each card, insert it into your Mac — `system-boot` auto-mounts. Run the matching command:

**the-bakery:**
```bash
cp cloud-init/network-config-the-bakery.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-the-bakery.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-the-bakery.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && echo "done"
```

**apple-pi:**
```bash
cp cloud-init/network-config-apple-pi.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-apple-pi.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-apple-pi.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && echo "done"
```

**pumpkin-pi:**
```bash
cp cloud-init/network-config-pumpkin-pi.yaml /Volumes/system-boot/network-config && \
cp cloud-init/user-data-pumpkin-pi.yaml /Volumes/system-boot/user-data && \
cp cloud-init/meta-data-pumpkin-pi.yaml /Volumes/system-boot/meta-data && \
diskutil eject /Volumes/system-boot && echo "done"
```

---

## Step 3 — Physical assembly

1. Insert SD cards into the correct Pis
2. Plug the USB flash drive into apple-pi's **blue USB 3.0 port**
3. Connect Pis to PoE switch ports 1–3
4. Connect switch port 5 to the ATT gateway — **ETH1, ETH3, or ETH4 only** (ETH2 is a passthrough port and won't serve DHCP)
5. Power on — PoE switch powers the Pis automatically

> **Don't unplug ethernet while Pis are booting.** Losing connectivity mid-install can corrupt dpkg state.

---

## Step 4 — Wait for cloud-init (~5–10 min)

cloud-init runs package updates on first boot. Poll until all three nodes appear:
```bash
sudo nmap -sn 192.168.1.0/24
# Wait for .100, .101, .102 to show up with Raspberry Pi MACs
```

Then verify SSH:
```bash
ssh ubuntu@192.168.1.100
```

---

## Step 5 — Run Ansible

```bash
make setup          # OS prep, USB mount on apple-pi, avahi mDNS
make install-k3s    # Install K3s server then agents
make bootstrap-flux # Bootstrap Flux CD (requires bw unlocked + flux CLI)
```

After bootstrap, workloads deploy automatically when you push to `main`.
Run `make flux-status` to check reconciliation state.

Each command is idempotent — safe to re-run.

> `make setup` may appear to hang after completing — this is normal. The `cloud-init status --wait` step uses a 5-minute timeout and exits cleanly.

---

## Step 6 — Verify

```bash
make status
# Expected:
# NAME         STATUS   ROLES           AGE   VERSION
# apple-pi     Ready    <none>          ...   v1.34.x+k3s1
# pumpkin-pi   Ready    <none>          ...   v1.34.x+k3s1
# the-bakery   Ready    control-plane   ...   v1.34.x+k3s1
```

Jellyfin should be accessible at `http://jellyfin.local` (Apple) or `http://192.168.1.100` (other clients).

---

## Re-running cloud-init

To force a re-run after config changes (e.g. if you need to reprovision a node):

1. Increment `cloud_init_version` in `ansible/group_vars/all.yaml`
2. Run `make generate`
3. Re-copy the updated `network-config`, `user-data`, and `meta-data` files to the SD card (Step 2 above)

The new `instance-id` in `meta-data` triggers a full cloud-init re-run on next boot.
