---
phase: quick
plan: 260321-iwc
type: execute
wave: 1
depends_on: []
files_modified: [README.md]
autonomous: true
requirements: []

must_haves:
  truths:
    - "README accurately describes jellyfin.local resolution via Pi-hole DNS, not mDNS"
    - "Mermaid diagram IPs match actual localDns config (jellyfin.local -> .101, not .100)"
    - "README includes Pi-hole DHCP role in the architecture description"
    - "README has clear initial setup and day-to-day usage sections"
  artifacts:
    - path: "README.md"
      provides: "Accurate project documentation"
  key_links: []
---

<objective>
Fix README.md accuracy: remove incorrect mDNS/avahi references for jellyfin.local, correct the mermaid diagram, and add initial setup + day-to-day usage sections.

Purpose: The README currently says jellyfin.local is "resolved via mDNS" (line 149) and the mermaid diagram shows `jellyfin.local -> .100` (the-bakery). In reality, jellyfin.local resolves via Pi-hole localDns to `192.168.1.101` (apple-pi). Pi-hole also serves DHCP, assigning itself as the DNS server to all LAN clients. The README must reflect the actual architecture.

Output: Accurate README.md
</objective>

<execution_context>
@~/.claude/get-shit-done/workflows/execute-plan.md
@~/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@README.md
@charts/pihole/values.yaml
@charts/jellyfin/values.yaml
@charts/jellyfin/templates/ingress.yaml
@charts/pihole/templates/ingress.yaml

<interfaces>
<!-- Actual DNS resolution chain for jellyfin.local -->
<!--
  1. Pi-hole runs DHCP (FTLCONF_dhcp_active=true in pihole values.yaml)
  2. Pi-hole DHCP assigns Pi-hole itself (192.168.1.102 / pumpkin-pi) as DNS to all LAN clients
  3. Pi-hole localDns has: jellyfin.local -> 192.168.1.101 (apple-pi)
  4. Pi-hole localDns has: pihole.local -> 192.168.1.102 (pumpkin-pi)
  5. Traefik runs on all nodes (DaemonSet) — IngressRoute on apple-pi matches Host(`jellyfin.local`) and routes to Jellyfin pod
  6. avahi-daemon IS installed on all nodes for hostname.local SSH access (e.g., ssh apple-pi.local), but jellyfin.local is NOT resolved via avahi/mDNS
-->

<!-- Pi-hole values.yaml localDns (source of truth): -->
<!-- localDns:
  - hostname: jellyfin.local
    ip: "192.168.1.101"
  - hostname: pihole.local
    ip: "192.168.1.102"
-->

<!-- Jellyfin ingress hosts: jellyfin.local, 192.168.1.101 -->
<!-- Pi-hole ingress: pihole.local, 192.168.1.102 -->
<!-- Pi-hole is pinned to pumpkin-pi (.102) via nodeSelector -->
<!-- Jellyfin is pinned to apple-pi (.101) via nodeSelector -->
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix mDNS references, correct mermaid diagram, and update Jellyfin access table</name>
  <files>README.md</files>
  <action>
Edit README.md with these specific changes:

1. **Mermaid diagram fixes:**
   - Change `jellyfin[Jellyfin<br/>pinned: apple-pi<br/>jellyfin.local → .100]` to `jellyfin[Jellyfin<br/>pinned: apple-pi<br/>jellyfin.local → .101]` (jellyfin.local resolves to apple-pi .101, not the-bakery .100)
   - Update pihole node to show its dual role: `pihole[Pi-hole<br/>DNS + DHCP<br/>pinned: pumpkin-pi]`
   - Add a visual connection showing Pi-hole provides DNS to LAN devices: add edge from `att` or `mac` through Pi-hole for DNS, or add a note. Simplest: add `mac -.->|DNS queries| pumpkin` edge to show client DNS flow.

