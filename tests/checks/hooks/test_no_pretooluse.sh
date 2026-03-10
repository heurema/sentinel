#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/hooks/no-pretooluse.sh"
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

# Test: {} (no hooks at all) → FAIL/critical
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-hooks/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "no-hooks - valid JSON" "$result"
assert_field "no-hooks - status FAIL" "$result" ".status" "FAIL"
assert_field "no-hooks - severity critical" "$result" ".severity" "critical"

# Test: partial hooks (only Bash covered) → WARN/high
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/partial-hooks/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "partial-hooks - valid JSON" "$result"
assert_field "partial-hooks - status WARN" "$result" ".status" "WARN"
assert_field "partial-hooks - severity high" "$result" ".severity" "high"

# Test: full hooks (all 4 destructive tools covered) → PASS
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/full-hooks/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "full-hooks - valid JSON" "$result"
assert_field "full-hooks - status PASS" "$result" ".status" "PASS"

# Test: neither settings file exists → SKIP
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-settings/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/no-settings" \
  sh "$CHECK")
assert_valid_json "no-settings - valid JSON" "$result"
assert_field "no-settings - status SKIP" "$result" ".status" "SKIP"

# Test: project settings.json used when global missing
result=$(SENTINEL_SETTINGS_FILE="$FIXTURES/no-settings/settings.json" \
  SENTINEL_PROJECT_DIR="$FIXTURES/project-full-hooks" \
  sh "$CHECK")
assert_valid_json "project-settings - valid JSON" "$result"
assert_field "project-settings - status PASS" "$result" ".status" "PASS"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
