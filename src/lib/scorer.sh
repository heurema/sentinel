#!/usr/bin/env sh
# scorer.sh — NORMALIZE and ASSESS stages for sentinel scoring pipeline
# Usage: . "$SENTINEL_LIB/scorer.sh"

# sha256_hash <string> — portable SHA-256, first 12 hex chars.
# Defined inline to avoid path resolution issues when sourced from arbitrary locations.
# If emit.sh was already sourced, this redefines identically (no harm).
sha256_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-12
  else
    printf '%s' "$1" | shasum -a 256 | cut -c1-12
  fi
}

# ---------------------------------------------------------------------------
# scorer_normalize <result_json> <duration_ms>
# Augments a single check result with:
#   - finding_id: sha256(check_id|category|sorted_evidence_paths)[0:12]
#   - fingerprint_version: 1
#   - duration_ms: from argument
# Status is NOT included in the hash so findings keep identity across status changes.
# ---------------------------------------------------------------------------
scorer_normalize() {
  _sn_result="$1"
  _sn_duration="$2"

  _sn_check_id=$(printf '%s' "$_sn_result" | jq -r '.check_id')
  _sn_category=$(printf '%s' "$_sn_result" | jq -r '.category')

  # Extract evidence paths, sort alphabetically, join with |
  _sn_paths=$(printf '%s' "$_sn_result" | jq -r '[.evidence[]? | select(.path != null) | .path] | sort | join("|")')

  # Build hash basis: check_id|category|sorted_paths
  _sn_basis="${_sn_check_id}|${_sn_category}|${_sn_paths}"
  _sn_finding_id=$(sha256_hash "$_sn_basis")

  # Augment the result JSON
  printf '%s' "$_sn_result" | jq \
    --arg fid "$_sn_finding_id" \
    --argjson dur "$_sn_duration" \
    '. + {finding_id: $fid, fingerprint_version: 1, duration_ms: $dur}'
}

# ---------------------------------------------------------------------------
# scorer_assess <results_json_array> <planned_count>
# Computes per-category scores, total score, reliability, and verdict.
#
# Status scores: PASS=100, WARN=50, FAIL=0
# Excluded from scoring: ERROR, SKIP, UNSUPPORTED
# Category weights: secrets=1.5, trust=1.5, hooks=1.2, mcp=1.0, plugins=1.0, config=1.0
#
# Verdict gates (first match wins):
#   ABORTED     — planned=0 or all checks excluded
#   UNRELIABLE  — reliability < 0.7
#   FAIL        — any critical/high FAIL exists, OR total score < 50
#   WARN        — total score < 80, OR any medium FAIL exists
#   PASS        — default
#
# Output JSON: {total, by_category, reliability, reliability_details, verdict, verdict_reasons}
# ---------------------------------------------------------------------------
scorer_assess() {
  _sa_results="$1"
  _sa_planned="$2"

  # Use jq to do the heavy lifting for scoring computation
  jq -n \
    --argjson results "$_sa_results" \
    --argjson planned "$_sa_planned" \
    '
    # Category weights
    def cat_weight(c):
      if c == "secrets" then 1.5
      elif c == "trust" then 1.5
      elif c == "hooks" then 1.2
      elif c == "mcp" then 1.0
      elif c == "plugins" then 1.0
      elif c == "config" then 1.0
      else 1.0
      end;

    # Status score (null = excluded from scoring)
    def status_score(s):
      if s == "PASS" then 100
      elif s == "WARN" then 50
      elif s == "FAIL" then 0
      else null
      end;

    # Scoreable checks (not ERROR/SKIP/UNSUPPORTED)
    def is_scoreable(r):
      r.status != "ERROR" and r.status != "SKIP" and r.status != "UNSUPPORTED";

    # Assessed count
    ($results | map(select(is_scoreable(.))) | length) as $assessed |

    # Reliability
    (if $planned == 0 then 0 else ($assessed / $planned) end) as $reliability |

    # Error list for reliability_details
    ($results | map(select(.status == "ERROR") | .check_id)) as $errors |

    # Per-category scores
    (
      $results
      | map(select(is_scoreable(.)))
      | group_by(.category)
      | map(
          {
            cat: .[0].category,
            score: (
              (map(((.weight // 1) * status_score(.status))) | add // 0) /
              (map((.weight // 1)) | add // 1)
            )
          }
        )
      | map({(.cat): (.score | round)})
      | add // {}
    ) as $by_category |

    # Total score: weighted average of category scores using category weights
    (
      if ($by_category | length) == 0 then 0
      else
        (
          $by_category | to_entries |
          map(.value * cat_weight(.key)) | add
        ) /
        (
          $by_category | to_entries |
          map(cat_weight(.key)) | add
        )
      end
    ) as $total |

    # Verdict gates
    (
      # Check for critical/high FAILs
      ($results | map(select(.status == "FAIL" and (.severity == "critical" or .severity == "high"))) | length > 0) as $has_critical_fail |

      # Check for medium FAILs
      ($results | map(select(.status == "FAIL" and .severity == "medium")) | length > 0) as $has_medium_fail |

      # All checks excluded?
      ($assessed == 0 and $planned > 0) as $all_excluded |

      if $planned == 0 or $all_excluded then
        {verdict: "ABORTED", reasons: ["planned=0 or all checks excluded"]}
      elif $reliability < 0.7 then
        {verdict: "UNRELIABLE", reasons: [("reliability \($reliability | . * 100 | round / 100) < 0.7 (\($assessed)/\($planned) assessed)")]}
      elif $has_critical_fail then
        {verdict: "FAIL", reasons: ["critical or high severity FAIL exists"]}
      elif $total < 50 then
        {verdict: "FAIL", reasons: [("total score \($total | round) < 50")]}
      elif $total < 80 then
        {verdict: "WARN", reasons: [("total score \($total | round) < 80")]}
      elif $has_medium_fail then
        {verdict: "WARN", reasons: ["medium severity FAIL exists"]}
      else
        {verdict: "PASS", reasons: ["all gates passed"]}
      end
    ) as $gate |

    {
      total: ($total | round),
      by_category: $by_category,
      reliability: $reliability,
      reliability_details: {
        planned: $planned,
        assessed: $assessed,
        errors: $errors
      },
      verdict: $gate.verdict,
      verdict_reasons: $gate.reasons
    }
    '
}
