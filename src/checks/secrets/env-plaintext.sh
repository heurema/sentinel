#!/usr/bin/env sh
# secrets-env-plaintext: Check for plaintext .env files with API keys
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="secrets-env-plaintext"
TITLE="Plaintext .env files with API keys"
CATEGORY="secrets"
PROJECT_DIR="${SENTINEL_PROJECT_DIR:-.}"

# Secret patterns (case-insensitive grep)
PATTERNS='_API_KEY=|_SECRET=|_TOKEN=|_PASSWORD=|ANTHROPIC_API|OPENAI_API|AWS_SECRET|GITHUB_TOKEN'

evidence="[]"
found=0

# Find .env files in project (not in node_modules, .git, vendor)
for envfile in $(find "$PROJECT_DIR" \( -name node_modules -o -name .git -o -name vendor \) -prune -o \( -name '.env' -o -name '.env.*' \) -print 2>/dev/null | head -20); do
  [ -f "$envfile" ] || continue
  matches=$(grep -iE "$PATTERNS" "$envfile" 2>/dev/null | head -5)
  if [ -n "$matches" ]; then
    found=$((found + 1))
    resolved=$(resolve_path "$envfile")
    # Redact: show key name only
    first_key=$(printf '%s' "$matches" | head -1 | cut -d= -f1)
    first_val=$(printf '%s' "$matches" | head -1 | cut -d= -f2)
    evidence=$(printf '%s' "$evidence" | jq --arg p "$resolved" --arg d "Contains ${first_key}=$(redact "$first_val")" \
      '. + [{"type":"file","path":$p,"detail":$d,"redacted":true}]')
  fi
done

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "critical" \
    "$evidence" \
    '{"description":"Encrypt .env files with sops+age or remove secrets to a vault","argv":["sops","-e","--input-type","dotenv",".env"],"risk":"caution"}'
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
