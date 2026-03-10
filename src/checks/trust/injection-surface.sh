#!/usr/bin/env sh
# trust-injection-surface: Scan project for prompt injection patterns and symlink escapes
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="trust-injection-surface"
TITLE="Potential prompt injection surface detected"
CATEGORY="trust"

PROJECT_DIR="${SENTINEL_PROJECT_DIR:-}"

# SKIP: env not set or not a directory
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
  exit 0
fi

evidence="[]"
found=0

# 1. Scan markdown files for injection patterns
# Patterns: HTML comment with system, <system-reminder>, IMPORTANT:.*override, ignore previous instructions
PATTERN='<!--.*system.*-->|<system-reminder>|IMPORTANT:.*override|ignore previous instructions'

# Find markdown files, exclude .git, limit depth to avoid infinite loops via symlinks
while IFS= read -r mdfile; do
  [ -f "$mdfile" ] || continue
  matches=$(grep -iE "$PATTERN" "$mdfile" 2>/dev/null | head -3)
  if [ -n "$matches" ]; then
    found=$((found + 1))
    first_match=$(printf '%s' "$matches" | head -1)
    evidence=$(printf '%s' "$evidence" | jq \
      --arg p "$mdfile" \
      --arg d "Injection pattern matched: $first_match" \
      '. + [{"type":"file","path":$p,"detail":$d}]')
  fi
done << EOF
$(find "$PROJECT_DIR" \( -name .git -o -name node_modules -o -name vendor \) -prune \
  -o -name "*.md" -print 2>/dev/null | head -50)
EOF

# 2. Check for symlinks pointing outside project
resolved_project=$(resolve_path "$PROJECT_DIR")

while IFS= read -r lnk; do
  [ -L "$lnk" ] || continue
  target=$(readlink "$lnk" 2>/dev/null || true)
  [ -n "$target" ] || continue
  # Resolve target: if relative, resolve against symlink's directory
  case "$target" in
    /*) abs_target="$target" ;;
    *)  link_dir=$(dirname "$lnk")
        abs_target=$(resolve_path "$link_dir/$target") ;;
  esac
  # Check if target starts with project dir
  case "$abs_target" in
    "$resolved_project"*) ;; # inside project — OK
    *)
      found=$((found + 1))
      evidence=$(printf '%s' "$evidence" | jq \
        --arg p "$lnk" \
        --arg d "Symlink escapes project: $lnk -> $target" \
        '. + [{"type":"file","path":$p,"detail":$d}]')
      ;;
  esac
done << EOF
$(find "$PROJECT_DIR" -type l 2>/dev/null | head -20)
EOF

if [ "$found" -gt 0 ]; then
  emit_warn "$CHECK_ID" "$TITLE" "$CATEGORY" "medium" \
    "$evidence" \
    '{"description":"Review and remove suspicious patterns or symlinks from project files","argv":["grep","-r","system-reminder","."],"risk":"safe"}' \
    | jq '. + {"confidence": 0.4}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
