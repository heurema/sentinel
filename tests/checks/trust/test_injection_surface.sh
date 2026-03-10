#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/trust/injection-surface.sh"
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

# Test: project with injection pattern → WARN/medium, confidence 0.4
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-injected" sh "$CHECK")
assert_valid_json "injected - valid JSON" "$result"
assert_field "injected warns" "$result" ".status" "WARN"
assert_field "injected severity" "$result" ".severity" "medium"
assert_field "injected category" "$result" ".category" "trust"
assert_field "injected confidence" "$result" ".confidence" "0.4"

# Test: clean project → PASS
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-clean" sh "$CHECK")
assert_valid_json "clean - valid JSON" "$result"
assert_field "clean passes" "$result" ".status" "PASS"

# Test: project with symlink escaping outside → WARN
result=$(SENTINEL_PROJECT_DIR="$FIXTURES/project-symlink" sh "$CHECK")
assert_valid_json "symlink - valid JSON" "$result"
assert_field "symlink warns" "$result" ".status" "WARN"
assert_field "symlink severity" "$result" ".severity" "medium"
assert_field "symlink confidence" "$result" ".confidence" "0.4"

# Test: SENTINEL_PROJECT_DIR not set → SKIP
result=$(sh "$CHECK")
assert_valid_json "no env - valid JSON" "$result"
assert_field "no env skips" "$result" ".status" "SKIP"

# Test: nonexistent dir → SKIP
result=$(SENTINEL_PROJECT_DIR="/nonexistent/path" sh "$CHECK")
assert_valid_json "nonexistent - valid JSON" "$result"
assert_field "nonexistent skips" "$result" ".status" "SKIP"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
