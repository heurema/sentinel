---
name: sentinel
description: >
  AI Workstation Security Audit. Use when user says "/sentinel",
  "security audit", "check my security", "scan for secrets",
  "audit my setup", "security check", "check AI security".
  Runs deterministic checks across 6 categories: secrets, MCP,
  plugins, hooks, trust boundaries, configuration hygiene.
  Produces scored report with actionable findings.
---

# /sentinel — AI Workstation Security Audit

You are orchestrating the sentinel security audit pipeline. Follow each step in order. Use the Bash tool for all shell commands.

## Step 0: Parse Arguments

Extract from the user's message:
- `--deep` flag → set DEEP=true (enables LLM advisory after audit)
- `--markdown` flag → set MARKDOWN=true (also render markdown report)
- `--no-color` flag → set NO_COLOR_FLAG=true (suppress ANSI)
- Remaining non-flag argument → PROJECT_DIR (optional, defaults to current working directory)

If PROJECT_DIR not provided, use the current working directory.

Set PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}.

## Step 1: Generate Run ID and Prepare Environment

Run:
```bash
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
echo "run_id: $RUN_ID"
```

Run:
```bash
mkdir -p ~/.sentinel/reports && chmod 700 ~/.sentinel/reports
```

## Step 2: Detect Platform

Run:
```bash
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
echo "platform: $PLATFORM"
```

## Step 3: Build Meta JSON

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
RUN_ID="<from Step 1>"
PROJECT_DIR="<resolved project dir>"
PLATFORM="<from Step 2>"

jq -n \
  --arg run_id "$RUN_ID" \
  --arg platform "$PLATFORM" \
  --arg project_dir "$PROJECT_DIR" \
  --arg plugin_version "$(jq -r .version "${PLUGIN_ROOT}/plugin.json" 2>/dev/null || echo "unknown")" \
  --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg hostname "$(hostname -s 2>/dev/null || hostname)" \
  '{run_id: $run_id, platform: $platform, project_dir: $project_dir, plugin_version: $plugin_version, started_at: $started_at, hostname: $hostname}'
```

Store the output as META_JSON.

## Step 4: Load and Validate Registry

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
sh -c ". \"${PLUGIN_ROOT}/src/lib/runner.sh\" && runner_load \"${PLUGIN_ROOT}/src/checks/registry.json\" /dev/null && echo \"\$_RUNNER_REGISTRY\" > /tmp/sentinel_registry.json && echo \"\$_RUNNER_CONFIG\" > /tmp/sentinel_config.json && echo OK"
```

Then validate:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
sh -c ". \"${PLUGIN_ROOT}/src/lib/runner.sh\" && runner_load \"${PLUGIN_ROOT}/src/checks/registry.json\" /dev/null && runner_validate \"\$_RUNNER_REGISTRY\" \"\$_RUNNER_CONFIG\" \"${PLUGIN_ROOT}/src/checks\" && echo VALID"
```

If validation fails, report the error and stop.

## Step 5: Plan Checks

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
PLATFORM="<from Step 2>"
sh -c ". \"${PLUGIN_ROOT}/src/lib/runner.sh\" && runner_load \"${PLUGIN_ROOT}/src/checks/registry.json\" /dev/null && runner_plan \"\$_RUNNER_REGISTRY\" \"\$_RUNNER_CONFIG\" \"$PLATFORM\"" > /tmp/sentinel_plan.json
cat /tmp/sentinel_plan.json | jq '{planned: (.planned | length), excluded: (.excluded | length)}'
```

Store plan JSON. Extract planned count:
```bash
PLANNED_COUNT=$(jq '.planned | length' /tmp/sentinel_plan.json)
echo "Planned: $PLANNED_COUNT checks"
```

## Step 6: Run Checks

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
START_MS=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
sh -c ". \"${PLUGIN_ROOT}/src/lib/runner.sh\" && runner_load \"${PLUGIN_ROOT}/src/checks/registry.json\" /dev/null && runner_plan \"\$_RUNNER_REGISTRY\" \"\$_RUNNER_CONFIG\" \"$(uname -s | tr '[:upper:]' '[:lower:]')\" > /tmp/sentinel_plan.json && runner_run \"\$(cat /tmp/sentinel_plan.json)\" \"${PLUGIN_ROOT}/src/checks\" \"\"" > /tmp/sentinel_results_raw.jsonl
END_MS=$(date +%s%3N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000))")
DURATION_MS=$((END_MS - START_MS))
echo "Checks complete. Duration: ${DURATION_MS}ms"
wc -l /tmp/sentinel_results_raw.jsonl
```

## Step 7: Normalize Results

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
DURATION_MS="<from Step 6>"
RESULTS_JSON="[]"
while IFS= read -r line; do
  norm=$(sh -c ". \"${PLUGIN_ROOT}/src/lib/scorer.sh\" && scorer_normalize '$(printf '%s' "$line" | sed "s/'/'\\\\''/g")' $DURATION_MS")
  RESULTS_JSON=$(printf '%s' "$RESULTS_JSON" | jq --argjson r "$norm" '. + [$r]')
done < /tmp/sentinel_results_raw.jsonl
printf '%s' "$RESULTS_JSON" > /tmp/sentinel_results.json
echo "Normalized $(jq length /tmp/sentinel_results.json) results"
```

