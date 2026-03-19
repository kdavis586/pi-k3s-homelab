# External Integrations

**Analysis Date:** 2026-03-18

## APIs & External Services

**GitHub Integration:**
- GitHub SSH public keys - SSH keys imported at boot via `ssh_import_id: gh:kdavis586` in `cloud-init/templates/user-data.j2`
- Flux CD repository sync - Flux watches `https://github.com/kdavis586/pi-k3s-homelab` (branch: main, path: ./k8s)
  - SDK/Client: Flux CD CLI (`flux bootstrap github`)
  - Auth: `GITHUB_TOKEN` environment variable (required for `make bootstrap-flux`)

**K3s Installation:**
- K3s binary distribution - Downloaded via `curl -sfL https://get.k3s.io` in `ansible/playbooks/k3s-install.yaml`
- Server installation: `INSTALL_K3S_EXEC="server"` with TLS SAN config
- Agent installation: `K3S_URL=https://{{ server_ip }}:6443` and `K3S_TOKEN` (node token)

**Docker Hub:**
- Container image pulls for all workloads (unauthenticated, public images only)
- Images:
  - `jellyfin/jellyfin:latest` - Jellyfin media server (`k8s/jellyfin/deployment.yaml`)
  - `pihole/pihole:2026.02.0` - Pi-hole DNS and DHCP server (`k8s/pihole/daemonset.yaml`)
  - `busybox` - Helper pod for local-path-provisioner (`k8s/storage/local-path-config.yaml`)

**Public DNS Resolvers:**
- Google DNS: 8.8.8.8, 8.8.4.4 - Cluster nodes pin to external DNS via `cloud-init/templates/network-config.j2` and `ansible/playbooks/base-setup.yaml` (netplan override)
- Pi-hole upstream: `FTLCONF_dns_upstreams="8.8.8.8;8.8.4.4"` in `k8s/pihole/daemonset.yaml`

## Data Storage

**Databases:**
- None - no database integrations configured

**File Storage:**

**Local exFAT USB Storage:**
- Device: `/dev/sda1` (128GB USB-C flash drive attached to apple-pi)
- Mount: `/mnt/usb-storage` via `/etc/fstab` entry in `ansible/playbooks/base-setup.yaml`
- File system: exFAT (does not support Unix ownership)
- Mount options: `uid=0,gid=0,umask=000` (set via fstab, not Ansible file tasks)

**Jellyfin Media:**
- Path: `/mnt/usb-storage/media` (hostPath volume in `k8s/jellyfin/deployment.yaml`)
- Type: Direct hostPath, not PVC (files visible immediately to container)
- Access: Samba share (`smb://apple-pi.local/media` or `\\apple-pi\media`) and rsync

**Jellyfin Config:**
- Path: `/mnt/usb-storage/k8s-volumes` (local-path-provisioner PVC in `k8s/jellyfin/pvc.yaml`)
- Provisioner: local-path-provisioner (k3s built-in, reconfigured via `k8s/storage/local-path-config.yaml`)
- Storage class: local-path (default in K3s)

**Caching:**
- None configured

## Authentication & Identity

**Auth Provider:**
- GitHub SSH keys - Only auth method
  - Implementation: `ssh_import_id: gh:{{ github_user }}` in `cloud-init/templates/user-data.j2`
  - GitHub user: `kdavis586`
  - SSH key file used by Ansible: `~/.ssh/id_ed25519` (specified in `ansible/inventory.yaml`)

**Kubernetes RBAC:**
- No special RBAC configured - kubeconfig written to `~/.kube/config-pi-k3s` with full cluster-admin access

**Pi-hole Web UI:**
- No password - `FTLCONF_webserver_api_password=""` (empty string) in `k8s/pihole/daemonset.yaml`
- Access: HTTP port 8080 (changed from 80 because Traefik iptables rules intercept port 80)

## Monitoring & Observability

**Error Tracking:**
- None configured

