#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../../../src/checks/config/stale-sessions.sh"
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

# Test: stale session dir → WARN/low
result=$(SENTINEL_PROJECTS_DIR="$FIXTURES/stale-projects" sh "$CHECK")
assert_valid_json "stale - valid JSON" "$result"
assert_field "stale warns" "$result" ".status" "WARN"
assert_field "stale severity" "$result" ".severity" "low"
assert_field "stale category" "$result" ".category" "config"

# Test: recent session dir → PASS
result=$(SENTINEL_PROJECTS_DIR="$FIXTURES/recent-projects" sh "$CHECK")
assert_valid_json "recent - valid JSON" "$result"
assert_field "recent passes" "$result" ".status" "PASS"

# Test: projects dir doesn't exist → SKIP
result=$(SENTINEL_PROJECTS_DIR="/nonexistent/projects" sh "$CHECK")
assert_valid_json "missing dir - valid JSON" "$result"
assert_field "missing dir skips" "$result" ".status" "SKIP"

# Test: empty projects dir (no subdirs) → PASS
EMPTY_DIR="$(mktemp -d)"
result=$(SENTINEL_PROJECTS_DIR="$EMPTY_DIR" sh "$CHECK")
assert_valid_json "empty dir - valid JSON" "$result"
assert_field "empty dir passes" "$result" ".status" "PASS"
rmdir "$EMPTY_DIR"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