Alternative single-command approach:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
DURATION_MS="<from Step 6>"
jq -s '.' /tmp/sentinel_results_raw.jsonl | jq --arg dur "$DURATION_MS" \
  --slurpfile scorer_fn /dev/null \
  'map(. + {finding_id: (.check_id + "|" + .category | @base64 | .[0:12]), fingerprint_version: 1, duration_ms: ($dur | tonumber)})' \
  > /tmp/sentinel_results.json
```

Preferred approach — use scorer_normalize via sh loop:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
DURATION_MS="<from Step 6>"
: > /tmp/sentinel_results_normalized.jsonl
while IFS= read -r line; do
  sh -c ". \"${PLUGIN_ROOT}/src/lib/scorer.sh\" && scorer_normalize \"\$1\" \"\$2\"" -- "$line" "$DURATION_MS" >> /tmp/sentinel_results_normalized.jsonl
done < /tmp/sentinel_results_raw.jsonl
jq -s '.' /tmp/sentinel_results_normalized.jsonl > /tmp/sentinel_results.json
echo "Normalized: $(jq length /tmp/sentinel_results.json) results"
```

## Step 8: Assess (Score)

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
PLANNED_COUNT="<from Step 5>"
RESULTS_JSON=$(cat /tmp/sentinel_results.json)
sh -c ". \"${PLUGIN_ROOT}/src/lib/scorer.sh\" && scorer_assess \"\$1\" \"\$2\"" -- "$RESULTS_JSON" "$PLANNED_COUNT" > /tmp/sentinel_scoring.json
echo "Verdict: $(jq -r .verdict /tmp/sentinel_scoring.json)  Score: $(jq .total /tmp/sentinel_scoring.json)"
```

## Step 9: Finalize Meta

Update META_JSON with completed_at:
```bash
RUN_ID="<from Step 1>"
META_JSON="<from Step 3>"
COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META_JSON=$(printf '%s' "$META_JSON" | jq --arg ca "$COMPLETED_AT" '. + {completed_at: $ca}')
```

## Step 10: Persist Report

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
META_JSON="<from Step 9>"
PLAN_JSON=$(cat /tmp/sentinel_plan.json)
RESULTS_JSON=$(cat /tmp/sentinel_results.json)
SCORING_JSON=$(cat /tmp/sentinel_scoring.json)
sh -c ". \"${PLUGIN_ROOT}/src/lib/reporter.sh\" && reporter_persist \"\$1\" \"\$2\" \"\$3\" \"\$4\" ~/.sentinel/reports" \
  -- "$META_JSON" "$PLAN_JSON" "$RESULTS_JSON" "$SCORING_JSON" > /tmp/sentinel_report_path.txt
REPORT_PATH=$(cat /tmp/sentinel_report_path.txt)
echo "Report saved: $REPORT_PATH"
```

## Step 11: Render Terminal Scorecard

Run:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REPORT_JSON=$(cat "$REPORT_PATH")
NO_COLOR_ARG="false"
# If --no-color was passed, set NO_COLOR_ARG=true
sh -c ". \"${PLUGIN_ROOT}/src/lib/reporter.sh\" && reporter_render_terminal_with_path \"\$1\" \"\$2\" \"\$3\"" \
  -- "$REPORT_JSON" "$NO_COLOR_ARG" "$REPORT_PATH"
```

Display the terminal output to the user.

## Step 11b: Render Markdown (if --markdown)

If MARKDOWN=true:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
REPORT_JSON=$(cat "$REPORT_PATH")
MD_PATH="${REPORT_PATH%.json}.md"
sh -c ". \"${PLUGIN_ROOT}/src/lib/reporter.sh\" && reporter_render_markdown \"\$1\" \"\$2\"" \
  -- "$REPORT_JSON" "$MD_PATH"
echo "Markdown report: $MD_PATH"
```

## Step 12: LLM Advisory (if --deep)

If DEEP=true, read the full report and provide analysis:

1. Read `cat "$REPORT_PATH"` to get the full JSON report
2. Identify the top 3–5 most critical findings (FAIL status, sorted by severity: critical > high > medium)
3. For each critical finding, explain:
   - What the finding means in plain language
   - Why it is a security risk in the context of AI workstation security
   - What the consequence of NOT fixing it could be
4. Provide a prioritized remediation order
5. Note any patterns (e.g., multiple secrets findings suggest a systemic secret management problem)

IMPORTANT: The LLM advisory is explanation only. Do NOT generate new shell commands. Do NOT suggest commands beyond what is in the report's `remediation.argv` fields.

## Step 13: Show Footer

Display:
```
──────────────────────────────────────────
Run `/sentinel-fix <run_id>` to remediate findings
Run `/sentinel-diff <run_id>` to compare with a previous audit
```

Where `<run_id>` is the actual run ID from Step 1.

## Error Handling

- If registry load fails (exit 4): "sentinel: registry not found or invalid. Check CLAUDE_PLUGIN_ROOT."
- If validation fails: "sentinel: registry validation failed. Check src/checks/ directory."
- If no checks are planned (ABORTED verdict): "sentinel: no checks planned for platform $PLATFORM. Check registry.json."
- If UNRELIABLE verdict: note the reliability percentage and how many checks failed to run
- Clean up temp files on completion: `rm -f /tmp/sentinel_*.json /tmp/sentinel_*.jsonl /tmp/sentinel_report_path.txt`
