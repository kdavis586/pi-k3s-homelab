# Codebase Concerns

**Analysis Date:** 2026-03-18

## Blocking Issue

**Pi-hole DaemonSet pods stuck in Pending state:**
- Issue: Early in a recent session, a `pihole-dns` LoadBalancer service was created for port 53. K3s's klipper-lb (ServiceLB) spawned `svclb-pihole-dns-*` pods on all three nodes claiming `hostPort: 53`. The `service-dns.yaml` file was later deleted from the repo, but `kubectl apply` is additive-only — it does NOT delete resources removed from manifests. The stale pods still hold port 53, preventing Pi-hole DaemonSet pods with `hostNetwork: true` from scheduling.
- Files: `k8s/pihole/service-dns.yaml` (deleted from repo but stale in cluster), Pi-hole DaemonSet pods cannot schedule
- Root cause: `kubectl apply` limitation — no resource cleanup when manifests are removed
- Impact: Pi-hole DHCP and DNS services unavailable; cluster nodes cannot receive DHCP config forcing use of Pi-hole as DNS
- Fix approach: **Migrate to Flux CD with pruning enabled** (deferred decision made in STATE.md). Flux will automatically delete the stale `pihole-dns` service on next reconcile. Once implemented, removes this and future accumulation of stale resources.
- Workaround for immediate fix: Manual deletion via raw `kubectl delete service pihole-dns -n pihole` (breaks project rule of "no direct kubectl commands")

---

## Tech Debt

**Network config uses interface wildcard, not explicit device name:**
- Issue: `cloud-init/templates/network-config.j2` configures networking via `name: "e*"` wildcard match in generated network-config YAML, not explicit `eth0`. This was a workaround after an earlier refactor incorrectly hardcoded `end0` which broke network config entirely.
- Files: `cloud-init/templates/network-config.j2` (line 4-5), generated files `cloud-init/network-config-*.yaml`
- Impact: Fragile — interface name depends on kernel/driver behavior. If naming scheme changes, all three Pis lose network connectivity.
- Improvement path: Verify `eth0` is stable across reboots on actual hardware, then update template to use explicit `eth0` with static configuration instead of wildcard match. This removes a point of failure and makes the template more maintainable.

**DNS configuration is split across three locations:**
- Issue: Node DNS configuration lives in three separate places: (1) `cloud-init/templates/network-config.j2`, (2) `/etc/netplan/99-dns-override.yaml` (applied via `base-setup.yaml`), and (3) `/etc/systemd/resolved.conf.d/nostub.conf` (also in `base-setup.yaml`). These are coupled but not centralized.
- Files: `cloud-init/templates/network-config.j2`, `ansible/playbooks/base-setup.yaml` (lines 71-85, 50-65)
- Impact: Hard to understand the full DNS picture; easy to miss implications when changing one piece. The three components work together to prevent DNS deadlock (Pi-hole pods restart → external DNS resolution needed → node DNS pinned to 8.8.8.8/1.1.1.1).
- Improvement path: Document the coupling clearly in comments. Add a DNS troubleshooting guide to CLAUDE.md or a dedicated DNS.md file explaining why all three pieces are necessary.

**Jellyfin uses `latest` image tag:**
- Issue: `k8s/jellyfin/deployment.yaml` specifies `image: jellyfin/jellyfin:latest` with `imagePullPolicy: IfNotPresent`. This means the first pull is cached indefinitely; new releases are never pulled unless the container is manually forced to re-pull or the node cache is cleared.
- Files: `k8s/jellyfin/deployment.yaml` (line 28)
- Impact: Security risk — vulnerability fixes in new releases won't be applied automatically. Manual intervention required to get updated image. Combined with `IfNotPresent` policy, there's no automatic patching mechanism.
- Improvement path: Pin to a specific version tag (e.g., `jellyfin:10.9.z` or `jellyfin:10.10.z`) and use `imagePullPolicy: Always` OR keep `latest` but set `imagePullPolicy: Always`. Add a note to CLAUDE.md about the trade-off: `latest` + `Always` means frequent restarts on new releases (good for security, bad for uptime); pinned version + `IfNotPresent` means manual updates but stable uptime.

