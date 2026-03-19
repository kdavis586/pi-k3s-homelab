# Testing Patterns

**Analysis Date:** 2026-03-18

## Overview

This project is **not a traditional application codebase with unit tests**. It is Infrastructure-as-Code (IaC) focused on cluster provisioning and deployment. Validation occurs through:

1. **Ansible idempotency** — playbooks must safely re-run without breaking existing state
2. **Kubernetes declarative validation** — `kubectl apply` must succeed without errors
3. **Manual testing** — SSH to nodes and verify state
4. **Integration smoke tests** — HTTP health checks during deployment

There are **no automated test suites** (no Jest, pytest, mocha, etc.).

## Test Framework

**No Test Runner:**
- This codebase does not use a traditional test framework
- All validation is implicit in deployment mechanics

**Validation Points:**

1. **Ansible Syntax Check:**
   ```bash
   ansible-playbook --syntax-check ansible/playbooks/*.yaml
   ```
   (Not currently enforced in Makefile; manual check only)

2. **Kubernetes Validation:**
   - `kubectl apply` validates manifest structure
   - `kubectl apply -R -f k8s/` applies all manifests recursively
   - Invalid manifests fail deployment immediately

3. **Idempotency Tests:**
   - All Ansible playbooks designed to be re-runnable
   - Tasks use `when:` clauses to skip already-completed actions
   - Changed-when detection prevents false "changed" status

4. **Health Checks:**
   - K3s API readiness polling with retry logic (`retries: 30, delay: 5`)
   - Pod rollout status polling: `kubectl rollout status deployment/jellyfin`
   - HTTP health probes on services

## Test Structure

### Deployment As Validation

The `make deploy` playbook itself IS the integration test:

**Location:** `ansible/playbooks/deploy.yaml`

**Structure:**
```yaml
- name: Deploy K8s manifests to cluster
  hosts: servers
  tasks:
    - name: Apply all manifests
      ansible.builtin.command: >
        kubectl apply -R -f {{ local_manifests_dir }}
        --kubeconfig {{ kubeconfig }}
      # If manifests are invalid, kubectl fails and entire playbook stops

    - name: Show apply output
      ansible.builtin.debug:
        msg: "{{ apply_output.stdout_lines }}"

    - name: Wait for Jellyfin deployment to be ready
      ansible.builtin.command: >
        kubectl rollout status deployment/jellyfin -n jellyfin
        --kubeconfig {{ kubeconfig }}
        --timeout=120s
      # If pod doesn't become Ready in 120s, deployment is considered failed
      ignore_errors: true  # Don't fail entire playbook if Jellyfin isn't deployed

    - name: Print pod status
      ansible.builtin.debug:
        msg: "{{ pod_status.stdout_lines }}"
```

**Validation Occurs At:**
1. `kubectl apply` — syntax validation
2. `kubectl rollout status` — actual pod startup and health readiness
3. Manual `make status` or `kubectl get pods -A`

### Installation Validation

**Location:** `ansible/playbooks/k3s-install.yaml`

**Patterns:**

1. **Precondition Checks:**
   ```yaml
   - name: Check if K3s server is already installed
     ansible.builtin.stat:
       path: /usr/local/bin/k3s
     register: k3s_binary

   - name: Install K3s server
     ansible.builtin.shell: ...
     when: not k3s_binary.stat.exists  # Only install once
   ```

2. **Readiness Polling:**
   ```yaml
   - name: Wait for K3s to be ready
     ansible.builtin.wait_for:
       path: /var/lib/rancher/k3s/server/node-token
       timeout: 120

   - name: Wait for K3s API server to be healthy
     ansible.builtin.uri:
       url: "https://{{ server_ip }}:6443/healthz"
       validate_certs: false
       status_code: [200, 401]  # Accept both codes as healthy
     register: k3s_health
     until: k3s_health.status in [200, 401]
     retries: 30
     delay: 5
   ```

