#!/usr/bin/env sh
# runner.sh — LOAD / VALIDATE / PLAN / RUN pipeline engine for sentinel
# Usage: . "$SENTINEL_LIB/runner.sh"

# Global state set by runner_load
_RUNNER_REGISTRY=""
_RUNNER_CONFIG=""

# ---------------------------------------------------------------------------
# runner_load <registry_path> <config_path>
# Reads both files, validates JSON, stores in _RUNNER_REGISTRY / _RUNNER_CONFIG.
# Exit 4 if registry missing/invalid, exit 5 if config missing/invalid.
# ---------------------------------------------------------------------------
runner_load() {
  _rl_reg="$1"
  _rl_cfg="$2"

  if [ ! -f "$_rl_reg" ]; then
    printf 'runner_load: registry not found: %s\n' "$_rl_reg" >&2
    return 4
  fi

  _rl_reg_json=$(cat "$_rl_reg") || { printf 'runner_load: cannot read registry\n' >&2; return 4; }
  if ! printf '%s' "$_rl_reg_json" | jq . >/dev/null 2>&1; then
    printf 'runner_load: registry is not valid JSON\n' >&2
    return 4
  fi

  if [ ! -f "$_rl_cfg" ]; then
    printf 'runner_load: config not found: %s\n' "$_rl_cfg" >&2
    return 5
  fi

  _rl_cfg_json=$(cat "$_rl_cfg") || { printf 'runner_load: cannot read config\n' >&2; return 5; }
  if ! printf '%s' "$_rl_cfg_json" | jq . >/dev/null 2>&1; then
    printf 'runner_load: config is not valid JSON\n' >&2
    return 5
  fi

  _RUNNER_REGISTRY="$_rl_reg_json"
  _RUNNER_CONFIG="$_rl_cfg_json"
  return 0
}

# ---------------------------------------------------------------------------
# runner_validate <registry_json> <config_json> <checks_dir>
# Checks for duplicate IDs, verifies script existence + executable bit.
# Returns 0 on success; nonzero if duplicate IDs found.
# Emits warnings to stderr for missing/non-executable scripts (non-fatal).
# ---------------------------------------------------------------------------
runner_validate() {
  _rv_reg="$1"
  _rv_cfg="$2"
  _rv_dir="$3"

  # Check for duplicate IDs
  _rv_dup=$(printf '%s' "$_rv_reg" | jq -r '.[].id' | sort | uniq -d)
  if [ -n "$_rv_dup" ]; then
    printf 'runner_validate: duplicate check IDs found: %s\n' "$_rv_dup" >&2
    return 1
  fi

  # Verify script existence and executable bit — non-fatal warnings
  _rv_count=$(printf '%s' "$_rv_reg" | jq 'length')
  _rv_i=0
  while [ "$_rv_i" -lt "$_rv_count" ]; do
    _rv_entry=$(printf '%s' "$_rv_reg" | jq ".[$_rv_i]")
    _rv_id=$(printf '%s' "$_rv_entry" | jq -r '.id')
    _rv_file=$(printf '%s' "$_rv_entry" | jq -r '.file')
    _rv_path="$_rv_dir/$_rv_file"

    if [ ! -f "$_rv_path" ]; then
      printf 'runner_validate: WARNING: script not found for %s: %s\n' "$_rv_id" "$_rv_path" >&2
    elif [ ! -x "$_rv_path" ]; then
      printf 'runner_validate: WARNING: script not executable for %s: %s\n' "$_rv_id" "$_rv_path" >&2
    fi

    _rv_i=$((_rv_i + 1))
  done

  return 0
}

