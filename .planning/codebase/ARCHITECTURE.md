# Architecture

**Analysis Date:** 2026-03-18

## Pattern Overview

**Overall:** Infrastructure-as-Code (IaC) GitOps with Ansible-driven provisioning and Kubernetes-native deployments.

**Key Characteristics:**
- Single source of truth: `ansible/group_vars/all.yaml` drives all configuration
- Jinja2 templating pipeline generates cloud-init, inventory, and K8s manifests from declarative YAML
- Layered approach: OS provisioning (Ansible) → K3s cluster setup → Container workload deployment
- GitOps-ready: Flux CD syncs cluster state from git (optional post-bootstrap)
- All changes through `make` commands, never direct kubectl/ansible

## Layers

**Workstation Layer:**
- Purpose: CLI orchestration and kubeconfig management
- Location: `Makefile`, `~/.kube/config-pi-k3s` (generated)
- Contains: Make targets that invoke Ansible playbooks and kubectl commands
- Depends on: Ansible, kubectl, SSH access to nodes
- Used by: Human operators running `make` commands

**Configuration Layer:**
- Purpose: Centralized, declarative node and cluster configuration
- Location: `ansible/group_vars/all.yaml` (source of truth)
- Contains: Hostnames, IPs, DNS servers, node groups, storage config, Flux version
- Depends on: Nothing
- Used by: All template rendering and playbooks

**Template Rendering Layer:**
- Purpose: Generate node-specific and cluster-wide configs from templates
- Location: `cloud-init/templates/` (user-data.j2, network-config.j2, meta-data.j2), `k8s/templates/`, `ansible/inventory.j2`, `make-vars.j2`
- Contains: Jinja2 templates parameterized by group_vars
- Depends on: `ansible/group_vars/all.yaml`
- Used by: `generate-configs.yaml` playbook to produce concrete files

**Generated Artifacts:**
- Purpose: Node-specific configuration files committed to git
- Location: `cloud-init/` (user-data-*.yaml, network-config-*.yaml, meta-data-*.yaml), `ansible/inventory.yaml`, `.make-vars`, `k8s/` manifests
- Contains: Rendered configs for each node and K8s objects
- Depends on: Template rendering layer
- Used by: cloud-init on Pi nodes, Ansible playbooks, kubectl, Flux

**OS Setup Layer:**
- Purpose: Bootstrap Pi nodes from cloud-init, perform idempotent base system setup
- Location: `ansible/playbooks/base-setup.yaml`
- Contains: Package installation, systemd service setup, DNS/network configuration, storage mount, Samba share
- Depends on: Generated cloud-init configs
- Used by: First boot via cloud-init, then re-runnable via `make setup`
- Key tasks:
  - Disable systemd-resolved stub listener (prevents K3s iptables deadlock)
  - Pin DNS to external resolvers via netplan override (prevents Pi-hole chicken-and-egg)
  - Load br_netfilter and overlay kernel modules (K3s prerequisites)
  - Configure sysctl bridge/IP forward settings
  - Mount USB drive on apple-pi with exFAT options
  - Start Samba for media share access
  - Set up avahi-daemon for mDNS

**K3s Installation Layer:**
- Purpose: Install K3s server on control plane, join agents, label nodes
- Location: `ansible/playbooks/k3s-install.yaml`
- Contains: K3s binary download via curl, server initialization, agent joining, node labeling
- Depends on: OS setup layer
- Used by: `make install-k3s` to bootstrap cluster
- Key tasks:
  - Install K3s server on the-bakery with specific node IP and TLS SAN
  - Wait for API health (accepts 200 or 401 status)
  - Read and distribute node token to agents
  - Install K3s agents with K3S_URL and K3S_TOKEN
  - Label nodes with `homelab/node-group` for workload affinity

**Kubernetes Layer:**
- Purpose: Container orchestration and workload management
- Location: `k8s/` directory with Jellyfin, Pi-hole, storage, and Flux manifests
- Contains: Deployments, DaemonSets, Services, Ingresses, PVCs, ConfigMaps
- Depends on: K3s installation layer
- Used by: kubectl apply, Flux CD reconciliation
- Key characteristics:
  - K3s comes with Traefik ingress controller (DaemonSet on all nodes on ports 80/443)
  - K3s includes local-path-provisioner (reconfigured to use USB storage)
  - Workloads deployed via `make deploy` or Flux GitOps sync

