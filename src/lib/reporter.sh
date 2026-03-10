#!/usr/bin/env sh
# reporter.sh — PERSIST and RENDER stages for sentinel
# Usage: . "$SENTINEL_LIB/reporter.sh"

# ---------------------------------------------------------------------------
# reporter_persist <meta_json> <plan_json> <results_json> <scoring_json> <report_dir>
# Assembles full report JSON and atomically writes it to <report_dir>/<run_id>.json.
# Permissions set to 600. Prints the written file path on stdout.
# ---------------------------------------------------------------------------
reporter_persist() {
  _rp_meta="$1"
  _rp_plan="$2"
  _rp_results="$3"
  _rp_scoring="$4"
  _rp_dir="$5"

  _rp_run_id=$(printf '%s' "$_rp_meta" | jq -r '.run_id')
  _rp_out="$_rp_dir/${_rp_run_id}.json"
  _rp_tmp="${_rp_out}.tmp.$$"

  jq -n \
    --argjson meta    "$_rp_meta" \
    --argjson plan    "$_rp_plan" \
    --argjson results "$_rp_results" \
    --argjson scoring "$_rp_scoring" \
    '{
      schema_version: 1,
      meta:     $meta,
      plan:     $plan,
      results:  $results,
      scoring: {
        total:       $scoring.total,
        by_category: $scoring.by_category
      },
      reliability:         $scoring.reliability,
      reliability_details: $scoring.reliability_details,
      verdict:             $scoring.verdict,
      verdict_reasons:     $scoring.verdict_reasons
    }' > "$_rp_tmp"

  chmod 600 "$_rp_tmp"
  mv "$_rp_tmp" "$_rp_out"
  printf '%s' "$_rp_out"
}

# ---------------------------------------------------------------------------
# _reporter_color <verdict> <no_color>
# Emits the ANSI color code for a verdict (or empty string when no_color=true).
# ---------------------------------------------------------------------------
_reporter_color() {
  _rc_verdict="$1"
  _rc_no_color="$2"

  # Also honour NO_COLOR env var (https://no-color.org/)
  if [ "$_rc_no_color" = "true" ] || [ "${NO_COLOR:-}" != "" ]; then
    return 0
  fi

  case "$_rc_verdict" in
    PASS)  printf '\033[32m' ;;
    WARN)  printf '\033[33m' ;;
    FAIL)  printf '\033[31m' ;;
    *)     printf '\033[33m' ;;
  esac
}

_reporter_reset() {
  _rreset_no_color="$1"
  if [ "$_rreset_no_color" = "true" ] || [ "${NO_COLOR:-}" != "" ]; then
    return 0
  fi
  printf '\033[0m'
}

# ---------------------------------------------------------------------------
# _reporter_bar <score> <width>
# Renders a score bar like: ████████░░  (width chars, filled proportion = score/100)
# ---------------------------------------------------------------------------
_reporter_bar() {
  _rb_score="$1"
  _rb_width="${2:-10}"
  _rb_filled=$(( _rb_score * _rb_width / 100 ))
  _rb_empty=$(( _rb_width - _rb_filled ))

  i=0
  while [ "$i" -lt "$_rb_filled" ]; do
    printf '█'
    i=$(( i + 1 ))
  done
  i=0
  while [ "$i" -lt "$_rb_empty" ]; do
    printf '░'
    i=$(( i + 1 ))
  done
}

