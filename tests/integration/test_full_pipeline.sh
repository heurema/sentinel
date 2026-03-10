#!/usr/bin/env sh
# Integration test: full sentinel pipeline end-to-end
# Exercises runner → scorer → reporter with a known-bad project fixture.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

passed=0; failed=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
# Setup: temporary project with planted security issues
# ---------------------------------------------------------------------------

TEMP_DIR=$(mktemp -d)
REPORT_DIR=$(mktemp -d)
FAKE_HOME=$(mktemp -d)

# Clean up on exit
trap 'rm -rf "$TEMP_DIR" "$REPORT_DIR" "$FAKE_HOME"' EXIT INT TERM

# 1. Plaintext .env with API key
printf 'ANTHROPIC_API_KEY=sk-ant-test123456789\nDB_HOST=localhost\n' > "$TEMP_DIR/.env"

# 2. No .claudeignore (deliberately absent)

# 3. .claude/settings.json with no PreToolUse hooks
mkdir -p "$TEMP_DIR/.claude"
printf '{"hooks":{}}\n' > "$TEMP_DIR/.claude/settings.json"

# 4. .mcp.json with plaintext credentials
printf '{"mcpServers":{"myserver":{"command":"npx","args":["server"],"env":{"API_KEY":"sk-test-plaintext-credential-abc123"}}}}\n' \
  > "$TEMP_DIR/.mcp.json"

# Fake SENTINEL_CLAUDE_HOME (no global settings.json there)
mkdir -p "$FAKE_HOME/.claude"

# ---------------------------------------------------------------------------
# Integration registry: only the 4 checks we care about
# ---------------------------------------------------------------------------