**Flux CD Layer (Optional):**
- Purpose: GitOps continuous deployment of cluster changes
- Location: `k8s/flux-system/gotk-sync.yaml`
- Contains: GitRepository and Kustomization resources
- Depends on: Kubernetes layer
- Used by: Automatic sync of k8s/ directory changes from git
- Enabled via: `make bootstrap-flux` with GITHUB_TOKEN

## Data Flow

**Configuration → Deployment:**

1. Edit `ansible/group_vars/all.yaml` (node IPs, hostnames, storage config)
2. Run `make generate` → triggers `generate-configs.yaml` playbook
3. Playbook renders Jinja2 templates with group_vars variables
4. Generated files committed to git: cloud-init/, ansible/inventory.yaml, k8s/ manifests
5. Commit triggers Flux CD if bootstrapped, or humans run `make deploy`

**Node Provisioning:**

1. Pi boots with cloud-init seed partition (user-data, network-config, meta-data)
2. cloud-init executes runcmd: loads kernel modules, configures sysctl
3. Ansible picks up node via generated inventory.yaml
4. `make setup` runs base-setup.yaml:
   - Waits for cloud-init to complete
   - Installs packages (curl, wget, git, htop, chrony, avahi-daemon, open-iscsi, nfs-common)
   - Disables systemd-resolved stub listener
   - Pins DNS to external resolvers
   - Mounts USB drive on apple-pi
   - Starts mDNS alias services (jellyfin.local, pihole.local)
5. `make install-k3s` runs k3s-install.yaml:
   - Installs K3s server on the-bakery
   - Joins agents to server
   - Labels nodes with homelab/node-group
   - Saves kubeconfig to workstation

**Cluster Deployment:**

1. `make deploy` applies all k8s/ manifests via kubectl
2. K3s applies manifests:
   - Creates namespaces (jellyfin, pihole, kube-system)
   - Starts Jellyfin deployment on apple-pi (nodeSelector)
   - Starts Pi-hole DaemonSet on workload nodes (nodeAffinity + hostNetwork)
   - Configures local-path-provisioner to use /mnt/usb-storage
   - Sets up Traefik ingress routes
3. Flux (if bootstrapped) watches github.com/kdavis586/pi-k3s-homelab/k8s
4. Any git changes auto-sync to cluster every 10 minutes (or manually via `make flux-reconcile`)

**Storage Data Flow:**