# ---------------------------------------------------------------------------
# runner_plan <registry_json> <config_json> <platform>
# Filters checks by: platform match, disabled_checks, disabled_categories,
# default_enabled. Outputs JSON: {"planned":[...], "excluded":[{"check_id","reason"}]}
# ---------------------------------------------------------------------------
runner_plan() {
  _rp_reg="$1"
  _rp_cfg="$2"
  _rp_platform="$3"

  _rp_disabled_checks=$(printf '%s' "$_rp_cfg" | jq -c '.disabled_checks // []')
  _rp_disabled_cats=$(printf '%s' "$_rp_cfg" | jq -c '.disabled_categories // []')

  _rp_planned='[]'
  _rp_excluded='[]'

  _rp_count=$(printf '%s' "$_rp_reg" | jq 'length')
  _rp_i=0
  while [ "$_rp_i" -lt "$_rp_count" ]; do
    _rp_entry=$(printf '%s' "$_rp_reg" | jq ".[$_rp_i]")
    _rp_id=$(printf '%s' "$_rp_entry" | jq -r '.id')
    _rp_cat=$(printf '%s' "$_rp_entry" | jq -r '.category')
    _rp_platforms=$(printf '%s' "$_rp_entry" | jq -c '.platforms // []')
    _rp_default_enabled=$(printf '%s' "$_rp_entry" | jq -r '.default_enabled')

    _rp_reason=""

    # Platform filter
    _rp_on_platform=$(printf '%s' "$_rp_platforms" | jq --arg p "$_rp_platform" 'map(select(. == $p)) | length')
    if [ "$_rp_on_platform" -eq 0 ]; then
      _rp_reason="platform not supported ($3)"
    fi

    # default_enabled filter
    if [ -z "$_rp_reason" ] && [ "$_rp_default_enabled" = "false" ]; then
      _rp_reason="default_enabled=false"
    fi

    # disabled_categories filter
    if [ -z "$_rp_reason" ]; then
      _rp_cat_disabled=$(printf '%s' "$_rp_disabled_cats" | jq --arg c "$_rp_cat" 'map(select(. == $c)) | length')
      if [ "$_rp_cat_disabled" -gt 0 ]; then
        _rp_reason="category disabled ($3)"
      fi
    fi

    # disabled_checks filter
    if [ -z "$_rp_reason" ]; then
      _rp_id_disabled=$(printf '%s' "$_rp_disabled_checks" | jq --arg id "$_rp_id" 'map(select(. == $id)) | length')
      if [ "$_rp_id_disabled" -gt 0 ]; then
        _rp_reason="disabled in config"
      fi
    fi

    if [ -n "$_rp_reason" ]; then
      _rp_excluded=$(printf '%s' "$_rp_excluded" | jq \
        --arg id "$_rp_id" --arg r "$_rp_reason" \
        '. + [{"check_id": $id, "reason": $r}]')
    else
      _rp_slim=$(printf '%s' "$_rp_entry" | jq \
        '{id: .id, file: .file, category: .category, severity_default: .severity_default, weight: .weight, timeout_ms: .timeout_ms}')
      _rp_planned=$(printf '%s' "$_rp_planned" | jq --argjson e "$_rp_slim" '. + [$e]')
    fi

    _rp_i=$((_rp_i + 1))
  done

  jq -n --argjson planned "$_rp_planned" --argjson excluded "$_rp_excluded" \
    '{"planned": $planned, "excluded": $excluded}'
}

