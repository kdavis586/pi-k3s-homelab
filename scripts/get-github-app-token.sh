#!/usr/bin/env bash
# Exchanges GitHub App credentials for an installation access token.
# Requires: bw (Bitwarden CLI, unlocked), openssl, curl
#
# Usage: get-github-app-token.sh <app-id> <installation-id> <bw-note-name>
# Outputs: installation access token (plain text, for use as GITHUB_TOKEN)

set -euo pipefail

APP_ID="${1:?Usage: $0 <app-id> <installation-id> <bw-note-name>}"
INSTALLATION_ID="${2:?}"
BW_NOTE="${3:?}"

# ── Fetch PEM from Bitwarden ────────────────────────────────────────────────
PEM=$(bw get notes "$BW_NOTE" 2>/dev/null) \
  || { echo "Error: Bitwarden locked or note '$BW_NOTE' not found." >&2; exit 1; }

# ── Build JWT (header.payload.signature) ────────────────────────────────────
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

NOW=$(date +%s)
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
PAYLOAD=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((NOW - 60))" "$((NOW + 540))" "$APP_ID" | b64url)

SIGNATURE=$(printf '%s' "$HEADER.$PAYLOAD" \
  | openssl dgst -sha256 -sign <(printf '%s' "$PEM") -binary \
  | b64url)

JWT="$HEADER.$PAYLOAD.$SIGNATURE"

# ── Exchange JWT for installation access token ───────────────────────────────
RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens")

TOKEN=$(printf '%s' "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

printf '%s' "$TOKEN"