**Samba configuration stored in Ansible playbook, not centralized:**
- Issue: Samba config is embedded directly in `base-setup.yaml` (lines 250-289) as a block of inline content. If the config needs updates or tuning, the playbook must be edited and re-run.
- Files: `ansible/playbooks/base-setup.yaml` (lines 250-289)
- Impact: Coupling between Samba config and Ansible playbook. Hard to version-control Samba config changes separately. No way to update Samba without running full Ansible playbook.
- Improvement path: Extract Samba config to a template file (`ansible/roles/storage/templates/smb.conf.j2`) and render it via template task. This allows Samba config changes without playbook changes. Low priority — Samba is stable and rarely needs updates.

**exFAT filesystem limitations not mitigated:**
- Issue: USB drive is formatted as exFAT because it's used with Mac for bulk file transfers. exFAT does NOT support Unix ownership (`chown`). The Ansible playbook works around this with mount options (`uid=0,gid=0,umask=000`) and comments warn not to use `owner`/`group` in file tasks.
- Files: `ansible/playbooks/base-setup.yaml` (line 235), `CLAUDE.md` (line 121-122)
- Impact: If someone adds an Ansible file task with `owner` or `group` parameters on the USB mount, the task will fail silently or succeed but have no effect, leading to confusion. No validation prevents this mistake.
- Improvement path: Add pre-flight check in `base-setup.yaml` to detect exFAT filesystem and skip `owner`/`group` for that mount. Or add a comment block at the top of the mount section with a clear warning. Low priority — documented and infrequent issue.

---

## Fragile Areas

**Pi-hole v6 environment variable migration incomplete:**
- Issue: Pi-hole upgraded from v5 → v6, which completely changed env var names from `WEBPASSWORD`, `PIHOLE_DNS_*` to `FTLCONF_*` prefix. The migration is documented in STATE.md but the DaemonSet uses v6 vars. If someone tries to downgrade or mix versions, the env vars won't match.
- Files: `k8s/pihole/daemonset.yaml` (lines 37-62), `STATE.md` (line 20)
- Impact: Version fragility — updating Pi-hole image without carefully reviewing env var changes could result in misconfiguration (e.g., DHCP not starting, password not applied).
- Safe modification: Any Pi-hole config change should (1) check the Pi-hole version in the image tag, (2) reference official Pi-hole v6 environment variable docs, (3) test in a dev environment first.

**K3s system-resolved stub listener fix is undocumented in code:**
- Issue: `base-setup.yaml` disables systemd-resolved stub listener to work around k3s iptables rules breaking containerd image pulls. This is a critical prerequisite but only documented in CLAUDE.md, not in the code itself.
- Files: `ansible/playbooks/base-setup.yaml` (lines 41-65)
- Impact: If the fix regresses (e.g., someone removes the nostub.conf task), image pulls will fail silently with "Try again" errors even though DNS itself appears healthy. Hard to diagnose without knowing the specific interaction.
- Safe modification: Keep the existing comments in the playbook. When touching systemd-resolved or containerd config, verify the nostub fix is still in place and re-run full `make setup` on all nodes.

**Jellyfin Recreate strategy means downtime on config changes:**
- Issue: `k8s/jellyfin/deployment.yaml` uses `strategy: type: Recreate` because Jellyfin cannot run multiple instances sharing the same config PVC. Any pod update requires stopping the container entirely, then restarting it.
- Files: `k8s/jellyfin/deployment.yaml` (lines 11-13)
- Impact: Jellyfin is unavailable during config changes or image updates. With a single replica pinned to a single node, there's no high availability. Reading a note in the code would help, but this is fundamental to the architecture.
- Safe modification: Document this limitation clearly. Any Jellyfin upgrade or restart requires notification to users. Consider future: if Jellyfin ever supports shared config (e.g., via external database), switch to RollingUpdate strategy for zero-downtime updates.