# ---------------------------------------------------------------------------
# runner_run <plan_json> <checks_dir> <env_vars>
# Runs each planned check with timeout; captures stdout; validates JSON.
# Outputs JSONL (one result per line).
# Synthetic ERROR format: {"check_id","title","category","status":"ERROR","error_kind","evidence":[]}
# error_kind: "timeout" | "invalid_json" | "nonzero_exit" | "oversized_output"
# ---------------------------------------------------------------------------
runner_run() {
  _rr_plan="$1"
  _rr_dir="$2"
  # _rr_env="$3"  # reserved for future use

  _rr_count=$(printf '%s' "$_rr_plan" | jq '.planned | length')
  _rr_i=0

  while [ "$_rr_i" -lt "$_rr_count" ]; do
    _rr_entry=$(printf '%s' "$_rr_plan" | jq ".planned[$_rr_i]")
    _rr_id=$(printf '%s' "$_rr_entry" | jq -r '.id')
    _rr_file=$(printf '%s' "$_rr_entry" | jq -r '.file')
    _rr_cat=$(printf '%s' "$_rr_entry" | jq -r '.category')
    _rr_timeout_ms=$(printf '%s' "$_rr_entry" | jq -r '.timeout_ms')
    # Convert ms to seconds (ceiling, minimum 1)
    _rr_timeout_s=$(( (_rr_timeout_ms + 999) / 1000 ))
    [ "$_rr_timeout_s" -lt 1 ] && _rr_timeout_s=1

    _rr_script="$_rr_dir/$_rr_file"

    # Temp files for stdout and stderr
    _rr_tmp_out=$(mktemp)
    _rr_tmp_err=$(mktemp)

    _rr_error_kind=""
    _rr_exit_code=0

    # Run the check with timeout
    if command -v timeout >/dev/null 2>&1; then
      # GNU/BSD timeout available
      timeout "$_rr_timeout_s" sh "$_rr_script" </dev/null >"$_rr_tmp_out" 2>"$_rr_tmp_err" || _rr_exit_code=$?
      # timeout exits 124 on timeout (GNU), 124 on BSD too
      if [ "$_rr_exit_code" -eq 124 ]; then
        _rr_error_kind="timeout"
      fi
    else
      # Fallback: background process + manual kill
      sh "$_rr_script" </dev/null >"$_rr_tmp_out" 2>"$_rr_tmp_err" &
      _rr_pid=$!
      _rr_killed=0
      _rr_elapsed=0
      while [ "$_rr_elapsed" -lt "$_rr_timeout_s" ]; do
        # Check if process is still running
        if ! kill -0 "$_rr_pid" 2>/dev/null; then
          break
        fi
        sleep 1
        _rr_elapsed=$((_rr_elapsed + 1))
      done
      if kill -0 "$_rr_pid" 2>/dev/null; then
        kill -TERM "$_rr_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$_rr_pid" 2>/dev/null || true
        _rr_error_kind="timeout"
        _rr_exit_code=124
      else
        wait "$_rr_pid" 2>/dev/null || _rr_exit_code=$?
      fi
    fi

    # Check output size (limit 64KB)
    _rr_out_size=$(wc -c <"$_rr_tmp_out" | tr -d ' ')
    if [ -z "$_rr_error_kind" ] && [ "$_rr_out_size" -gt 65536 ]; then
      _rr_error_kind="oversized_output"
    fi

    # Check nonzero exit (skip if already have error_kind from timeout)
    if [ -z "$_rr_error_kind" ] && [ "$_rr_exit_code" -ne 0 ]; then
      _rr_error_kind="nonzero_exit"
    fi

    if [ -z "$_rr_error_kind" ]; then
      # Capture stdout (limit 64KB)
      _rr_stdout=$(head -c 65536 "$_rr_tmp_out")

      # Validate JSON
      if printf '%s' "$_rr_stdout" | jq . >/dev/null 2>&1; then
        # Valid JSON — output as-is
        printf '%s\n' "$_rr_stdout"
      else
        _rr_error_kind="invalid_json"
      fi
    fi

    # Emit synthetic ERROR if any error_kind set
    if [ -n "$_rr_error_kind" ]; then
      jq -n \
        --arg id "$_rr_id" \
        --arg cat "$_rr_cat" \
        --arg kind "$_rr_error_kind" \
        '{"check_id": $id, "title": ("ERROR: " + $id), "category": $cat, "status": "ERROR", "error_kind": $kind, "evidence": []}'
    fi

    # Cleanup temp files
    rm -f "$_rr_tmp_out" "$_rr_tmp_err"

    _rr_i=$((_rr_i + 1))
  done
}