3. **Post-Install Verification:**
   ```yaml
   - name: Verify cluster
     hosts: servers
     tasks:
       - name: Check all nodes are Ready
         ansible.builtin.command: kubectl get nodes
         register: nodes_output
         changed_when: false

       - name: Print cluster nodes
         ansible.builtin.debug:
           msg: "{{ nodes_output.stdout_lines }}"

       - name: Label cluster nodes
         ansible.builtin.command: >
           kubectl label node {{ server_hostname }}
           homelab/node-group={{ server_node_group }} --overwrite
   ```

## Idempotency Patterns

**All playbooks MUST be re-runnable without breaking state.**

### Changed-When Detection

Use `changed_when: false` for read-only operations:

```yaml
- name: Wait for cloud-init to complete
  ansible.builtin.shell: timeout 300 cloud-init status --wait || true
  changed_when: false  # Status check doesn't change state

- name: Repair any interrupted dpkg transactions
  ansible.builtin.command: dpkg --configure -a
  changed_when: false  # Repair is idempotent; don't report as "changed"

- name: Check all nodes are Ready
  ansible.builtin.command: kubectl get nodes
  register: nodes_output
  changed_when: false  # Query only, no state change
```

### Precondition Checking

Use `when:` clauses to skip already-completed tasks:

```yaml
- name: Check if K3s server is already installed
  ansible.builtin.stat:
    path: /usr/local/bin/k3s
  register: k3s_binary

- name: Install K3s server
  ansible.builtin.shell: curl -sfL https://get.k3s.io | ... sh -
  when: not k3s_binary.stat.exists  # Skip if already installed
```

Use `check` register + conditional:

```yaml
- name: Get UUID of USB drive partition
  ansible.builtin.command: blkid -s UUID -o value {{ usb_device }}
  register: usb_uuid
  changed_when: false
  when: usb_dev.stat.exists

- name: Mount USB drive by UUID in fstab
  ansible.posix.mount:
    path: "{{ usb_mount }}"
    src: "UUID={{ usb_uuid.stdout }}"
    fstype: "{{ usb_fstype }}"
    opts: defaults,nofail,uid=0,gid=0,umask=000
    state: mounted
  when: usb_dev.stat.exists and usb_uuid.stdout != ""
```

### Handlers for Restarts

Do NOT restart services inline; use handlers:

```yaml
tasks:
  - name: Disable systemd-resolved stub listener
    ansible.builtin.copy:
      dest: /etc/systemd/resolved.conf.d/nostub.conf
      content: |
        [Resolve]
        DNSStubListener=no
    notify: Restart systemd-resolved  # Triggers handler at end of play

  - name: Point /etc/resolv.conf at upstream DNS
    ansible.builtin.file:
      path: /etc/resolv.conf
      src: /run/systemd/resolve/resolv.conf
      state: link
      force: true
    notify: Restart systemd-resolved

handlers:
  - name: Restart systemd-resolved
    ansible.builtin.systemd:
      name: systemd-resolved
      state: restarted
      daemon_reload: true
```

**Benefit:** Multiple tasks can trigger the same handler; it only runs once at the end.

## Fixture and Test Data

**No test fixtures or factories** — this is not a data-driven application.

**Configuration as Fixtures:**
- `ansible/group_vars/all.yaml` is the single source of truth
- Values are rendered into templates to generate configs

**Cloud-init Templates as Test Cases:**
- `cloud-init/templates/user-data.j2`, `network-config.j2`, `meta-data.j2`
- Rendered with real cluster variables from `all.yaml`
- Generated files in `cloud-init/` are copied to SD cards and validated at boot

## Coverage

**No Coverage Requirements:**
- No code coverage metrics
- No test suite to measure

**"Coverage" via Deployment:**
- Every k8s manifest path tested by running `make deploy`
- Every Ansible task path tested by running appropriate `make` command
- Every Jinja2 template tested by running `make generate`

## Manual Testing Approach

**SSH Validation:**
```bash
make ssh-the-bakery
# Then on node:
kubectl get nodes
kubectl get pods -A
systemctl status k3s
systemctl status avahi-daemon
```

**Network Validation:**
```bash
# From macOS:
ping jellyfin.local          # mDNS resolution
ping pihole.local            # mDNS resolution
http://jellyfin.local        # Browser test
http://pihole.local          # Web UI test
```

