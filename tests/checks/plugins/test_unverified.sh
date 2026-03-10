#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/plugins/unverified.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

passed=0; failed=0

assert_valid_json() {
  name="$1"; json="$2"
  if printf '%s' "$json" | jq . >/dev/null 2>&1; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s — invalid JSON: %s\n' "$name" "$json"
    failed=$((failed + 1))
  fi
}

assert_field() {
  name="$1"; json="$2"; field="$3"; expected="$4"
  actual=$(printf '%s' "$json" | jq -r "$field")
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s — %s: expected "%s", got "%s"\n' "$name" "$field" "$expected" "$actual"
    failed=$((failed + 1))
  fi
}

# Test: one plugin missing verified field → WARN
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/unverified/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "unverified - valid JSON" "$result"
assert_field "unverified - status WARN" "$result" ".status" "WARN"
assert_field "unverified - severity medium" "$result" ".severity" "medium"
assert_field "unverified - has evidence" "$result" '.evidence | length > 0' "true"
assert_field "unverified - evidence names sketchy plugin" "$result" '.evidence[0].detail' "sketchy"

# Test: all plugins have verified:true → PASS
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/verified/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "verified - valid JSON" "$result"
assert_field "verified - status PASS" "$result" ".status" "PASS"

# Test: installed_plugins.json does not exist → SKIP
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/empty/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "empty - valid JSON" "$result"
assert_field "empty - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
