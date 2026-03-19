# Codebase Structure

**Analysis Date:** 2026-03-18

## Directory Layout

```
pi-k3s-homelab/
├── Makefile                           # Orchestration entry point (generate, setup, install-k3s, deploy, etc.)
├── CLAUDE.md                          # Context for Claude AI assistants
├── README.md                          # Project overview
├── SETUP.md                           # Human-readable setup guide
├── STATE.md                           # Current cluster state and session context (local only)
│
├── ansible/                           # Ansible configuration management
│   ├── group_vars/
│   │   └── all.yaml                  # Single source of truth for all configuration
│   ├── inventory.j2                  # Template for generated inventory
│   ├── inventory.yaml                # Generated inventory (do not edit directly)
│   └── playbooks/
│       ├── generate-configs.yaml     # Renders all Jinja2 templates from group_vars
│       ├── base-setup.yaml           # OS setup: DNS, networking, storage, packages
│       ├── k3s-install.yaml          # K3s server + agent installation
│       └── deploy.yaml               # kubectl apply all k8s/ manifests
│
├── cloud-init/                        # Cloud-init boot configurations
│   ├── templates/
│   │   ├── user-data.j2              # Hostname, SSH keys, packages, runcmd
│   │   ├── network-config.j2         # Static IP, gateway, DNS
│   │   └── meta-data.j2              # Instance ID for re-run control
│   ├── user-data-*.yaml              # Generated (one per node)
│   ├── network-config-*.yaml         # Generated (one per node)
│   └── meta-data-*.yaml              # Generated (one per node)
│
├── k8s/                               # Kubernetes manifests
│   ├── templates/
│   │   ├── jellyfin-deployment.j2    # Jellyfin with storage + resource limits
│   │   └── local-path-config.j2      # Reconfigures storage provisioner
│   │
│   ├── jellyfin/                     # Jellyfin media server workload
│   │   ├── namespace.yaml            # jellyfin namespace
│   │   ├── deployment.yaml           # Jellyfin pod spec with node selector + probes
│   │   ├── service.yaml              # ClusterIP service on port 8096
│   │   ├── ingress.yaml              # Traefik IngressRoute (jellyfin.local)
│   │   └── pvc.yaml                  # PersistentVolumeClaim for config (5Gi)
│   │
│   ├── pihole/                       # Pi-hole DNS/DHCP server workload
│   │   ├── 00-namespace.yaml         # pihole namespace
│   │   ├── daemonset.yaml            # DaemonSet with hostNetwork, nodeAffinity
│   │   ├── service-web.yaml          # Service for web UI (port 8080)
│   │   └── ingress.yaml              # Traefik IngressRoute (pihole.local)
│   │
│   ├── storage/
│   │   └── local-path-config.yaml    # ConfigMap reconfiguring storage to /mnt/usb-storage
│   │
│   └── flux-system/
│       └── gotk-sync.yaml            # Flux GitRepository + Kustomization
│
├── make-vars.j2                       # Template for .make-vars (additional Makefile config)
├── .make-vars                         # Generated (included by Makefile)
│
├── .planning/
│   └── codebase/                     # GSD analysis documents
│       ├── STACK.md                  # Technology stack analysis
│       ├── ARCHITECTURE.md           # Architecture patterns and layers
│       └── STRUCTURE.md              # This file
│
└── .git/                             # Git repository
    └── ...
```

## Directory Purposes

**Root:**
- Purpose: Repository root with build orchestration and documentation
- Contains: Makefile, .gitignore, README, setup guides, git metadata

**ansible/:**
- Purpose: Infrastructure-as-Code for provisioning and cluster management
- Contains: Configuration variables, playbooks, generated inventory
- Key concept: Single source of truth is `group_vars/all.yaml`

**ansible/group_vars/:**
- Purpose: Centralized variable definitions
- Contains: Hostnames, IPs, DNS, storage config, Flux version
- Edit pattern: Change `all.yaml`, then run `make generate`

**ansible/playbooks/:**
- Purpose: Executable provisioning and deployment steps
- Contains: Playbooks invoked by `make` targets
- Execution: Each playbook is idempotent (can be re-run safely)

**cloud-init/:**
- Purpose: First-boot system initialization for Raspberry Pis
- Contains: Jinja2 templates and generated per-node configs
- Deployment: Files copied to SD card system-boot partition

**cloud-init/templates/:**
- Purpose: Jinja2 templates rendered by `generate-configs.yaml`
- Contains: Parameterized user-data (hostname, SSH keys, packages), network-config (IP, DNS), meta-data (instance ID)
- Dependencies: All use variables from `group_vars/all.yaml`

**k8s/:**
- Purpose: Kubernetes manifests for container workloads
- Contains: Namespaces, deployments, daemonsets, services, ingresses, storage configs
- Deployment methods: `make deploy` (kubectl apply) or Flux CD (GitOps)