**Node group labels set via kubectl during K3s install:**
- Issue: `ansible/playbooks/k3s-install.yaml` (lines 120-135) runs raw `kubectl label` commands to apply the `homelab/node-group` labels AFTER K3s is installed. Labels are critical for Pi-hole pod scheduling but are NOT part of the infrastructure-as-code definition — they're applied manually by the playbook.
- Files: `ansible/playbooks/k3s-install.yaml` (lines 120-135)
- Impact: If someone deletes a node label, re-running `make install-k3s` won't re-apply it (K3s binary check at line 13 skips the playbook if already installed). Pods using nodeAffinity on these labels will fail to schedule. No single source of truth for labels.
- Improvement path: Define node labels in a K3s manifest or GitOps system (Flux) rather than in Ansible. Or add a separate Ansible play that runs every time (not just on first install) to ensure labels are correct.

---

## Security Considerations

**Samba guest access with no password on media directory:**
- Risk: Apple-pi exports `/mnt/usb-storage/media` via Samba with `guest ok = yes` and `map to guest = bad user`. Any device on the LAN can mount the share and read/write files.
- Files: `ansible/playbooks/base-setup.yaml` (lines 250-289), specifically lines 283-285
- Current mitigation: The share is on a private home LAN; access is only possible from devices connected to the home network. Perimeter security relies on router and physical isolation.
- Recommendations: This is acceptable for a home media server but document the security model clearly. If accessing from public networks in future (e.g., VPN → home network), restrict Samba to specific hosts or add authentication. Consider adding a comment in smb.conf explaining the security posture.

**Pi-hole has no authentication on web UI:**
- Risk: `FTLCONF_webserver_api_password: ""` (empty string) means the Pi-hole web UI and API have no password protection.
- Files: `k8s/pihole/daemonset.yaml` (line 40-41)
- Current mitigation: Pi-hole runs only on internal K3s cluster; web UI is accessed via `pihole.local` mDNS alias on home LAN only. Ingress (`k8s/pihole/ingress.yaml`) does not expose Pi-hole externally via Traefik.
- Recommendations: This is acceptable for home use but document clearly. If exposing Pi-hole to untrusted networks (e.g., guests with WiFi access), add Basic Auth via Traefik IngressRoute or set a strong password in env var.

**SSH keys imported from GitHub, no offline fallback:**
- Risk: `cloud-init/templates/user-data.j2` uses `ssh_import_id: [gh:kdavis586]` to pull SSH keys from GitHub at boot. If GitHub is unreachable, cloud-init may fail to set up SSH access.
- Files: `cloud-init/templates/user-data.j2`
- Current mitigation: GitHub is highly available; initial network setup via cloud-init happens during first boot when network connectivity is stable.
- Recommendations: Low risk for this use case. For production deployments, consider including a static fallback key in cloud-init or in the repo (with restricted permissions, rotated frequently).

**Kubeconfig saved with `chmod 0600` but stored in user home directory:**
- Risk: Kubeconfig contains cluster API credentials and is saved to `~/.kube/config-pi-k3s` with mode 0600 (readable by owner only). If user account is compromised, attacker has full cluster access.
- Files: `ansible/playbooks/k3s-install.yaml` (line 59)
- Current mitigation: Home directory is typically only accessible by the user. K3s API server requires TLS certificates; the kubeconfig includes cert data but bearer tokens are not used.
- Recommendations: This is acceptable for a home cluster. For shared systems, store kubeconfig with stronger protections or use RBAC to limit what the kubeconfig can do.

---

## Performance Bottlenecks

**Single-replica Jellyfin with high memory limit (6Gi) on 8GB node:**
- Issue: Jellyfin deployment has `replicas: 1` and limits of `6Gi` memory on apple-pi (8GB total). If Jellyfin approaches the limit and another pod starts, there's little room for the kubelet or system processes.
- Files: `k8s/jellyfin/deployment.yaml` (lines 10, 41-43)
- Current capacity: apple-pi has 8GB total; Jellyfin limited to 6Gi, leaving 2Gi for kubelet, systemd, OS, and other pods. Acceptable but tight.
- Limit: If Jellyfin memory usage exceeds limits, the container is OOMKilled. If multiple workloads run on apple-pi, contention will arise.
- Scaling path: Monitor actual Jellyfin memory usage over time. If it stays well below 2Gi, reduce the limit. If it exceeds 4Gi under normal use, consider upgrading apple-pi RAM or moving other workloads off the node.

