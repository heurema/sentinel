#!/usr/bin/env sh
# secrets-runtime-env: Check current process environment for sensitive variables
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="secrets-runtime-env"
TITLE="Sensitive credentials in runtime environment"
CATEGORY="secrets"

REMEDIATION='{"description":"Unset sensitive environment variables","argv":["unset","ANTHROPIC_API_KEY"],"risk":"safe"}'

# Fixed list of sensitive variable names to check
SENSITIVE_VARS="ANTHROPIC_API_KEY OPENAI_API_KEY AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN GITHUB_TOKEN GITHUB_PAT GITLAB_TOKEN SLACK_TOKEN TELEGRAM_BOT_TOKEN"

evidence="[]"
found=0

for var in $SENSITIVE_VARS; do
  # Use eval to check if var is set and non-empty (POSIX portable)
  val=$(eval "printf '%s' \"\${${var}:-}\"")
  if [ -n "$val" ]; then
    found=$((found + 1))
    redacted_val=$(redact "$val")
    evidence=$(printf '%s' "$evidence" | jq \
      --arg v "$var" \
      --arg d "${var}=$(printf '%s' "$redacted_val")" \
      '. + [{"type":"runtime","detail":$d,"redacted":true}]')
  fi
done

# DATABASE_URL: only flag if it contains credentials (://user:pass@host pattern)
db_url="${DATABASE_URL:-}"
if [ -n "$db_url" ]; then
  # Check for password in URL: ://something:something@
  if printf '%s' "$db_url" | grep -qE '://[^:]+:[^@]+@'; then
    found=$((found + 1))
    # Redact the password portion
    redacted_url=$(printf '%s' "$db_url" | sed 's|\(://[^:]*:\)[^@]*@|\1***@|')
    evidence=$(printf '%s' "$evidence" | jq \
      --arg d "DATABASE_URL contains credentials: $redacted_url" \
      '. + [{"type":"runtime","detail":$d,"redacted":true}]')
  fi
fi

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "critical" "$evidence" "$REMEDIATION"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
