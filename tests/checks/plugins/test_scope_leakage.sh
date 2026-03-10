#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/plugins/scope-leakage.sh"
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

# Test: user-scoped plugin with project path → FAIL
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/leaky/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "leaky - valid JSON" "$result"
assert_field "leaky - status FAIL" "$result" ".status" "FAIL"
assert_field "leaky - severity high" "$result" ".severity" "high"
assert_field "leaky - has evidence" "$result" '.evidence | length > 0' "true"

# Test: project-scoped plugin with project path → PASS
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/clean/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "clean - valid JSON" "$result"
assert_field "clean - status PASS" "$result" ".status" "PASS"

# Test: user-scoped plugin with global path → PASS
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/global/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "global - valid JSON" "$result"
assert_field "global - status PASS" "$result" ".status" "PASS"

# Test: installed_plugins.json does not exist → SKIP
result=$(SENTINEL_INSTALLED_PLUGINS="$FIXTURES/empty/installed_plugins.json" \
  sh "$CHECK")
assert_valid_json "empty - valid JSON" "$result"
assert_field "empty - status SKIP" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