**Local-path-provisioner uses single storage node (single point of failure):**
- Issue: All PVCs are provisioned on apple-pi via local-path-provisioner. If apple-pi goes offline, PVCs become inaccessible.
- Files: `k8s/storage/local-path-config.yaml` (path is `/mnt/usb-storage/k8s-volumes`)
- Current capacity: 128GB USB drive is shared between config PVCs and media files. PVC storage is capped at 5Gi per the Jellyfin config PVC request (line 14 of `k8s/jellyfin/pvc.yaml`).
- Limit: If more PVCs are added, USB drive space fills up. If apple-pi fails, all state is lost (though Jellyfin config is typically recoverable from fresh image).
- Scaling path: For HA, either (1) replicate USB drive to another node with ceph or glusterfs, or (2) migrate to network storage (NFS, SAN). For now, this is acceptable for a single-workload homelab.

**DNS resolution on every node goes to external DNS (8.8.8.8/1.1.1.1), bypassing Pi-hole:**
- Issue: cluster nodes are pinned to external DNS (8.8.8.8/1.1.1.1) to avoid Pi-hole restart chicken-and-egg deadlock. This means k3s system pods don't get the benefit of Pi-hole's DNS caching or blocking.
- Files: `ansible/playbooks/base-setup.yaml` (lines 71-85), `CLAUDE.md` (lines 40-49)
- Impact: Pi-hole's filtering and caching only apply to LAN devices; cluster system pods bypass it entirely. Slightly redundant DNS traffic to Google/Cloudflare.
- Scaling path: This is a known trade-off documented in CLAUDE.md. If cluster DNS caching becomes important, consider running a separate in-cluster DNS cache (e.g., CoreDNS) that points to external DNS, separate from Pi-hole.

---

## Scaling Limits

**Three-node cluster (1 server, 2 agents) with fixed RAM allocation:**
- Current capacity: 4GB (server) + 8GB + 8GB (agents) = 20GB total
- Limit: Workload density is limited by available RAM. K3s control plane on the-bakery (4GB) is constrained compared to the agents (8GB each). For a homelab this is fine, but if adding more stateful workloads, the-bakery may become a bottleneck.
- Scaling path: (1) Add more agent nodes (need more Pis + network switch ports + PoE budget), (2) upgrade the-bakery RAM if possible, or (3) implement Kubernetes resource quotas and pod eviction to keep cluster healthy.

**PoE switch power budget:**
- Current: 3x Raspberry Pi with PoE hats. TP-Link TL-SG605P is rated for 65W total.
- Limit: Each Pi with PoE hat draws ~5–10W depending on load. Three nodes + switch overhead leaves little headroom for additional powered devices.
- Scaling path: To add more nodes, upgrade to a higher-power PoE switch (e.g., 90W+) or add a separate power supply for some devices.

---

## Missing Critical Features

**No backup strategy for config PVC or USB drive:**
- What's missing: Configuration data (Jellyfin metadata, potential future app configs) lives only on the USB drive on apple-pi. No backup mechanism exists.
- Blocks: If the USB drive fails, all Jellyfin metadata (watch history, library data, etc.) is lost. Media files are on the same drive, so catastrophic failure = total loss.
- Workaround: Manually copy USB drive to Mac periodically using the instructions in CLAUDE.md. Not automated.
- Improvement path: Add a backup playbook that `rsync`s `/mnt/usb-storage/k8s-volumes` to an external location (Mac via rsync, or a NAS). Consider adding a cron job for periodic automated backups, or documenting manual backup frequency expectations.

