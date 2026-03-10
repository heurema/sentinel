#!/usr/bin/env sh
# plugins-unverified: Check for plugins without verified:true
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="plugins-unverified"
TITLE="Installed plugins without verification"
CATEGORY="plugins"

INSTALLED_FILE="${SENTINEL_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"

# SKIP if installed_plugins.json doesn't exist
if [ ! -f "$INSTALLED_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

plugin_count=$(jq 'length' "$INSTALLED_FILE" 2>/dev/null) || plugin_count=0

# No plugins → SKIP (empty array)
if [ "$plugin_count" -eq 0 ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

# Find plugins where verified is false or missing
while IFS= read -r entry; do
  name=$(printf '%s' "$entry" | jq -r '.name // ""')
  verified=$(printf '%s' "$entry" | jq -r '.verified // false')

  if [ "$verified" != "true" ]; then
    evidence=$(printf '%s' "$evidence" | jq \
      --arg n "$name" \
      '. + [{"type":"unverified_plugin","detail":$n}]')
    found=$((found + 1))
  fi
done << EOF
$(jq -c '.[]' "$INSTALLED_FILE" 2>/dev/null)
EOF

if [ "$found" -gt 0 ]; then
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Only install plugins from trusted sources and set verified:true after review","argv":["echo","Review and verify plugin sources"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