**Logs:**
- Standard Kubernetes pod logs - accessed via `make logs` (tails Jellyfin logs)
- kubectl: `kubectl logs -n jellyfin -l app=jellyfin -f`

**Health Checks:**
- Jellyfin liveness probe: HTTP GET `/health` on port 8096 (60s delay, 30s period, 5 failures to restart)
- Jellyfin readiness probe: HTTP GET `/health` on port 8096 (30s delay, 10s period)
- K3s API health: URI check `https://{{ server_ip }}:6443/healthz` (accepts 200 or 401 as healthy)

## CI/CD & Deployment

**Hosting:**
- Raspberry Pi K3s cluster (on-premises)
- 3-node K3s cluster:
  - Server (control plane): the-bakery (192.168.1.100)
  - Agents: apple-pi (192.168.1.101), pumpkin-pi (192.168.1.102)

**CI Pipeline:**
- Flux CD - GitOps sync from GitHub repository
  - Source: GitRepository CRD watching `https://github.com/kdavis586/pi-k3s-homelab` (branch: main)
  - Sync: Kustomization CRD applies manifests from `./k8s` path
  - Interval: 10 minutes for reconciliation
  - Prune: Enabled - deletes cluster resources removed from git

**Deployment Process:**
- Manual: `make deploy` applies all k8s manifests via `kubectl apply`
- GitOps: `make bootstrap-flux` sets up Flux CD for automatic syncing
- Force re-sync: `make flux-reconcile` to immediately re-sync from git

## Environment Configuration

**Required env vars:**
- `GITHUB_TOKEN` - GitHub personal access token for `make bootstrap-flux`
- `HOME` - User home directory (used for kubeconfig path)
- `KUBECONFIG` - Set to `~/.kube/config-pi-k3s` by `make install-k3s`

**Generated env vars (in manifests):**
- Jellyfin: `JELLYFIN_PublishedServerUrl="http://jellyfin.local"` (hostname for external access)
- Pi-hole:
  - `TZ="UTC"` (timezone)
  - `FTLCONF_webserver_api_password=""` (no password)
  - `FTLCONF_dns_upstreams="8.8.8.8;8.8.4.4"` (upstream DNS)
  - `FTLCONF_dns_listeningMode="ALL"` (listen on all interfaces)
  - `FTLCONF_webserver_port="8080"` (web UI port)
  - `FTLCONF_dhcp_active="true"` (DHCP server enabled)
  - `FTLCONF_dhcp_start="192.168.1.2"`, `FTLCONF_dhcp_end="192.168.1.253"`, `FTLCONF_dhcp_router="192.168.1.254"`, `FTLCONF_dhcp_leaseTime="24h"`

**Secrets location:**
- No secrets stored in repository (credentials all via environment or GitHub auth)
- SSH keys: loaded from GitHub at boot, not checked in

## Webhooks & Callbacks

**Incoming:**
- None configured

**Outgoing:**
- Flux CD reconciliation - pushes cluster state to GitHub via standard git operations
  - Flux watches GitHub for changes and applies them to cluster
  - No reverse webhook from cluster back to GitHub

## Network Integration

**Cluster Networking:**
- Static IPs via cloud-init netplan configuration:
  - Server: 192.168.1.100/24
  - apple-pi: 192.168.1.101/24
  - pumpkin-pi: 192.168.1.102/24
- Gateway: 192.168.1.254 (ATT BGW320-500 router)
- DNS: Pinned to 8.8.8.8 and 1.1.1.1 (via netplan override, ignores DHCP DNS)

**Ingress:**
- Traefik - K3s built-in ingress controller (DaemonSet listening on ports 80/443)
- Jellyfin ingress: Routes `jellyfin.local` HTTP traffic to Jellyfin service
- Pi-hole ingress: Routes HTTP traffic to Pi-hole web UI on port 8080

**mDNS / Service Discovery:**
- avahi-daemon - Publishes `.local` hostnames on all nodes
- `jellyfin.local` - Published from the-bakery node to `192.168.1.100` via systemd service

---

*Integration audit: 2026-03-18*
