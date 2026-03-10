#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORER="$SCRIPT_DIR/../../src/lib/scorer.sh"
passed=0; failed=0

assert_field() {
  name="$1"; json="$2"; field="$3"; expected="$4"
  actual=$(printf '%s' "$json" | jq -r "$field")
  if [ "$actual" = "$expected" ]; then passed=$((passed + 1))
  else printf 'FAIL: %s — %s: expected "%s", got "%s"\n' "$name" "$field" "$expected" "$actual"; failed=$((failed + 1)); fi
}

# --- NORMALIZE tests ---
RESULT='{"check_id":"secrets-env-plaintext","title":"test","category":"secrets","status":"FAIL","severity":"critical","evidence":[{"type":"file","path":"/tmp/a","detail":"found"}]}'
normalized=$(. "$SCORER" && scorer_normalize "$RESULT" 42)
assert_field "normalize adds finding_id" "$normalized" ".finding_id" "$(printf '%s' 'secrets-env-plaintext|secrets|/tmp/a' | shasum -a 256 2>/dev/null | cut -c1-12 || printf '%s' 'secrets-env-plaintext|secrets|/tmp/a' | sha256sum | cut -c1-12)"
assert_field "normalize adds fingerprint_version" "$normalized" ".fingerprint_version" "1"
assert_field "normalize adds duration_ms" "$normalized" ".duration_ms" "42"

# finding_id stability: same input twice → same hash
normalized2=$(. "$SCORER" && scorer_normalize "$RESULT" 99)
fid1=$(printf '%s' "$normalized" | jq -r '.finding_id')
fid2=$(printf '%s' "$normalized2" | jq -r '.finding_id')
if [ "$fid1" = "$fid2" ]; then passed=$((passed + 1)); else printf 'FAIL: finding_id not stable\n'; failed=$((failed + 1)); fi

# finding_id excludes status: change FAIL→WARN, same ID
RESULT_WARN=$(printf '%s' "$RESULT" | jq '.status="WARN"')
normalized_warn=$(. "$SCORER" && scorer_normalize "$RESULT_WARN" 42)
fid3=$(printf '%s' "$normalized_warn" | jq -r '.finding_id')
if [ "$fid1" = "$fid3" ]; then passed=$((passed + 1)); else printf 'FAIL: finding_id changed with status\n'; failed=$((failed + 1)); fi

# --- ASSESS tests ---
RESULTS_JSON='[
  {"check_id":"a","category":"secrets","status":"PASS","weight":10},
  {"check_id":"b","category":"secrets","status":"FAIL","severity":"critical","weight":10},
  {"check_id":"c","category":"config","status":"PASS","weight":5}
]'
assessed=$(. "$SCORER" && scorer_assess "$RESULTS_JSON" 3)

# secrets: (10*100 + 10*0) / (10+10) = 50.0
assert_field "secrets category score" "$assessed" '.by_category.secrets' "50"
# config: (5*100) / 5 = 100.0
assert_field "config category score" "$assessed" '.by_category.config' "100"
# reliability = assessed/planned = 3/3 = 1.0
assert_field "reliability" "$assessed" '.reliability' "1"
# verdict: FAIL (critical FAIL exists)
assert_field "verdict FAIL on critical" "$assessed" '.verdict' "FAIL"

# verdict: UNRELIABLE when reliability < 0.7
assessed_unrel=$(. "$SCORER" && scorer_assess "$RESULTS_JSON" 10)
assert_field "verdict UNRELIABLE" "$assessed_unrel" '.verdict' "UNRELIABLE"

# verdict: PASS when all pass and score >= 80
RESULTS_PASS='[{"check_id":"a","category":"secrets","status":"PASS","weight":10},{"check_id":"b","category":"config","status":"PASS","weight":5}]'
assessed_pass=$(. "$SCORER" && scorer_assess "$RESULTS_PASS" 2)
assert_field "verdict PASS" "$assessed_pass" '.verdict' "PASS"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
