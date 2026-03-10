#!/usr/bin/env sh
# plugins-scope-leakage: Check for user-scoped plugins with project-specific paths
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="plugins-scope-leakage"
TITLE="User-scoped plugin installed in project directory"
CATEGORY="plugins"

INSTALLED_FILE="${SENTINEL_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"

# SKIP if installed_plugins.json doesn't exist
if [ ! -f "$INSTALLED_FILE" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

plugin_count=$(jq 'length' "$INSTALLED_FILE" 2>/dev/null) || plugin_count=0

# No plugins → PASS
if [ "$plugin_count" -eq 0 ]; then
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

# For each user-scoped plugin, check if path is in a project directory
# Project heuristic: path contains /works/ or /personal/ but NOT under ~/.claude/plugins/
while IFS= read -r entry; do
  name=$(printf '%s' "$entry" | jq -r '.name // ""')
  scope=$(printf '%s' "$entry" | jq -r '.scope // ""')
  path=$(printf '%s' "$entry" | jq -r '.path // ""')

  [ "$scope" = "user" ] || continue
  [ -n "$path" ] || continue

  # Check if path is in a project directory.
  # Project heuristic: path contains a known project segment (/works/ or /personal/).
  # Global (user) paths live directly under ~/.claude/plugins/ with no project segment.
  is_project_path=0
  case "$path" in
    */works/*|*/personal/*)
      is_project_path=1 ;;
  esac

  if [ "$is_project_path" -eq 1 ]; then
    evidence=$(printf '%s' "$evidence" | jq \
      --arg n "$name" --arg p "$path" \
      '. + [{"type":"scope_leak","detail":($n + ": user-scoped at " + $p)}]')
    found=$((found + 1))
  fi
done << EOF
$(jq -c '.[]' "$INSTALLED_FILE" 2>/dev/null)
EOF

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" \
    "$evidence" \
    '{"description":"Change plugin scope to project or reinstall to global location ~/.claude/plugins/","argv":["echo","Fix plugin scope or path"],"risk":"safe"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
