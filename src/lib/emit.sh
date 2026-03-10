#!/usr/bin/env sh
# emit.sh — JSON output helpers for sentinel checks
# Usage: . "$SENTINEL_LIB/emit.sh"

# emit_pass <check_id> <title> <category>
emit_pass() {
  jq -n --arg id "$1" --arg t "$2" --arg c "$3" \
    '{check_id:$id, title:$t, category:$c, status:"PASS", evidence:[]}'
}

# emit_warn <check_id> <title> <category> <severity> <evidence_json> <remediation_json>
emit_warn() {
  jq -n --arg id "$1" --arg t "$2" --arg c "$3" --arg s "$4" \
    --argjson ev "$5" --argjson rem "$6" \
    '{check_id:$id, title:$t, category:$c, status:"WARN", severity:$s, evidence:$ev, remediation:$rem}'
}

# emit_fail <check_id> <title> <category> <severity> <evidence_json> <remediation_json>
emit_fail() {
  jq -n --arg id "$1" --arg t "$2" --arg c "$3" --arg s "$4" \
    --argjson ev "$5" --argjson rem "$6" \
    '{check_id:$id, title:$t, category:$c, status:"FAIL", severity:$s, evidence:$ev, remediation:$rem}'
}

# emit_skip <check_id> <title> <category>
emit_skip() {
  jq -n --arg id "$1" --arg t "$2" --arg c "$3" \
    '{check_id:$id, title:$t, category:$c, status:"SKIP", evidence:[]}'
}

# emit_unsupported <check_id> <title> <category> <reason>
emit_unsupported() {
  jq -n --arg id "$1" --arg t "$2" --arg c "$3" --arg r "$4" \
    '{check_id:$id, title:$t, category:$c, status:"UNSUPPORTED", evidence:[{type:"runtime", detail:$r}]}'
}

# redact <value> — replaces all but first 4 chars with ***
redact() {
  if [ ${#1} -le 4 ]; then
    printf '***'
  else
    printf '%s***' "$(printf '%s' "$1" | cut -c1-4)"
  fi
}

# resolve_path <path> — expand ~ to $HOME, resolve symlinks
resolve_path() {
  _p="$1"
  case "$_p" in
    "~"*) _p="$HOME$(printf '%s' "$_p" | cut -c2-)" ;;
  esac
  # Portable realpath: python3 fallback for macOS (no readlink -f)
  if command -v realpath >/dev/null 2>&1; then
    realpath "$_p" 2>/dev/null || printf '%s' "$_p"
  else
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$_p" 2>/dev/null || printf '%s' "$_p"
  fi
}

# sha256_hash <string> — portable SHA-256 (macOS: shasum, Linux: sha256sum)
sha256_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-12
  else
    printf '%s' "$1" | shasum -a 256 | cut -c1-12
  fi
}
