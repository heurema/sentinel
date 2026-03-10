#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/../../src/lib/runner.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

passed=0; failed=0

assert_eq() {
  name="$1"; expected="$2"; actual="$3"
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s\n  expected: %s\n  got:      %s\n' "$name" "$expected" "$actual"
    failed=$((failed + 1))
  fi
}

assert_contains() {
  name="$1"; needle="$2"; haystack="$3"
  case "$haystack" in
    *"$needle"*) passed=$((passed + 1)) ;;
    *)
      printf 'FAIL: %s\n  expected to contain: %s\n  got: %s\n' "$name" "$needle" "$haystack"
      failed=$((failed + 1))
      ;;
  esac
}

assert_exit() {
  name="$1"; expected_code="$2"
  shift 2
  actual_code=0
  "$@" >/dev/null 2>&1 || actual_code=$?
  assert_eq "$name (exit code)" "$expected_code" "$actual_code"
}

# ---------------------------------------------------------------------------
# LOAD tests
# ---------------------------------------------------------------------------

# LOAD: valid registry + config returns 0
_rc=0
(
  . "$RUNNER"
  runner_load "$FIXTURES/valid-registry.json" "$FIXTURES/valid-config.json"
) >/dev/null 2>&1 || _rc=$?
assert_eq "LOAD valid registry+config returns 0" "0" "$_rc"

# LOAD: missing registry returns exit 4
_rc=0
(
  . "$RUNNER"
  runner_load "/nonexistent/registry.json" "$FIXTURES/valid-config.json"
) >/dev/null 2>&1 || _rc=$?
assert_eq "LOAD missing registry returns exit 4" "4" "$_rc"

# LOAD: missing config returns exit 5
_rc=0
(
  . "$RUNNER"
  runner_load "$FIXTURES/valid-registry.json" "/nonexistent/config.json"
) >/dev/null 2>&1 || _rc=$?
assert_eq "LOAD missing config returns exit 5" "5" "$_rc"

# LOAD: sets _RUNNER_REGISTRY and _RUNNER_CONFIG
_out=$(
  . "$RUNNER"
  runner_load "$FIXTURES/valid-registry.json" "$FIXTURES/valid-config.json"
  printf '%s\n' "$_RUNNER_REGISTRY" | jq -r 'length'
  printf '%s\n' "$_RUNNER_CONFIG" | jq -r '.check_timeout_ms'
)
_reg_len=$(printf '%s\n' "$_out" | head -1)
_cfg_to=$(printf '%s\n' "$_out" | tail -1)
assert_eq "LOAD sets _RUNNER_REGISTRY (length=2)" "2" "$_reg_len"
assert_eq "LOAD sets _RUNNER_CONFIG (check_timeout_ms=5000)" "5000" "$_cfg_to"

# ---------------------------------------------------------------------------
# VALIDATE tests
# ---------------------------------------------------------------------------

# VALIDATE: valid registry returns 0
_rc=0
(
  . "$RUNNER"
  _reg=$(cat "$FIXTURES/valid-registry.json")
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_validate "$_reg" "$_cfg" "$FIXTURES"
) >/dev/null 2>&1 || _rc=$?
assert_eq "VALIDATE valid registry returns 0" "0" "$_rc"

