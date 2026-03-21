---
phase: quick
plan: 260321-iwc
subsystem: docs
tags: [readme, dns, pihole, jellyfin, mermaid]

requires: []
provides:
  - Accurate README reflecting Pi-hole DNS (not mDNS) for jellyfin.local resolution
  - Correct mermaid diagram with jellyfin.local -> .101 and Pi-hole DNS+DHCP role shown
  - Clear Initial Setup and Day-to-Day Usage sections for new readers
affects: []

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - README.md

key-decisions:
  - "jellyfin.local resolves via Pi-hole localDns to 192.168.1.101 (apple-pi), not via mDNS/avahi"
  - "Pi-hole described with DNS + DHCP dual role throughout README"

patterns-established: []

requirements-completed: []

duration: 5min
completed: 2026-03-21
---

# Quick Task 260321-iwc: Fix README Accuracy — Remove mDNS References Summary

**README corrected to show Pi-hole DNS (not mDNS) resolves jellyfin.local to 192.168.1.101, mermaid diagram IP fixed, Pi-hole DHCP role documented, and Initial Setup + Day-to-Day Usage sections added**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-21T00:00:00Z
- **Completed:** 2026-03-21T00:05:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Removed incorrect "resolved via mDNS" text from Jellyfin access table and replaced with accurate Pi-hole DNS explanation
- Fixed mermaid diagram: `jellyfin.local -> .101` (was `.100`), updated Pi-hole node to show DNS + DHCP role, added DNS query edge from mac to pumpkin-pi
- Updated Stack section to describe Pi-hole as "LAN DNS + DHCP, pinned to pumpkin-pi"
- Restructured Quick Start into "Initial Setup" with prerequisites (bw CLI, ~/.kube, router DHCP) and post-bootstrap notes
- Added "Day-to-Day Usage" section covering deployments, cluster health, service URLs (including Pi-hole admin at port 8080), and media upload cross-reference

## Task Commits

1. **Task 1: Fix mDNS references, correct mermaid diagram, and update Jellyfin access table** - `a916b6e` (fix)
2. **Task 2: Add initial setup and day-to-day usage sections** - `3038f3a` (docs)

## Files Created/Modified

- `/Users/KaelanDavis/Documents/Projects/coding/pi-k3s-homelab/README.md` - Corrected DNS architecture, diagram IPs, access table, and added operational sections

## Decisions Made

- None — followed plan as specified. Source of truth was `charts/pihole/values.yaml` (localDns entries) and `charts/jellyfin/values.yaml` (ingress hosts).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Self-Check: PASSED

- `README.md` modified and committed: FOUND (commits a916b6e and 3038f3a verified)
- `grep -c "mDNS" README.md` returns 0: PASS
- Mermaid diagram contains `.101` for jellyfin.local: PASS
- "Day-to-Day" section present: PASS
- "Initial Setup" section present: PASS
- Pi-hole described with DHCP role: PASS

---
*Quick task: 260321-iwc*
*Completed: 2026-03-21*
