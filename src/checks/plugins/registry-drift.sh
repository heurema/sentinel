#!/usr/bin/env sh
# plugins-registry-drift: Check for drift between installed and declared plugins
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="plugins-registry-drift"
TITLE="Installed plugins differ from declared plugins"
CATEGORY="plugins"

INSTALLED_FILE="${SENTINEL_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
SETTINGS_FILE="${SENTINEL_SETTINGS_FILE:-$HOME/.claude/settings.json}"

# SKIP if installed_plugins.json doesn't exist
if [ ! -f "$INSTALLED_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Read installed plugin names
installed_names=$(jq -r '.[].name' "$INSTALLED_FILE" 2>/dev/null) || installed_names=""
installed_count=$(printf '%s\n' "$installed_names" | grep -c . 2>/dev/null || printf '0')

# If no plugins installed, PASS
if [ "$installed_count" -eq 0 ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

# Read declared plugins from settings.json (plugins or enabledPlugins key)
declared_names=""
if [ -f "$SETTINGS_FILE" ]; then
  # Try "plugins" key first (array of strings or array of objects with name)
  declared_raw=$(jq -r '(.plugins // .enabledPlugins // []) | if type == "array" then .[] | if type == "object" then .name else . end else empty end' "$SETTINGS_FILE" 2>/dev/null) || declared_raw=""
  declared_names="$declared_raw"
fi

declared_count=$(printf '%s\n' "$declared_names" | grep -c . 2>/dev/null || printf '0')

# Build sets and compare
evidence="[]"
drift_found=0

# Find installed plugins not in declared set
for name in $installed_names; do
  if ! printf '%s\n' "$declared_names" | grep -qxF "$name" 2>/dev/null; then
    evidence=$(printf '%s' "$evidence" | jq \
      --arg n "$name" \
      '. + [{"type":"plugin_drift","detail":$n}]')
    drift_found=$((drift_found + 1))
  fi
done

# Also check declared not in installed (reverse drift)
for name in $declared_names; do
  if ! printf '%s\n' "$installed_names" | grep -qxF "$name" 2>/dev/null; then
    evidence=$(printf '%s' "$evidence" | jq \
      --arg n "$name (declared but not installed)" \
      '. + [{"type":"plugin_drift","detail":$n}]')
    drift_found=$((drift_found + 1))
  fi
done

if [ "$drift_found" -gt 0 ]; then
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Reconcile installed_plugins.json with declared plugins in settings.json","argv":["echo","Update settings.json plugins list or remove undeclared plugins"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
