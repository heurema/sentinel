#!/usr/bin/env sh
# secrets-dotfiles: Check shell config files for hardcoded secrets
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../lib/emit.sh"

CHECK_ID="secrets-dotfiles"
TITLE="Hardcoded secrets in shell config files"
CATEGORY="secrets"

REMEDIATION='{"description":"Remove secrets from shell config, use a secrets manager","argv":["sed","-i","","/_API_KEY=/d","~/.zshrc"],"risk":"caution"}'

# Shell config files to scan
DOTFILES=".bashrc .zshrc .bash_profile .zprofile .profile"
SECRET_PATTERN='export[[:space:]].*(_API_KEY|_SECRET|_TOKEN|_PASSWORD)='

evidence="[]"
found=0
any_exists=0

for dotfile in $DOTFILES; do
  filepath="$HOME/$dotfile"
  [ -f "$filepath" ] || continue
  any_exists=1

  # Scan for secret export patterns
  matches=$(grep -nE "$SECRET_PATTERN" "$filepath" 2>/dev/null) || true
  if [ -n "$matches" ]; then
    # Process each matching line
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      lineno=$(printf '%s' "$line" | cut -d: -f1)
      content=$(printf '%s' "$line" | cut -d: -f2-)
      # Redact the value (everything after the = sign)
      key_part=$(printf '%s' "$content" | sed 's/=.*//')
      val_part=$(printf '%s' "$content" | sed 's/[^=]*=//')
      redacted_content="${key_part}=$(redact "$val_part")"
      found=$((found + 1))
      resolved=$(resolve_path "$filepath")
      evidence=$(printf '%s' "$evidence" | jq \
        --arg p "$resolved" \
        --arg d "Line ${lineno}: ${redacted_content}" \
        '. + [{"type":"file","path":$p,"detail":$d,"redacted":true}]')
    done << EOF
$matches
EOF
  fi
done

if [ "$found" -gt 0 ]; then
  emit_fail "$CHECK_ID" "$TITLE" "$CATEGORY" "high" "$evidence" "$REMEDIATION"
elif [ "$any_exists" -eq 0 ]; then
  emit_skip "$CHECK_ID" "$TITLE" "$CATEGORY"
else
  emit_pass "$CHECK_ID" "$TITLE" "$CATEGORY"
fi
