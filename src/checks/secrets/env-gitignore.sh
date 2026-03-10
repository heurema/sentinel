#!/usr/bin/env sh
# secrets-env-gitignore: Check that .env files are listed in .gitignore
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="secrets-env-gitignore"
TITLE=".env files not excluded from git"
CATEGORY="secrets"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"

REMEDIATION='{"description":"Add .env to .gitignore","argv":["sh","-c","echo '"'"'.env'"'"' >> .gitignore"],"risk":"safe"}'

has_gitignore=0
has_env=0
evidence="[]"
found=0

[ -f "$PROJECT_DIR/.gitignore" ] && has_gitignore=1

# Find .env files (not in node_modules, .git, vendor)
for envfile in $(find "$PROJECT_DIR" \( -name node_modules -o -name .git -o -name vendor \) -prune -o \( -name '.env' -o -name '.env.*' \) -print 2>/dev/null | head -20); do
  [ -f "$envfile" ] || continue
  has_env=1

  if [ "$has_gitignore" -eq 1 ]; then
    # Get relative path from project dir
    relpath="${envfile#$PROJECT_DIR/}"
    # Check if this file or pattern is in .gitignore
    # Match exact name, wildcard patterns like *.env or .env*
    basename_file=$(basename "$envfile")
    matched=0
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      case "$line" in
        '#'*|'') continue ;;
      esac
      # Direct name match or wildcard glob match
      case "$basename_file" in
        $line) matched=1; break ;;
      esac
      # Also check if relpath matches
      case "$relpath" in
        $line) matched=1; break ;;
      esac
    done < "$PROJECT_DIR/.gitignore"

    if [ "$matched" -eq 0 ]; then
      found=$((found + 1))
      resolved=$(resolve_path "$envfile")
      evidence=$(printf '%s' "$evidence" | jq \
        --arg p "$resolved" \
        --arg d "$relpath not found in .gitignore" \
        '. + [{"type":"file","path":$p,"detail":$d}]')
    fi
  else
    # No .gitignore at all — .env exists without gitignore
    found=$((found + 1))
    resolved=$(resolve_path "$envfile")
    relpath="${envfile#$PROJECT_DIR/}"
    evidence=$(printf '%s' "$evidence" | jq \
      --arg p "$resolved" \
      --arg d "$relpath exists but no .gitignore present" \
      '. + [{"type":"file","path":$p,"detail":$d}]')
  fi
done

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" "$evidence" "$REMEDIATION"
elif [ "$has_env" -eq 0 ] && [ "$has_gitignore" -eq 0 ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
