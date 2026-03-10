#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTER="$SCRIPT_DIR/../../src/lib/reporter.sh"

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

assert_not_contains() {
  name="$1"; needle="$2"; haystack="$3"
  case "$haystack" in
    *"$needle"*) printf 'FAIL: %s\n  expected NOT to contain: %s\n' "$name" "$needle"; failed=$((failed + 1)) ;;
    *) passed=$((passed + 1)) ;;
  esac
}

assert_valid_json() {
  name="$1"; json="$2"
  if printf '%s' "$json" | jq . >/dev/null 2>&1; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s — invalid JSON\n' "$name"
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

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

META_JSON='{"run_id":"20260310T120000Z","completed_at":"2026-03-10T12:00:00Z","sentinel_version":"1.0.0","registry_hash":"abc123def456","scoring_version":1,"platform":"darwin","hostname":"myhost","scan_roots":["/home"],"effective_config":{},"config_sources":[]}'

PLAN_JSON='{"total":3,"executed":3,"skipped":0,"excluded":[]}'

RESULTS_JSON='[
  {"check_id":"secrets-env","title":"Plaintext Secrets","category":"secrets","status":"FAIL","severity":"critical","finding_id":"aabbccddeeff","fingerprint_version":1,"duration_ms":50},
  {"check_id":"hooks-verify","title":"Hook Verification","category":"hooks","status":"PASS","finding_id":"112233445566","fingerprint_version":1,"duration_ms":30},
  {"check_id":"config-perms","title":"Config Permissions","category":"config","status":"WARN","severity":"medium","finding_id":"aabbcc001122","fingerprint_version":1,"duration_ms":20}
]'

SCORING_JSON='{"total":45,"by_category":{"secrets":0,"hooks":100,"config":50},"reliability":1,"reliability_details":{"planned":3,"assessed":3,"errors":[]},"verdict":"FAIL","verdict_reasons":["critical or high severity FAIL exists"]}'

# ---------------------------------------------------------------------------
# PERSIST tests
# ---------------------------------------------------------------------------

TMPDIR_REPORTS="$(mktemp -d)"

# PERSIST: builds complete report JSON with meta, plan, results, scoring, reliability, verdict
report_path=$(. "$REPORTER" && reporter_persist "$META_JSON" "$PLAN_JSON" "$RESULTS_JSON" "$SCORING_JSON" "$TMPDIR_REPORTS")
report_json=$(cat "$report_path")

assert_valid_json "PERSIST: output is valid JSON" "$report_json"
assert_field "PERSIST: schema_version=1" "$report_json" ".schema_version" "1"
assert_field "PERSIST: meta.run_id" "$report_json" ".meta.run_id" "20260310T120000Z"
assert_field "PERSIST: plan.total" "$report_json" ".plan.total" "3"
assert_field "PERSIST: results count" "$report_json" ".results | length" "3"
assert_field "PERSIST: scoring.total" "$report_json" ".scoring.total" "45"
assert_field "PERSIST: scoring has by_category" "$report_json" ".scoring.by_category.secrets" "0"
assert_field "PERSIST: reliability" "$report_json" ".reliability" "1"
assert_field "PERSIST: reliability_details.planned" "$report_json" ".reliability_details.planned" "3"
assert_field "PERSIST: reliability_details.assessed" "$report_json" ".reliability_details.assessed" "3"
assert_field "PERSIST: verdict" "$report_json" ".verdict" "FAIL"
assert_field "PERSIST: verdict_reasons count" "$report_json" ".verdict_reasons | length" "1"

# PERSIST: atomic write — file named after run_id
expected_path="$TMPDIR_REPORTS/20260310T120000Z.json"
assert_eq "PERSIST: file path matches run_id" "$expected_path" "$report_path"

# PERSIST: file permissions 600
perms=$(stat -f "%OLp" "$report_path" 2>/dev/null || stat -c "%a" "$report_path" 2>/dev/null)
assert_eq "PERSIST: file permissions 600" "600" "$perms"

rm -rf "$TMPDIR_REPORTS"

# ---------------------------------------------------------------------------
# RENDER terminal tests
# ---------------------------------------------------------------------------

PASS_SCORING='{"total":85,"by_category":{"secrets":100,"hooks":90,"config":70},"reliability":1,"reliability_details":{"planned":3,"assessed":3,"errors":[]},"verdict":"PASS","verdict_reasons":["all gates passed"]}'
PASS_RESULTS='[
  {"check_id":"secrets-env","title":"Plaintext Secrets","category":"secrets","status":"PASS","finding_id":"aabbccddeeff","fingerprint_version":1,"duration_ms":50},
  {"check_id":"hooks-verify","title":"Hook Verification","category":"hooks","status":"PASS","finding_id":"112233445566","fingerprint_version":1,"duration_ms":30},
  {"check_id":"config-perms","title":"Config Permissions","category":"config","status":"PASS","finding_id":"aabbcc001122","fingerprint_version":1,"duration_ms":20}
]'
TMPDIR_PASS="$(mktemp -d)"
pass_path=$(. "$REPORTER" && reporter_persist "$META_JSON" "$PLAN_JSON" "$PASS_RESULTS" "$PASS_SCORING" "$TMPDIR_PASS")
pass_report=$(cat "$pass_path")

