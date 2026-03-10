#!/usr/bin/env sh
# trust-broad-permissions: Check Claude settings.json for overly permissive allow lists
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="trust-broad-permissions"
TITLE="Overly permissive Claude tool allow list"
CATEGORY="trust"

REMEDIATION='{"description":"Restrict allow list to specific tools needed","argv":["vi",".claude/settings.json"],"risk":"safe"}'

# Resolve settings file: explicit env > project .claude/settings.json
# No global fallback — caller must provide context via env
SETTINGS_FILE="${SENTINEL_SETTINGS_FILE:-}"

if [ -z "$SETTINGS_FILE" ]; then
  PROJECT_DIR="${SENTINEL_PROJECT_DIR:-}"
  if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
  fi
fi

# SKIP: no settings file found
if [ -z "$SETTINGS_FILE" ] || [ ! -f "$SETTINGS_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Validate JSON parseable
if ! jq . "$SETTINGS_FILE" >/dev/null 2>&1; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Extract allow array (null if missing)
allow_count=$(jq 'if .permissions.allow then (.permissions.allow | length) else 0 end' "$SETTINGS_FILE")

# No permissions key or empty allow — safe defaults
if [ "$allow_count" -eq 0 ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Check for unrestricted wildcard "*"
has_wildcard=$(jq 'if .permissions.allow then (.permissions.allow | map(select(. == "*")) | length) else 0 end' "$SETTINGS_FILE")

if [ "$has_wildcard" -gt 0 ]; then
  evidence=$(jq -n --arg p "$SETTINGS_FILE" \
    '[{"type":"file","path":$p,"detail":"Unrestricted wildcard \"*\" in permissions.allow grants access to all tools"}]')
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" "$evidence" "$REMEDIATION"
  exit 0
fi

# Check for Bash(*) — allows any bash command
has_bash_wildcard=$(jq 'if .permissions.allow then (.permissions.allow | map(select(. == "Bash(*)")) | length) else 0 end' "$SETTINGS_FILE")

if [ "$has_bash_wildcard" -gt 0 ]; then
  evidence=$(jq -n --arg p "$SETTINGS_FILE" \
    '[{"type":"file","path":$p,"detail":"Bash(*) allows execution of any bash command without restrictions"}]')
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "high" "$evidence" "$REMEDIATION"
  exit 0
fi

# Scoped permissions — pass
emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