**Storage Validation:**
```bash
# From macOS:
smb://apple-pi.local/media   # Samba share test
# Upload files and verify Jellyfin sees them
```

## Kubernetes Readiness

**Liveness Probes:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8096
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 5
```
- Restarts container if endpoint unhealthy for 5 consecutive checks (150 seconds)

**Readiness Probes:**
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8096
  initialDelaySeconds: 30
  periodSeconds: 10
```
- Removes from service if endpoint unhealthy
- Faster check (10s interval) than liveness

**Rollout Status Polling:**
```bash
kubectl rollout status deployment/jellyfin -n jellyfin --timeout=120s
```
- Blocks until deployment replicas are ready
- Timeout prevents hanging; `ignore_errors: true` allows recovery

## Test Types

### Unit Tests
**Not used.** No application code to unit test.

### Integration Tests
**Implicit in Deployment:**

1. **Cloud-init Integration:**
   - Template rendering via Jinja2 (`make generate`)
   - Boot node with generated cloud-init files
   - Verify hostname, SSH keys, packages installed, network configured

2. **Ansible Integration:**
   - Run playbooks against live nodes
   - Each playbook is idempotent (can re-run safely)
   - Verify state with subsequent SSH checks

3. **Kubernetes Integration:**
   - `kubectl apply -R -f k8s/` validates manifest structure
   - Pod startup validates image pulls, volume mounts, networking
   - Service selectors validate label matching
   - Ingress validates routing rules

### End-to-End Tests
**Manual Testing:**

```bash
# Full cluster bring-up cycle
make generate
make setup
make install-k3s
make deploy
make status

# Verify each component
make ssh-the-bakery "kubectl get nodes"
make ssh-apple-pi "mount | grep usb-storage"
curl http://jellyfin.local         # Over network
curl http://pihole.local
smb://apple-pi.local/media         # Samba from macOS
```

## Error Scenarios and Recovery

### Ansible Error Handling

**Retry Logic:**
```yaml
- name: Wait for K3s API server to be healthy
  ansible.builtin.uri:
    url: "https://{{ server_ip }}:6443/healthz"
    validate_certs: false
    status_code: [200, 401]
  register: k3s_health
  until: k3s_health.status in [200, 401]
  retries: 30        # Try up to 30 times
  delay: 5           # Wait 5s between attempts
```

**Ignored Errors:**
```yaml
- name: Wait for Jellyfin deployment to be ready
  ansible.builtin.command: >
    kubectl rollout status deployment/jellyfin -n jellyfin
    --kubeconfig {{ kubeconfig }}
    --timeout=120s
  ignore_errors: true  # Don't fail playbook if Jellyfin not deployed yet
```

**Conditional Handling:**
```yaml
- name: Display reminder if USB drive not detected
  ansible.builtin.debug:
    msg: >
      USB drive not detected at {{ usb_device }}. Plug in the drive and re-run
      this playbook, or check device path with 'lsblk'.
  when: not usb_dev.stat.exists
```

### Kubernetes Error Handling

**Failed Pod Recovery:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8096
  failureThreshold: 5   # Auto-restart after 5 failures
```

**Resource Limits Prevent Cascade Failures:**
```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 6Gi        # Prevent OOM kill of entire node
    cpu: "4"
```

## Known Limitations

1. **No Automated Tests:** Validation is manual or implicit in deployment
2. **No Linting:** YAML syntax validated only at deployment time
3. **No Test Isolation:** All playbooks modify live infrastructure; no staging environment
4. **Single Node Failure Mode:** Jellyfin deployment fails if apple-pi is unavailable (nodeSelector)

## Running Tests

**Validate Everything:**
```bash
# Regenerate all configs (tests Jinja2 template rendering)
make generate

# Full deployment cycle (tests Ansible + Kubernetes)
make setup
make install-k3s
make deploy
make status

# Manual smoke tests
make ssh-the-bakery "kubectl get nodes"
curl http://jellyfin.local
smb://apple-pi.local/media
```

**Re-run Setup (Idempotency Test):**
```bash
# Re-run any playbook to verify it's idempotent
make setup     # Should be no-op if system already configured
make install-k3s
make deploy
```

---

*Testing analysis: 2026-03-18*