# VALIDATE: duplicate check_id returns nonzero
_dup_reg='[
  {"id":"dup-id","file":"mock-check-pass.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true},
  {"id":"dup-id","file":"mock-check-fail.sh","category":"secrets","severity_default":"high","weight":8,"timeout_ms":5000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true}
]'
_rc=0
(
  . "$RUNNER"
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_validate "$_dup_reg" "$_cfg" "$FIXTURES"
) >/dev/null 2>&1 || _rc=$?
if [ "$_rc" -ne 0 ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: VALIDATE duplicate check_id should return nonzero, got 0\n'
  failed=$((failed + 1))
fi

# VALIDATE: missing script file emits warning to stderr (non-fatal, returns 0)
_missing_reg='[
  {"id":"missing-check","file":"no-such-file.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true}
]'
_stderr_out=$(
  . "$RUNNER"
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_validate "$_missing_reg" "$_cfg" "$FIXTURES" 2>&1
)
assert_contains "VALIDATE missing script emits warning" "missing-check" "$_stderr_out"

# ---------------------------------------------------------------------------
# PLAN tests
# ---------------------------------------------------------------------------

# PLAN: both checks enabled — planned has 2 entries
_plan_out=$(
  . "$RUNNER"
  _reg=$(cat "$FIXTURES/valid-registry.json")
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_plan "$_reg" "$_cfg" "darwin"
)
_planned_count=$(printf '%s' "$_plan_out" | jq '.planned | length')
assert_eq "PLAN both checks enabled — planned count=2" "2" "$_planned_count"

# PLAN: disabled_checks excludes one entry
_cfg_disabled='{"disabled_checks":["mock-pass"],"disabled_categories":[],"ignore_paths":[],"check_timeout_ms":5000,"report_retention_days":90}'
_plan_out=$(
  . "$RUNNER"
  _reg=$(cat "$FIXTURES/valid-registry.json")
  runner_plan "$_reg" "$_cfg_disabled" "darwin"
)
_planned_count=$(printf '%s' "$_plan_out" | jq '.planned | length')
_excluded_count=$(printf '%s' "$_plan_out" | jq '.excluded | length')
assert_eq "PLAN disabled_checks reduces planned to 1" "1" "$_planned_count"
assert_eq "PLAN disabled_checks adds to excluded (count=1)" "1" "$_excluded_count"

# PLAN: exclusion reason recorded
_excl_reason=$(printf '%s' "$_plan_out" | jq -r '.excluded[0].reason')
assert_contains "PLAN exclusion reason contains 'disabled'" "disabled" "$_excl_reason"

# PLAN: platform filtering excludes windows-only check
_win_reg='[
  {"id":"win-only","file":"mock-check-pass.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000,"optional":false,"platforms":["windows"],"default_enabled":true}
]'
_plan_out=$(
  . "$RUNNER"
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_plan "$_win_reg" "$_cfg" "darwin"
)
_planned_count=$(printf '%s' "$_plan_out" | jq '.planned | length')
_excl_reason=$(printf '%s' "$_plan_out" | jq -r '.excluded[0].reason')
assert_eq "PLAN platform filter excludes windows-only check" "0" "$_planned_count"
assert_contains "PLAN platform exclusion reason" "platform" "$_excl_reason"

# PLAN: disabled_categories excludes matching category
_cfg_disabled_cat='{"disabled_checks":[],"disabled_categories":["secrets"],"ignore_paths":[],"check_timeout_ms":5000,"report_retention_days":90}'
_plan_out=$(
  . "$RUNNER"
  _reg=$(cat "$FIXTURES/valid-registry.json")
  runner_plan "$_reg" "$_cfg_disabled_cat" "darwin"
)
_planned_count=$(printf '%s' "$_plan_out" | jq '.planned | length')
assert_eq "PLAN disabled_categories excludes all secrets checks" "0" "$_planned_count"

# PLAN: default_enabled=false excludes check
_disabled_default_reg='[
  {"id":"no-default","file":"mock-check-pass.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000,"optional":false,"platforms":["darwin","linux"],"default_enabled":false}
]'
_plan_out=$(
  . "$RUNNER"
  _cfg=$(cat "$FIXTURES/valid-config.json")
  runner_plan "$_disabled_default_reg" "$_cfg" "darwin"
)
_planned_count=$(printf '%s' "$_plan_out" | jq '.planned | length')
assert_eq "PLAN default_enabled=false excludes check" "0" "$_planned_count"

# ---------------------------------------------------------------------------
# RUN tests
# ---------------------------------------------------------------------------

# RUN: mock-pass produces PASS result
_pass_plan=$(jq -n --arg dir "$FIXTURES" \
  '{"planned": [{"id":"mock-pass","file":"mock-check-pass.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000}], "excluded": []}')
_run_out=$(
  . "$RUNNER"
  runner_run "$_pass_plan" "$FIXTURES" ""
)
_status=$(printf '%s' "$_run_out" | jq -r '.status')
_check_id=$(printf '%s' "$_run_out" | jq -r '.check_id')
assert_eq "RUN mock-pass produces status=PASS" "PASS" "$_status"
assert_eq "RUN mock-pass check_id=mock-pass" "mock-pass" "$_check_id"

# RUN: mock-fail produces FAIL result
_fail_plan=$(jq -n --arg dir "$FIXTURES" \
  '{"planned": [{"id":"mock-fail","file":"mock-check-fail.sh","category":"secrets","severity_default":"high","weight":8,"timeout_ms":5000}], "excluded": []}')
_run_out=$(
  . "$RUNNER"
  runner_run "$_fail_plan" "$FIXTURES" ""
)
_status=$(printf '%s' "$_run_out" | jq -r '.status')
assert_eq "RUN mock-fail produces status=FAIL" "FAIL" "$_status"

# RUN: bad JSON produces synthetic ERROR with error_kind=invalid_json
_bad_json_plan=$(jq -n \
  '{"planned": [{"id":"mock-bad-json","file":"mock-check-bad-json.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":5000}], "excluded": []}')
_run_out=$(
  . "$RUNNER"
  runner_run "$_bad_json_plan" "$FIXTURES" ""
)
_status=$(printf '%s' "$_run_out" | jq -r '.status')
_kind=$(printf '%s' "$_run_out" | jq -r '.error_kind')
assert_eq "RUN bad JSON produces status=ERROR" "ERROR" "$_status"
assert_eq "RUN bad JSON error_kind=invalid_json" "invalid_json" "$_kind"

# RUN: timeout produces synthetic ERROR with error_kind=timeout
# Use timeout_ms=1000 (1 second) so the sleep 30 gets killed fast
_timeout_plan=$(jq -n \
  '{"planned": [{"id":"mock-timeout","file":"mock-check-timeout.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":1000}], "excluded": []}')
_t_start=$(date +%s)
_run_out=$(
  . "$RUNNER"
  runner_run "$_timeout_plan" "$FIXTURES" ""
)
_t_end=$(date +%s)
_elapsed=$((_t_end - _t_start))
_status=$(printf '%s' "$_run_out" | jq -r '.status')
_kind=$(printf '%s' "$_run_out" | jq -r '.error_kind')
assert_eq "RUN timeout produces status=ERROR" "ERROR" "$_status"
assert_eq "RUN timeout error_kind=timeout" "timeout" "$_kind"
if [ "$_elapsed" -lt 10 ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: RUN timeout should complete in <10s, took %ds\n' "$_elapsed"
  failed=$((failed + 1))
fi

# RUN: JSONL output has one line per planned check (2 checks → 2 lines)
_multi_plan=$(cat "$FIXTURES/valid-registry.json" | jq \
  '{"planned": map({id: .id, file: .file, category: .category, severity_default: .severity_default, weight: .weight, timeout_ms: .timeout_ms}), "excluded": []}')
_run_lines=$(
  . "$RUNNER"
  runner_run "$_multi_plan" "$FIXTURES" "" | wc -l | tr -d ' '
)
assert_eq "RUN 2 planned checks produces 2 output lines" "2" "$_run_lines"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
