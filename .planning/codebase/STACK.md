# Technology Stack

**Analysis Date:** 2026-03-18

## Languages

**Primary:**
- YAML - Configuration, manifests, and playbooks throughout
- Jinja2 - Template rendering for cloud-init and Kubernetes manifests
- Bash - Shell scripting in cloud-init runcmd

**Secondary:**
- Python - Ansible playbook execution and JSON parsing in Makefile SSH helpers
- Shell script - K3s installation via curl scripts

## Runtime

**Environment:**
- Ubuntu Server 24.04 LTS (arm64) - OS for all Raspberry Pi nodes
- K3s v1.34+ - Kubernetes distribution running on all nodes

**Package Manager:**
- apt - Ubuntu package manager for OS-level dependencies
- Ansible module: ansible.builtin.* - Configuration management and orchestration

## Frameworks

**Core:**
- K3s - Lightweight Kubernetes distribution (installs via `curl -sfL https://get.k3s.io`)
- Traefik - Ingress controller included with K3s (DaemonSet on all nodes)
- local-path-provisioner - Storage provisioning included with K3s

**Configuration Management:**
- Ansible - Infrastructure provisioning and templating (`ansible-playbook` via Make)

**CD/GitOps:**
- Flux CD v2.4.0 - GitOps sync for cluster state (bootstrapped via `make bootstrap-flux`)

**Cloud Init:**
- cloud-init - First-boot system initialization on all Pi nodes

**Monitoring & Health:**
- Liveness and readiness probes - HTTP `/health` endpoint checks in pod definitions

## Key Dependencies

**Infrastructure:**
- `curl` - K3s binary installation, used in cloud-init runcmd
- `chrony` - NTP time synchronization on all nodes
- `open-iscsi` - iSCSI support for potential future storage
- `nfs-common` - NFS support for potential future storage
- `avahi-daemon` and `avahi-utils` - mDNS hostname resolution (`.local` domains)

**Networking:**
- `netplan` - Network configuration tool (via `/etc/netplan/99-dns-override.yaml`)
- `systemd-resolved` - DNS resolution (configured to bypass stub listener via `/etc/systemd/resolved.conf.d/nostub.conf`)

**Container Runtimes:**
- containerd - Built into K3s, handles image pulls from Docker Hub

## Configuration

**Environment:**
- Single source of truth: `ansible/group_vars/all.yaml`
- Environment variables required:
  - `GITHUB_TOKEN` - For `make bootstrap-flux` to authenticate with GitHub
  - `HOME` - Used by Ansible to write kubeconfig to `~/.kube/config-pi-k3s`

**Build:**
- Makefile - Orchestrates all operations (generate, setup, install-k3s, deploy, bootstrap-flux)
- `.make-vars` - Included by Makefile for additional configuration
- `ansible/inventory.yaml` - Generated from `group_vars/all.yaml`

**Templating:**
- Jinja2 templates in `cloud-init/templates/` and `k8s/templates/` directory structure
- Ansible playbooks render templates from `group_vars/all.yaml` variables
- `cloud_init_version` variable controls cloud-init re-runs (incremented to change `instance-id`)

## Platform Requirements

**Development:**
- macOS or Linux with Make, Ansible, kubectl, and flux CLI
- SSH access to Raspberry Pi nodes (via ED25519 keys from GitHub)
- `~/.kube` directory must exist before running `make install-k3s`

**Production (Cluster Nodes):**
- Raspberry Pi 4 Model B with PoE hats
- Ubuntu Server 24.04 LTS pre-flashed to SD cards
- TP-Link TL-SG605P PoE+ switch for network connectivity
- ATT BGW320-500 fiber gateway as LAN router
- 128GB USB-C flash drive attached to apple-pi for Jellyfin storage

**Deployment Target:**
- K3s cluster running on 3 Raspberry Pi 4s:
  - 1 server (control plane): the-bakery (4GB RAM, 32GB SD)
  - 2 agents: apple-pi (8GB RAM, 64GB SD + 128GB USB), pumpkin-pi (8GB RAM, 64GB SD)

**Node-level Prerequisites:**
- br_netfilter and overlay kernel modules loaded (via cloud-init)
- systemd-resolved stub listener disabled to prevent DNS resolution deadlock
- Static DNS (8.8.8.8, 1.1.1.1) pinned via netplan override to prevent chicken-and-egg deadlock with Pi-hole
- UFW firewall disabled
- sysctl settings: bridge-nf-call-iptables, bridge-nf-call-ip6tables, ip_forward enabled

---

*Stack analysis: 2026-03-18*