**k8s/templates/:**
- Purpose: Jinja2 templates for workload-specific manifests
- Contains: Jellyfin deployment (with storage + resource specs), local-path storage reconfiguration
- Generated into: k8s/jellyfin/deployment.yaml, k8s/storage/local-path-config.yaml

**k8s/jellyfin/:**
- Purpose: Jellyfin media server workload
- Contains: Namespace, deployment (1 replica, pinned to apple-pi), service, ingress, PVC
- Storage: Config PVC (5Gi on local-path-provisioner), media hostPath (/mnt/usb-storage/media)

**k8s/pihole/:**
- Purpose: Pi-hole DNS/DHCP server workload
- Contains: Namespace, DaemonSet (runs on all workload nodes), web service, ingress
- Networking: Uses hostNetwork for DHCP broadcasts, nodeAffinity to run on workloads only
- Ports: 53 (DNS UDP/TCP), 67 (DHCP UDP), 8080 (web UI TCP)

**k8s/storage/:**
- Purpose: Storage provisioning configuration
- Contains: ConfigMap that reconfigures K3s's local-path-provisioner to use /mnt/usb-storage

**k8s/flux-system/:**
- Purpose: Flux CD GitOps synchronization
- Contains: GitRepository (github.com/kdavis586/pi-k3s-homelab#main), Kustomization (watches k8s/)
- Optional: Only applied if `make bootstrap-flux` is run

**.planning/codebase/:**
- Purpose: GSD analysis documents
- Contains: STACK.md, ARCHITECTURE.md, STRUCTURE.md
- Consumed by: `/gsd:plan-phase` and `/gsd:execute-phase` to understand codebase patterns

## Key File Locations

**Entry Points:**

- `Makefile`: Primary entry point for all operations (see make help)
- `ansible/playbooks/generate-configs.yaml`: Renders templates → generated configs
- `ansible/playbooks/base-setup.yaml`: Idempotent OS setup for nodes
- `ansible/playbooks/k3s-install.yaml`: Cluster bootstrap (server then agents)
- `ansible/playbooks/deploy.yaml`: Apply K8s manifests to cluster

**Configuration:**

- `ansible/group_vars/all.yaml`: Single source of truth (edit this first)
- `ansible/inventory.j2`: Template for ansible inventory
- `ansible/inventory.yaml`: Generated inventory (from inventory.j2)
- `.make-vars`: Generated (included by Makefile)
- `make-vars.j2`: Template for .make-vars

**Core Logic:**

- `cloud-init/templates/user-data.j2`: Sets hostname, SSH keys, installs packages
- `cloud-init/templates/network-config.j2`: Static IP configuration
- `cloud-init/templates/meta-data.j2`: Controls cloud-init re-runs
- `k8s/templates/jellyfin-deployment.j2`: Jellyfin pod spec with storage
- `k8s/templates/local-path-config.j2`: Storage provisioner reconfiguration

**Deployed Applications:**

- `k8s/jellyfin/deployment.yaml`: Jellyfin container (1 replica on apple-pi)
- `k8s/pihole/daemonset.yaml`: Pi-hole DNS/DHCP (all workload nodes)
- `k8s/storage/local-path-config.yaml`: Storage path override

**GitOps:**

- `k8s/flux-system/gotk-sync.yaml`: Flux GitRepository and Kustomization
- Watch: github.com/kdavis586/pi-k3s-homelab branch main, path k8s

## Naming Conventions

**Files:**

- Playbooks: `hyphen-separated.yaml` (e.g., `base-setup.yaml`, `generate-configs.yaml`)
- Templates: `descriptive-name.j2` with Jinja2 extension (e.g., `user-data.j2`)
- Generated configs: `descriptive-name-*.yaml` with node name or identifier (e.g., `user-data-apple-pi.yaml`)
- K8s manifests: Grouped by workload, files named by resource kind (e.g., `deployment.yaml`, `service.yaml`)
- Naming in inventory: kebab-case hostnames (e.g., `the-bakery`, `apple-pi`, `pumpkin-pi`)

**Directories:**

- Ansible: `playbooks/` contains all playbooks, `group_vars/` contains variables
- cloud-init: `templates/` for Jinja2 sources, root for generated files
- K8s: `<workload>/` for each app (jellyfin, pihole), `storage/` for shared config, `flux-system/` for GitOps
- Config: `ansible/`, `cloud-init/`, `k8s/` are top-level organization

**Kubernetes Resources:**

- Namespaces: `jellyfin`, `pihole`, `kube-system` (K3s default), `flux-system` (Flux default)
- Labels: `app: <appname>` on all pods/services/deployments
- Node labels: `homelab/node-group: control|workloads` applied by k3s-install.yaml
- mDNS aliases: `jellyfin.local`, `pihole.local` published on the-bakery

## Where to Add New Code

**New Workload (e.g., another service):**

1. Add new node group or workload affinity rule to `ansible/group_vars/all.yaml` if needed
2. Create new namespace: `k8s/<workload>/00-namespace.yaml`
3. Create pod spec: `k8s/<workload>/deployment.yaml` (or daemonset/statefulset)
4. Create service: `k8s/<workload>/service.yaml` (ClusterIP, NodePort, etc.)
5. Create ingress: `k8s/<workload>/ingress.yaml` (Traefik IngressRoute)
6. Create storage if needed: `k8s/<workload>/pvc.yaml` (uses local-path-provisioner)
7. Commit to git, then run `make deploy` (or wait for Flux if bootstrapped)

**New Configuration Variable (e.g., new node, new network setting):**

1. Edit `ansible/group_vars/all.yaml` (add to agent_nodes, dns_servers, etc.)
2. Run `make generate` (renders all templates with new values)
3. Commit generated files to git
4. Run `make setup` to apply OS-level changes, or `make deploy` for K8s changes

**New Cluster Addon (e.g., cert-manager, monitoring):**

1. If requires provisioning-time setup: Create new playbook in `ansible/playbooks/`
2. Add deployment manifests to `k8s/<addon>/`
3. Either: Add playbook target to Makefile, or add manifests to k8s/ and let Flux sync
4. Run `make deploy` or commit + wait for Flux reconciliation

**Customizing Workload:**

1. Edit template in `k8s/templates/` (e.g., `jellyfin-deployment.j2`)
2. Or directly edit generated manifest (e.g., `k8s/jellyfin/deployment.yaml`)
   - If editing directly: Add comment `# Generated by: make generate` to preserve workflow
3. Run `make deploy` to apply changes to cluster

**Changing Node Configuration:**

1. Edit `ansible/group_vars/all.yaml` (hostnames, IPs, cloud_init_version)
2. Run `make generate` (updates all derived configs)
3. For cloud-init changes: Increment `cloud_init_version` to force re-run on next boot
4. For K3s/base-setup changes: Run `make setup` or re-flash SD card
5. Commit all generated files to git

## Special Directories

**Generated Directories:**

- `ansible/inventory.yaml`: Generated from `inventory.j2` template
  - Committed to git: Yes (allows offline Ansible if needed)
  - Re-generated: Every `make generate` run

- `cloud-init/*.yaml` (all user-data/network-config/meta-data files)
  - Committed to git: Yes (historical record, easy to replicate)
  - Re-generated: Every `make generate` run

- `k8s/jellyfin/deployment.yaml`: Generated from `jellyfin-deployment.j2`
  - Committed to git: Yes
  - Re-generated: Every `make generate` run

- `k8s/storage/local-path-config.yaml`: Generated from `local-path-config.j2`
  - Committed to git: Yes
  - Re-generated: Every `make generate` run

- `.make-vars`: Generated from `make-vars.j2`
  - Committed to git: Yes (ensures consistent make behavior)
  - Re-generated: Every `make generate` run

**Ignored Directories:**

- `.git/`: Version control metadata
- `node_modules/`: npm packages (if ever needed for local tooling)
- `~/.kube/`: Kubeconfig stored on workstation, not in repo
- `.env` files: Not used in this IaC

**Runtime State (not committed):**

- `/var/lib/rancher/k3s/` on nodes: K3s server data (ephemeral if node is replaced)
- `/mnt/usb-storage/` on apple-pi: Jellyfin config and media (persistent, backed up externally)
- `~/.kube/config-pi-k3s`: Kubeconfig on workstation (regenerated by `make install-k3s`)

## Typical Workflow

**Initial Setup:**

```bash
# 1. Edit once
vim ansible/group_vars/all.yaml  # Hostnames, IPs, storage paths

# 2. Generate all configs (commit to git)
make generate
git add -A && git commit -m "Initial config"

# 3. Flash SD cards with ubuntu-server image, copy cloud-init seed partition files

# 4. Boot nodes, then provision
make setup        # OS setup (idempotent)
make install-k3s  # Cluster bootstrap
make deploy       # K8s workloads

# 5. Optional: enable GitOps
make bootstrap-flux
```

**Day-to-Day Changes:**

```bash
# Change a variable
vim ansible/group_vars/all.yaml

# Regenerate and apply
make generate
make deploy

# Or if changing only a K8s manifest:
vim k8s/jellyfin/deployment.yaml
make deploy

# Check status
make status
make logs
```

**Debugging:**

```bash
# See all available targets
make help

# SSH into a node
make ssh-apple-pi

# Check cluster status
make status

# Tail Jellyfin logs
make logs

# Manual Flux sync
make flux-reconcile
```

---

*Structure analysis: 2026-03-18*
