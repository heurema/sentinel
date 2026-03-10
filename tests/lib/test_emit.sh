#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMIT="$SCRIPT_DIR/../../src/lib/emit.sh"

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

# Test emit_pass
result=$(. "$EMIT" && emit_pass "test-id" "Test Title" "secrets")
assert_valid_json "emit_pass produces valid JSON" "$result"
assert_field "emit_pass check_id" "$result" ".check_id" "test-id"
assert_field "emit_pass status" "$result" ".status" "PASS"
assert_field "emit_pass category" "$result" ".category" "secrets"

# Test emit_fail with evidence
result=$(. "$EMIT" && emit_fail "test-id" "Test Title" "secrets" "critical" \
  '[{"type":"file","path":"/tmp/test","detail":"found secret","redacted":true}]' \
  '{"description":"fix it","argv":["echo","fix"],"risk":"safe"}')
assert_valid_json "emit_fail produces valid JSON" "$result"
assert_field "emit_fail status" "$result" ".status" "FAIL"
assert_field "emit_fail severity" "$result" ".severity" "critical"
assert_field "emit_fail evidence count" "$result" ".evidence | length" "1"

# Test emit_warn
result=$(. "$EMIT" && emit_warn "test-id" "Test Title" "secrets" "medium" \
  '[{"type":"config","detail":"weak setting"}]' \
  '{"description":"tighten","argv":["echo","fix"],"risk":"safe"}')
assert_valid_json "emit_warn produces valid JSON" "$result"
assert_field "emit_warn status" "$result" ".status" "WARN"
assert_field "emit_warn severity" "$result" ".severity" "medium"

# Test emit_skip
result=$(. "$EMIT" && emit_skip "test-id" "Test Title" "secrets")
assert_valid_json "emit_skip produces valid JSON" "$result"
assert_field "emit_skip status" "$result" ".status" "SKIP"

# Test emit_unsupported
result=$(. "$EMIT" && emit_unsupported "test-id" "Test Title" "secrets" "git not found")
assert_valid_json "emit_unsupported produces valid JSON" "$result"
assert_field "emit_unsupported status" "$result" ".status" "UNSUPPORTED"

# Test JSON safety: title with quotes
result=$(. "$EMIT" && emit_pass "test-id" 'Title with "quotes" and \backslash' "secrets")
assert_valid_json "emit_pass handles special chars" "$result"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
