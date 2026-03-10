#!/usr/bin/env sh
# config-insecure-defaults: Check ~/.claude/settings.json for known insecure settings
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="config-insecure-defaults"
TITLE="Insecure defaults in Claude settings"
CATEGORY="config"

REMEDIATION='{"description":"Review and disable insecure settings in ~/.claude/settings.json","argv":["vi","~/.claude/settings.json"],"risk":"safe"}'

# Resolve settings file: explicit env > ~/.claude/settings.json
SETTINGS_FILE="${SENTINEL_SETTINGS_FILE:-}"

if [ -z "$SETTINGS_FILE" ]; then
  SETTINGS_FILE="$HOME/.claude/settings.json"
fi

# SKIP: no settings file
if [ ! -f "$SETTINGS_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# SKIP: unparseable JSON
if ! jq . "$SETTINGS_FILE" >/dev/null 2>&1; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

# Check 1: autoApprove: true
auto_approve=$(jq 'if .autoApprove == true then "true" else "false" end' "$SETTINGS_FILE")
if [ "$auto_approve" = '"true"' ]; then
  found=$((found + 1))
  evidence=$(printf '%s' "$evidence" | jq --arg p "$SETTINGS_FILE" \
    '. + [{"type":"file","path":$p,"detail":"autoApprove: true — agent actions approved without user confirmation"}]')
fi

# Check 2: bypassPermissions: true
bypass=$(jq 'if .bypassPermissions == true then "true" else "false" end' "$SETTINGS_FILE")
if [ "$bypass" = '"true"' ]; then
  found=$((found + 1))
  evidence=$(printf '%s' "$evidence" | jq --arg p "$SETTINGS_FILE" \
    '. + [{"type":"file","path":$p,"detail":"bypassPermissions: true — permission checks are disabled"}]')
fi

# Check 3: skipHooks: true
skip_hooks=$(jq 'if .skipHooks == true then "true" else "false" end' "$SETTINGS_FILE")
if [ "$skip_hooks" = '"true"' ]; then
  found=$((found + 1))
  evidence=$(printf '%s' "$evidence" | jq --arg p "$SETTINGS_FILE" \
    '. + [{"type":"file","path":$p,"detail":"skipHooks: true — hook execution is bypassed"}]')
fi

# Check 4: permissions.allow contains "*"
has_wildcard=$(jq 'if (.permissions.allow // []) | map(select(. == "*")) | length > 0 then "true" else "false" end' "$SETTINGS_FILE")
if [ "$has_wildcard" = '"true"' ]; then
  found=$((found + 1))
  evidence=$(printf '%s' "$evidence" | jq --arg p "$SETTINGS_FILE" \
    '. + [{"type":"file","path":$p,"detail":"permissions.allow contains \"*\" — all tools permitted globally"}]')
fi

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" "$evidence" "$REMEDIATION"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