- Jellyfin config PVC (5Gi) → local-path-provisioner → /mnt/usb-storage/k8s-volumes on apple-pi
- Jellyfin media hostPath → /mnt/usb-storage/media on apple-pi
- Media upload via Samba (smb://apple-pi/media) → /mnt/usb-storage/media
- USB drive mounted via fstab with UUID (survives reboot)

## State Management

**Declared State:**
- `ansible/group_vars/all.yaml` — Single source of truth for all variables
- `k8s/*.yaml` — Cluster state is git-versioned
- `Makefile` — Standard commands enforce consistent workflow

**Runtime State:**
- `/var/lib/rancher/k3s/` — K3s server data (token, certs, kubeconfig)
- `/mnt/usb-storage/` — Jellyfin config and media (persistent across reboots)
- `~/.kube/config-pi-k3s` — Kubeconfig generated and saved on workstation

**Recovery:**
- All configuration stored in git; new nodes can be re-provisioned by regenerating from group_vars
- cloud-init re-runs if `cloud_init_version` incremented and instance-id changes
- Ansible playbooks are idempotent; can be re-run safely

## Key Abstractions

**Node Abstraction:**
- Purpose: Represent Raspberry Pi hardware as managed nodes
- Examples: `the-bakery` (server), `apple-pi` (agent with storage), `pumpkin-pi` (agent)
- Pattern: Each node has hostname, IP, and node_group; defined once in group_vars, used everywhere

**Node Group Labeling:**
- Purpose: Affinity/anti-affinity for workload scheduling
- Examples: `homelab/node-group: control` (server), `homelab/node-group: workloads` (agents)
- Pattern: Applied by k3s-install.yaml, used by Jellyfin nodeSelector and Pi-hole nodeAffinity

**Workload Abstraction:**
- Purpose: Container applications (Jellyfin, Pi-hole)
- Pattern: Each workload has namespace, deployment/daemonset, service, ingress, and optional storage

**Storage Abstraction:**
- Purpose: Persistent data volumes
- Pattern:
  - PVC (Jellyfin config) uses local-path-provisioner → /mnt/usb-storage/k8s-volumes
  - hostPath (Jellyfin media) mounts /mnt/usb-storage/media directly
  - Samba provides user-friendly network access to media

## Entry Points

**Workstation Entry Point:**
- Location: `Makefile`
- Triggers: Human runs `make <target>`
- Responsibilities: Route to correct Ansible playbook or kubectl command
- Targets:
  - `make generate` → render configs
  - `make setup` → OS provisioning
  - `make install-k3s` → cluster bootstrap
  - `make deploy` → apply K8s manifests
  - `make bootstrap-flux` → enable GitOps
  - `make status` → show cluster state
  - `make logs` → tail Jellyfin logs
  - `make ssh-<name>` → SSH into node

**Cloud-Init Entry Point:**
- Location: SD card system-boot partition (user-data-*.yaml)
- Triggers: First boot after flashing SD card
- Responsibilities: Set hostname, import SSH keys, install base packages, configure sysctl/modules
- Depends on: Generated user-data.j2 template

**Ansible Entry Point:**
- Location: `ansible/playbooks/` directory
- Triggers: `make` targets via Makefile
- Playbooks:
  - `generate-configs.yaml` — Render all templates
  - `base-setup.yaml` — OS setup and idempotent re-provisioning
  - `k3s-install.yaml` — Cluster initialization
  - `deploy.yaml` — Apply K8s manifests

**Kubernetes Entry Point:**
- Location: K3s API server at https://192.168.1.100:6443
- Triggers: `kubectl` commands, Flux CD reconciliation
- Responsibilities: Manage pods, services, volumes, ingress
- Accessed via: kubeconfig at ~/.kube/config-pi-k3s

## Error Handling

**Strategy:** Layered validation with idempotent playbooks; fail-safe defaults.

**Patterns:**

**Cloud-Init Level:**
- Uses `cloud-init status --wait` with timeout 300s to wait for completion
- `dpkg --configure -a` repairs any interrupted package installs
- Kernel module load failures ignored (modules may already be loaded)

**Ansible Level:**
- `wait_for_connection` with 120s timeout ensures nodes are reachable
- `wait_for` on K3s node-token file with 120s timeout
- `until/retries` polling for API health check (30 retries × 5s = 150s)
- `ignore_errors: true` on non-critical tasks (e.g., rollout status for optional Jellyfin)
- Changed_when: false prevents false "changed" status for read-only tasks

**DNS/Network Resilience:**
- systemd-resolved stub listener disabled to prevent k3s iptables deadlock (documented in CLAUDE.md)
- Static DNS pins nodes to 8.8.8.8/1.1.1.1, preventing chicken-and-egg with Pi-hole
- If DNS fails, curl-based K3s install will fail → admin sees clear error

**K3s Health Checks:**
- Accepts both 200 and 401 status from /healthz endpoint (401 is normal in K3s v1.34+)
- Pod probes: Jellyfin uses liveness (30s period, 5 failure threshold) and readiness (10s period)
- Pi-hole liveness not explicitly defined; relies on DaemonSet restart policy

**Deployment Validation:**
- `make deploy` includes `kubectl rollout status` for Jellyfin (120s timeout)
- Errors don't block final playbook output of pod status
- `make status` command shows all nodes/pods/services for manual inspection

## Cross-Cutting Concerns

**Logging:**
- Approach: journalctl on nodes, Jellyfin container logs via `make logs` (kubectl logs -f)
- No centralized logging; logs stay on nodes
- cloud-init logs at `/var/log/cloud-init-output.log` on each Pi

**Validation:**
- Approach: Ansible facts gathering, systemd service status checks, kubectl rollout status
- No centralized validation; each layer validates its own outputs
- Makefile help shows all available targets

**Authentication:**
- SSH: ED25519 keys imported from GitHub (`gh:kdavis586`)
- K3s API: kubeconfig with embedded certificates
- Pi-hole: No password (local LAN only, no internet exposure)
- Jellyfin: No auth configured (local LAN only)
- Samba: Guest access, no credentials required

**Secrets Management:**
- `.env` files git-ignored (not used in this IaC)
- K3s server certificate and node token stored on server, distributed via Ansible
- kubeconfig saved to workstation with 0600 permissions
- No external secret manager (vault, sealed-secrets); credentials ephemeral or avoided

**Networking:**
- Approach: Static IPs from group_vars, netplan for network config, Traefik for ingress
- mDNS aliases published on the-bakery (jellyfin.local, pihole.local via avahi)
- Traefik listens on all nodes; Pod traffic routed via node IPs
- No network policies; all pods can reach each other

**Observability:**
- Approach: kubectl get nodes/pods/svc, pod describe, logs
- No metrics scraping (Prometheus, Grafana not deployed)
- Pod resource requests/limits defined to prevent resource starvation

---

*Architecture analysis: 2026-03-18*