INT_REGISTRY=$(jq -n '
[
  {"id":"secrets-env-plaintext","file":"secrets/env-plaintext.sh","category":"secrets","severity_default":"critical","weight":10,"timeout_ms":10000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true},
  {"id":"trust-no-claudeignore","file":"trust/no-claudeignore.sh","category":"trust","severity_default":"medium","weight":5,"timeout_ms":10000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true},
  {"id":"hooks-no-pretooluse","file":"hooks/no-pretooluse.sh","category":"hooks","severity_default":"critical","weight":10,"timeout_ms":10000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true},
  {"id":"mcp-plaintext-creds","file":"mcp/plaintext-creds.sh","category":"mcp","severity_default":"critical","weight":10,"timeout_ms":10000,"optional":false,"platforms":["darwin","linux"],"default_enabled":true}
]')

INT_CONFIG='{"disabled_checks":[],"disabled_categories":[],"ignore_paths":[],"check_timeout_ms":10000,"report_retention_days":90}'

# Write registry to temp file so runner_load can read it
INT_REGISTRY_FILE="$TEMP_DIR/int-registry.json"
printf '%s\n' "$INT_REGISTRY" > "$INT_REGISTRY_FILE"
INT_CONFIG_FILE="$TEMP_DIR/int-config.json"
printf '%s\n' "$INT_CONFIG" > "$INT_CONFIG_FILE"

# ---------------------------------------------------------------------------
# run_pipeline <temp_dir> <fake_home>
# Runs the full LOAD→VALIDATE→PLAN→RUN→NORMALIZE→ASSESS→PERSIST pipeline.
# Prints the report JSON to stdout.
# ---------------------------------------------------------------------------
run_pipeline() {
  _rp_project_dir="$1"
  _rp_fake_home="$2"

  (
    . "$PLUGIN_ROOT/src/lib/emit.sh"
    . "$PLUGIN_ROOT/src/lib/runner.sh"
    . "$PLUGIN_ROOT/src/lib/scorer.sh"
    . "$PLUGIN_ROOT/src/lib/reporter.sh"

    # LOAD
    runner_load "$INT_REGISTRY_FILE" "$INT_CONFIG_FILE"

    # VALIDATE (non-fatal warnings to stderr; real scripts exist)
    runner_validate "$_RUNNER_REGISTRY" "$_RUNNER_CONFIG" "$PLUGIN_ROOT/src/checks" 2>/dev/null || true

    # PLAN
    PLAN=$(runner_plan "$_RUNNER_REGISTRY" "$_RUNNER_CONFIG" "darwin")
    PLANNED=$(printf '%s' "$PLAN" | jq -c '.planned')
    PLANNED_COUNT=$(printf '%s' "$PLANNED" | jq 'length')

    # RUN (inject env vars so checks find the planted issues)
    # runner_run outputs a sequence of JSON objects (one per check, may be pretty-printed).
    # Use jq -sc "." to collect the entire sequence into a compact JSON array.
    PLAN_OBJ=$(jq -n --argjson p "$PLANNED" '{"planned": $p, "excluded": []}')
    RAW_ARRAY=$(
      SENTINEL_PROJECT_DIR="$_rp_project_dir" \
      SENTINEL_PLATFORM="darwin" \
      SENTINEL_SETTINGS_FILE="$_rp_fake_home/.claude/settings.json" \
      SENTINEL_CLAUDE_HOME="$_rp_fake_home/.claude" \
      runner_run "$PLAN_OBJ" "$PLUGIN_ROOT/src/checks" "" | jq -sc "."
    )

    # NORMALIZE each result: iterate over array indices
    RESULTS_ARRAY='[]'
    _raw_count=$(printf '%s' "$RAW_ARRAY" | jq 'length')
    _raw_i=0
    while [ "$_raw_i" -lt "$_raw_count" ]; do
      _entry=$(printf '%s' "$RAW_ARRAY" | jq -c ".[$_raw_i]")
      _norm=$(scorer_normalize "$_entry" 0)
      RESULTS_ARRAY=$(printf '%s' "$RESULTS_ARRAY" | jq --argjson r "$_norm" '. + [$r]')
      _raw_i=$((_raw_i + 1))
    done

    # ASSESS
    SCORING=$(scorer_assess "$RESULTS_ARRAY" "$PLANNED_COUNT")

    # Build meta
    RUN_ID="integration-test-$(date +%Y%m%dT%H%M%SZ)"
    META=$(jq -n \
      --arg rid "$RUN_ID" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg host "$(hostname 2>/dev/null || printf 'unknown')" \
      --arg proj "$_rp_project_dir" \
      '{run_id:$rid, completed_at:$ts, sentinel_version:"0.1.0", registry_hash:"integration", scoring_version:1, platform:"darwin", hostname:$host, scan_roots:[$proj], effective_config:{}, config_sources:[]}')

    PLAN_SUMMARY=$(jq -n \
      --argjson pc "$PLANNED_COUNT" \
      --argjson full "$PLAN" \
      '{"total":$pc, "executed":$pc, "skipped":0, "excluded":($full.excluded // [])}')

    # PERSIST + emit path, then print report JSON
    report_path=$(reporter_persist "$META" "$PLAN_SUMMARY" "$RESULTS_ARRAY" "$SCORING" "$REPORT_DIR")
    cat "$report_path"
  )
}

# ---------------------------------------------------------------------------
# Run 1
# ---------------------------------------------------------------------------

REPORT1=$(run_pipeline "$TEMP_DIR" "$FAKE_HOME")

# ---------------------------------------------------------------------------
# Validate top-level structure
# ---------------------------------------------------------------------------

assert_field "schema_version=1" "$REPORT1" ".schema_version" "1"

for _f in schema_version meta plan results scoring reliability reliability_details verdict verdict_reasons; do
  _val=$(printf '%s' "$REPORT1" | jq -r --arg f "$_f" 'has($f)')
  assert_eq "has top-level field: $_f" "true" "$_val"
done

# ---------------------------------------------------------------------------
# Validate results
# ---------------------------------------------------------------------------

RESULTS_LEN=$(printf '%s' "$REPORT1" | jq '.results | length')
if [ "$RESULTS_LEN" -gt 0 ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: results array is empty\n'
  failed=$((failed + 1))
fi

# Expected check IDs must appear in results
for _cid in secrets-env-plaintext trust-no-claudeignore hooks-no-pretooluse; do
  _found=$(printf '%s' "$REPORT1" | jq -r --arg c "$_cid" '[.results[] | select(.check_id == $c)] | length')
  if [ "$_found" -gt 0 ]; then
    passed=$((passed + 1))
  else
    printf 'FAIL: check_id "%s" not found in results\n' "$_cid"
    failed=$((failed + 1))
  fi
done

# ---------------------------------------------------------------------------
# Validate scoring and verdict
# ---------------------------------------------------------------------------

TOTAL_SCORE=$(printf '%s' "$REPORT1" | jq -r '.scoring.total')
if [ "$TOTAL_SCORE" -lt 60 ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: score should be < 60 for planted issues, got %s\n' "$TOTAL_SCORE"
  failed=$((failed + 1))
fi

assert_field "verdict is FAIL" "$REPORT1" ".verdict" "FAIL"

# ---------------------------------------------------------------------------
# Validate finding_id format (12 hex chars)
# ---------------------------------------------------------------------------

FINDING_COUNT=$(printf '%s' "$REPORT1" | jq '[.results[] | select(.finding_id != null)] | length')
if [ "$FINDING_COUNT" -gt 0 ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: no finding_id fields found in results\n'
  failed=$((failed + 1))
fi

# All finding_ids match ^[0-9a-f]{12}$
BAD_IDS=$(printf '%s' "$REPORT1" | jq -r '[.results[] | select(.finding_id != null) | .finding_id | select(test("^[0-9a-f]{12}$") | not)] | join(",")')
assert_eq "all finding_ids match ^[0-9a-f]{12}$" "" "$BAD_IDS"

# ---------------------------------------------------------------------------
# Finding_id stability: run again, verify byte-for-byte identical IDs
# ---------------------------------------------------------------------------

REPORT2=$(run_pipeline "$TEMP_DIR" "$FAKE_HOME")

# Collect finding_ids from both runs (sorted by check_id for stable comparison)
FIDS1=$(printf '%s' "$REPORT1" | jq -r '[.results[] | {check_id, finding_id}] | sort_by(.check_id) | .[] | .finding_id')
FIDS2=$(printf '%s' "$REPORT2" | jq -r '[.results[] | {check_id, finding_id}] | sort_by(.check_id) | .[] | .finding_id')

if [ "$FIDS1" = "$FIDS2" ]; then
  passed=$((passed + 1))
else
  printf 'FAIL: finding_ids differ between run 1 and run 2\n'
  printf '  run1: %s\n' "$FIDS1"
  printf '  run2: %s\n' "$FIDS2"
  failed=$((failed + 1))
fi

# Also confirm result count is stable between runs
COUNT1=$(printf '%s' "$REPORT1" | jq '.results | length')
COUNT2=$(printf '%s' "$REPORT2" | jq '.results | length')
assert_eq "result count stable across runs" "$COUNT1" "$COUNT2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