**No monitoring or alerting:**
- What's missing: No Prometheus, Alertmanager, or similar observability stack. Cluster health is only visible via `make status` or `kubectl` commands.
- Blocks: Silent failures — if a pod crashes and restarts in a loop, or a node runs out of disk, no notification is sent. Requires manual polling to detect issues.
- Improvement path: Add a lightweight monitoring stack (e.g., Prometheus + Grafana, or just Prometheus with basic rules). For a homelab, even simple alerts (e.g., "node down", "pod OOMKilled") would be valuable.

**No CI/CD pipeline for testing manifests:**
- What's missing: K8s manifests are not validated before apply. No lint checks for best practices (e.g., missing resource limits, deprecated APIs).
- Blocks: Invalid manifests can cause deploy failures. Breaking changes to manifests are not caught until `make deploy` is run.
- Improvement path: Add `kubeval` or `kube-linter` to a GitHub Actions workflow that runs on every commit. Catch issues before they hit the cluster.

---

## Test Coverage Gaps

**No testing of Ansible playbooks:**
- What's not tested: Ansible playbooks (base-setup.yaml, k3s-install.yaml) are run directly against real hardware. If a task fails, the cluster may be left in an inconsistent state.
- Files: All playbooks in `ansible/playbooks/`
- Risk: Idempotency is assumed but not verified. If a playbook is re-run with changes, it may behave differently than the first run.
- Priority: Medium — playbooks are relatively simple and tested manually after each major change. For production, add `molecule` testing with Docker containers to simulate playbook runs.

**No validation of cloud-init templates:**
- What's not tested: Generated cloud-init files are not validated before being written to SD cards. Syntax errors or logic bugs only manifest at boot time.
- Files: `cloud-init/templates/` and generated `cloud-init/*.yaml` files
- Risk: A typo in cloud-init can break network config or hostname setup, requiring re-flashing the SD card.
- Priority: Low — templates are simple and tested on deployment. For safety, add a `cloud-init-devel validate-cloud-init-file` check in a pre-commit hook.

**No integration tests for Jellyfin or Pi-hole workloads:**
- What's not tested: Jellyfin deployment, ingress routing, USB mount, and Samba share are manually verified after `make deploy`. No automated tests check that Jellyfin actually starts, serves HTTP, or reads media files.
- Risk: Configuration changes that break Jellyfin (e.g., wrong volume mount) are not caught until manual testing.
- Priority: Medium — for a single-workload homelab, manual testing is sufficient. If adding more workloads, add simple curl/health-check tests.

---

## Known Limitations (By Design)

**No node affinity for system pods (Traefik, local-path-provisioner):**
- Issue: Traefik runs as a DaemonSet on all nodes, including the control plane (the-bakery). Local-path-provisioner runs on the-bakery only. This is fine for a 3-node cluster but means control-plane node is not dedicated to control plane only.
- Files: K3s default behavior (Traefik DaemonSet), `k8s/storage/local-path-config.yaml`
- Impact: Low for this cluster size. If scaling to 10+ nodes, should taint the control plane and move Traefik to dedicated ingress nodes.

**Cloud-init only runs once per instance-id (requires manual trigger to re-run):**
- Issue: Changing cloud-init config requires incrementing `cloud_init_version` in `group_vars/all.yaml`, running `make generate`, and re-flashing the SD card. Not fully automated.
- Files: `ansible/group_vars/all.yaml` (line 11), `CLAUDE.md` (lines 87-99)
- Impact: Acceptable for infrequent changes. If cloud-init config needs to change frequently, this becomes tedious.
- Mitigation: Documented in CLAUDE.md with clear steps. Users understand the mechanism.

**No Flux CD pruning enabled yet (deferred decision):**
- Issue: Cluster still uses `kubectl apply` (via `make deploy`), not Flux. Flux bootstrap is prepared in Makefile but not yet run. Until Flux is bootstrapped with `prune: true`, the Pi-hole port 53 conflict will persist (blocking issue above).
- Files: Makefile (lines 32-41), `STATE.md` (lines 61-127)
- Impact: Critical blocker for Pi-hole. Once Flux is bootstrapped, this is resolved automatically.

---

*Concerns audit: 2026-03-18*