# ---------------------------------------------------------------------------
# reporter_render_terminal <report_json> <no_color>
# Renders a human-readable scorecard to stdout.
# no_color: "true" to suppress ANSI escape codes (also honours $NO_COLOR env).
# ---------------------------------------------------------------------------
reporter_render_terminal() {
  _rt_report="$1"
  _rt_nc="${2:-false}"

  _rt_verdict=$(printf '%s' "$_rt_report"   | jq -r '.verdict')
  _rt_total=$(printf '%s' "$_rt_report"     | jq -r '.scoring.total')
  _rt_reliability=$(printf '%s' "$_rt_report" | jq -r '.reliability')
  _rt_run_id=$(printf '%s' "$_rt_report"    | jq -r '.meta.run_id')
  _rt_report_path=""  # will be set by caller context; we use run_id for footer

  # Determine report file path from meta (we need the dir; fall back to run_id only)
  # The persist function writes to <report_dir>/<run_id>.json — we don't store the dir
  # in the JSON, but we can reconstruct from run_id when we have the path passed in.
  # Since render_terminal receives the JSON (not path), we embed path via a jq field
  # if present, else use run_id as identifier.
  _rt_report_file=$(printf '%s' "$_rt_report" | jq -r '.meta.report_path // empty')
  if [ -z "$_rt_report_file" ]; then
    _rt_report_file="<run_id: ${_rt_run_id}>"
  fi

  _rt_col=$(_reporter_color "$_rt_verdict" "$_rt_nc")
  _rt_rst=$(_reporter_reset "$_rt_nc")

  # Header
  printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf 'Sentinel Security Audit  %s%s%s\n' "$_rt_col" "$_rt_verdict" "$_rt_rst"
  printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Total score bar
  printf 'Score  '
  _reporter_bar "$_rt_total" 10
  printf '  %s/100\n' "$_rt_total"
  printf 'Reliability  %.0f%%\n' "$(printf '%s' "$_rt_reliability" | awk '{printf "%.0f", $1 * 100}')"
  printf '\n'

  # Category breakdown
  printf 'By category:\n'
  printf '%s' "$_rt_report" | jq -r '.scoring.by_category | to_entries[] | "\(.key) \(.value)"' | \
  while IFS=' ' read -r _cat _score; do
    _bar=$(_reporter_bar "$_score" 8)
    printf '  %-12s %s %3d\n' "$_cat" "$_bar" "$_score"
  done
  printf '\n'

  # Critical findings (max 5, with "+N more" if there are more)
  _rt_fail_count=$(printf '%s' "$_rt_report" | jq '[.results[] | select(.status == "FAIL")] | length')
  if [ "$_rt_fail_count" -gt 0 ]; then
    printf 'Findings (FAIL):\n'
    _rt_shown=0
    _rt_max=5
    printf '%s' "$_rt_report" | jq -r '[.results[] | select(.status == "FAIL")] | .[] | "\(.severity // "unknown") \(.title)"' | \
    while IFS= read -r _line; do
      if [ "$_rt_shown" -lt "$_rt_max" ]; then
        printf '  [%s] %s\n' "$(printf '%s' "$_line" | cut -d' ' -f1)" "$(printf '%s' "$_line" | cut -d' ' -f2-)"
        _rt_shown=$(( _rt_shown + 1 ))
      fi
    done
    if [ "$_rt_fail_count" -gt "$_rt_max" ]; then
      _rt_more=$(( _rt_fail_count - _rt_max ))
      printf '  +%d more\n' "$_rt_more"
    fi
    printf '\n'
  fi

  # Footer
  printf '%s\n' "──────────────────────────────────────────"
  printf 'Report: %s\n' "$_rt_report_file"
  printf 'Next:   sentinel report --open %s\n' "$_rt_run_id"
}

# ---------------------------------------------------------------------------
# reporter_render_terminal_with_path <report_json> <no_color> <report_path>
# Same as reporter_render_terminal but accepts a file path for the footer.
# ---------------------------------------------------------------------------
reporter_render_terminal_with_path() {
  _rtwp_report="$1"
  _rtwp_nc="${2:-false}"
  _rtwp_path="$3"

  # Inject path into report JSON for render_terminal to pick up
  _rtwp_injected=$(printf '%s' "$_rtwp_report" | jq --arg p "$_rtwp_path" '.meta.report_path = $p')
  reporter_render_terminal "$_rtwp_injected" "$_rtwp_nc"
}

# ---------------------------------------------------------------------------
# reporter_render_markdown <report_json> <output_path>
# Renders a markdown report to output_path.
# ---------------------------------------------------------------------------
reporter_render_markdown() {
  _rm_report="$1"
  _rm_out="$2"

  _rm_verdict=$(printf '%s' "$_rm_report"     | jq -r '.verdict')
  _rm_total=$(printf '%s' "$_rm_report"       | jq -r '.scoring.total')
  _rm_reliability=$(printf '%s' "$_rm_report" | jq -r '.reliability')
  _rm_run_id=$(printf '%s' "$_rm_report"      | jq -r '.meta.run_id')
  _rm_completed=$(printf '%s' "$_rm_report"   | jq -r '.meta.completed_at')
  _rm_hostname=$(printf '%s' "$_rm_report"    | jq -r '.meta.hostname')

  {
    printf '# Sentinel Security Audit\n\n'
    printf '## Summary\n\n'
    printf '| Field | Value |\n'
    printf '|-------|-------|\n'
    printf '| Run ID | `%s` |\n' "$_rm_run_id"
    printf '| Completed | %s |\n' "$_rm_completed"
    printf '| Host | %s |\n' "$_rm_hostname"
    printf '| **Verdict** | **%s** |\n' "$_rm_verdict"
    printf '| Score | %s/100 |\n' "$_rm_total"
    printf '| Reliability | %.0f%% |\n' "$(printf '%s' "$_rm_reliability" | awk '{printf "%.0f", $1 * 100}')"
    printf '\n'

    printf '## Category Scores\n\n'
    printf '| Category | Score |\n'
    printf '|----------|-------|\n'
    printf '%s' "$_rm_report" | jq -r '.scoring.by_category | to_entries[] | "| \(.key) | \(.value)/100 |"'
    printf '\n'

    printf '## Findings\n\n'
    _rm_fail_count=$(printf '%s' "$_rm_report" | jq '[.results[] | select(.status == "FAIL")] | length')
    if [ "$_rm_fail_count" -eq 0 ]; then
      printf 'No FAIL findings.\n\n'
    else
      printf '| Check | Category | Severity | Title |\n'
      printf '|-------|----------|----------|-------|\n'
      printf '%s' "$_rm_report" | jq -r '[.results[] | select(.status == "FAIL")] | .[] | "| `\(.check_id)` | \(.category) | \(.severity // "-") | \(.title) |"'
      printf '\n'
    fi

    printf '## Verdict Reasons\n\n'
    printf '%s' "$_rm_report" | jq -r '.verdict_reasons[] | "- \(.)"'
    printf '\n'
  } > "$_rm_out"
}