2. **"Accessing Jellyfin" section (lines 145-152):**
   - Remove "resolved via mDNS" from the Apple devices row
   - Change the table to explain the actual resolution: Pi-hole DNS resolves jellyfin.local to 192.168.1.101 for any device using Pi-hole as its DNS server (which is all DHCP clients on the LAN)
   - Update to show that `http://jellyfin.local` works on ANY device that uses Pi-hole DNS (not just Apple devices)
   - Keep the `http://192.168.1.100` fallback row for devices not using Pi-hole DNS, but correct the IP: Traefik runs on all nodes, but Jellyfin is pinned to apple-pi so use `http://192.168.1.101` as the direct IP

3. **Stack section (line 52):**
   - Update Pi-hole description from "Pi-hole (LAN DNS for client devices)" to "Pi-hole (LAN DNS + DHCP, pinned to pumpkin-pi)" to reflect its DHCP role
  </action>
  <verify>
    <automated>grep -c "mDNS" README.md | grep -q "^0$" && echo "PASS: no mDNS references" || echo "FAIL: mDNS still referenced"</automated>
  </verify>
  <done>
  - No mentions of "mDNS" in Jellyfin access context (mDNS may still appear in avahi/SSH context if relevant, but NOT for jellyfin.local)
  - Mermaid diagram shows jellyfin.local -> .101 (not .100)
  - Pi-hole described with DNS + DHCP role
  - Jellyfin access table explains Pi-hole DNS resolution, not mDNS
  </done>
</task>

<task type="auto">
  <name>Task 2: Add initial setup and day-to-day usage sections</name>
  <files>README.md</files>
  <action>
Restructure the "Quick Start" section into two clear sections:

1. **Rename/restructure "Quick Start" into "Initial Setup"** — keep existing content (SD card prep, cloud-init, cluster bring-up) but add:
   - A prerequisites list: Mac with SD card reader, Bitwarden CLI (`bw`) installed and unlocked (for Flux bootstrap), `~/.kube` directory exists
   - After `make bootstrap-flux`: note that Flux will automatically deploy Jellyfin and Pi-hole from the `charts/` and `flux/apps/` directories
   - After initial setup: Pi-hole DHCP will start serving IPs to LAN clients — mention user should disable DHCP on their router to avoid conflicts (or set Pi-hole as the DHCP range to non-overlapping)

2. **Add a new "Day-to-Day Usage" section** after Initial Setup, containing:
   - **Deploying changes:** Edit Helm charts/values in `charts/`, commit, push to main. Flux reconciles within 60s. Use `make flux-status` to watch, `make flux-reconcile` for immediate sync.
   - **Uploading media:** Reference the existing Media upload / Storage section (Samba or rsync)
   - **Checking cluster health:** `make status` for nodes/pods, `make flux-status` for GitOps state
   - **SSH access:** `make ssh-<hostname>` (already documented, just cross-reference)
   - **Accessing services:** `http://jellyfin.local` (any device on LAN using Pi-hole DNS), `http://pihole.local:8080` for Pi-hole admin (note port 8080)
  </action>
  <verify>
    <automated>grep -q "Day-to-Day" README.md && grep -q "Initial Setup\|initial setup" README.md && echo "PASS: sections exist" || echo "FAIL: missing sections"</automated>
  </verify>
  <done>
  - README has a clear "Initial Setup" section covering first-time setup end-to-end
  - README has a "Day-to-Day Usage" section covering ongoing operations
  - Pi-hole admin URL includes port 8080
  - Flux GitOps workflow documented in day-to-day
  </done>
</task>

</tasks>

<verification>
- `grep -c "mDNS" README.md` returns 0 (no mDNS references for jellyfin.local)
- Mermaid diagram contains `.101` for jellyfin.local, not `.100`
- README contains "Day-to-Day" section
- README contains "Initial Setup" or restructured quick start
- Pi-hole described with DHCP role
</verification>

<success_criteria>
README.md accurately reflects the current architecture: jellyfin.local resolved via Pi-hole DNS (not mDNS), correct IPs in diagram, and clear initial setup + day-to-day usage sections for new readers.
</success_criteria>

<output>
After completion, create `.planning/quick/260321-iwc-fix-readme-accuracy-remove-mdns-referenc/260321-iwc-SUMMARY.md`
</output>