# RENDER: terminal scorecard contains category names, scores, verdict
render_out=$(. "$REPORTER" && reporter_render_terminal_with_path "$pass_report" "false" "$pass_path")

assert_contains "RENDER: contains 'secrets'" "secrets" "$render_out"
assert_contains "RENDER: contains 'hooks'" "hooks" "$render_out"
assert_contains "RENDER: contains 'config'" "config" "$render_out"
assert_contains "RENDER: contains total score" "85" "$render_out"
assert_contains "RENDER: contains verdict PASS" "PASS" "$render_out"
assert_contains "RENDER: contains score bar chars" "█" "$render_out"
assert_contains "RENDER: contains report path in footer" "$pass_path" "$render_out"

# RENDER: --no-color omits ANSI escape codes
render_no_color=$(. "$REPORTER" && reporter_render_terminal "$pass_report" "true")
assert_not_contains "RENDER: no-color omits ANSI ESC" "$(printf '\033')" "$render_no_color"
assert_contains "RENDER: no-color still has verdict" "PASS" "$render_no_color"
assert_contains "RENDER: no-color still has score" "85" "$render_no_color"

rm -rf "$TMPDIR_PASS"

# RENDER: FAIL report — critical findings listed
FAIL_SCORING='{"total":20,"by_category":{"secrets":0,"hooks":50},"reliability":1,"reliability_details":{"planned":2,"assessed":2,"errors":[]},"verdict":"FAIL","verdict_reasons":["critical or high severity FAIL exists"]}'
FAIL_RESULTS='[
  {"check_id":"secrets-env","title":"Plaintext Secrets in Env","category":"secrets","status":"FAIL","severity":"critical","finding_id":"aabbccddeeff","fingerprint_version":1,"duration_ms":50},
  {"check_id":"secrets-git","title":"Secrets in Git History","category":"secrets","status":"FAIL","severity":"high","finding_id":"112233aabbcc","fingerprint_version":1,"duration_ms":40},
  {"check_id":"secrets-cfg","title":"Secrets in Config Files","category":"secrets","status":"FAIL","severity":"high","finding_id":"223344bbccdd","fingerprint_version":1,"duration_ms":35},
  {"check_id":"secrets-log","title":"Secrets in Logs","category":"secrets","status":"FAIL","severity":"medium","finding_id":"334455ccddee","fingerprint_version":1,"duration_ms":25},
  {"check_id":"secrets-net","title":"Secrets in Network Calls","category":"secrets","status":"FAIL","severity":"low","finding_id":"445566ddeeff","fingerprint_version":1,"duration_ms":20},
  {"check_id":"hooks-bypass","title":"Hook Bypass Possible","category":"hooks","status":"FAIL","severity":"high","finding_id":"556677eeffaa","fingerprint_version":1,"duration_ms":30}
]'
FAIL_PLAN='{"total":6,"executed":6,"skipped":0,"excluded":[]}'
TMPDIR_FAIL="$(mktemp -d)"
fail_path=$(. "$REPORTER" && reporter_persist "$META_JSON" "$FAIL_PLAN" "$FAIL_RESULTS" "$FAIL_SCORING" "$TMPDIR_FAIL")
fail_report=$(cat "$fail_path")

render_fail=$(. "$REPORTER" && reporter_render_terminal "$fail_report" "true")

# Should show at most 5 critical findings
assert_contains "RENDER: shows critical finding title" "Plaintext Secrets in Env" "$render_fail"
assert_contains "RENDER: shows +N more for 6 failures" "+1 more" "$render_fail"

# RENDER: footer shows next action
assert_contains "RENDER: footer has next action" "sentinel" "$render_fail"

rm -rf "$TMPDIR_FAIL"

# ---------------------------------------------------------------------------
# RENDER markdown tests
# ---------------------------------------------------------------------------

TMPDIR_MD="$(mktemp -d)"
MD_OUT="$TMPDIR_MD/report.md"
TMPDIR_MD_REPORTS="$(mktemp -d)"
md_rpt_path=$(. "$REPORTER" && reporter_persist "$META_JSON" "$PLAN_JSON" "$RESULTS_JSON" "$SCORING_JSON" "$TMPDIR_MD_REPORTS")
md_report=$(cat "$md_rpt_path")

. "$REPORTER" && reporter_render_markdown "$md_report" "$MD_OUT"
md_content=$(cat "$MD_OUT")

assert_contains "RENDER MD: has H1 heading" "# Sentinel Security Audit" "$md_content"
assert_contains "RENDER MD: has verdict" "FAIL" "$md_content"
assert_contains "RENDER MD: has score" "45" "$md_content"
assert_contains "RENDER MD: has category table" "secrets" "$md_content"

rm -rf "$TMPDIR_MD" "$TMPDIR_MD_REPORTS"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
