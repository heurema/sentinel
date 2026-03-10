---
name: sentinel-diff
description: >
  Compare two sentinel security audit reports. Use when user says
  "/sentinel-diff", "compare audits", "what changed since last audit",
  "security diff", "compare reports". Shows new, resolved, changed findings.
---

# /sentinel-diff — Security Audit Comparison

You are comparing two sentinel audit reports to show what changed between them. Use the Bash tool to read reports.

## Step 0: Parse Arguments

Extract from the user's message:
- Two positional IDs → RUN_ID_A and RUN_ID_B (compare A→B)
- One positional ID → RUN_ID_B only (compare previous→B, auto-detect A)
- `--deep` flag → set DEEP=true (add LLM explanation of changes)

## Step 1: Validate Run ID Formats

For each provided run ID, validate it matches `^[0-9]{8}T[0-9]{6}Z$`.

Run:
```bash
echo "<RUN_ID>" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' && echo VALID || echo INVALID
```

If any ID is invalid, report the format error and stop.

## Step 2: Resolve Run IDs (single-argument mode)

If only one run ID was provided (RUN_ID_B), find the most recent report that is older than RUN_ID_B:

Run:
```bash
ls ~/.sentinel/reports/*.json 2>/dev/null | sort | grep -v '<RUN_ID_B>.json' | tail -1
```

If no prior report exists, tell the user:
"No previous report found. Run /sentinel to create a baseline, then re-run /sentinel and use /sentinel-diff <run_id_a> <run_id_b>."
Stop here.

Set RUN_ID_A to the basename of the found file (without .json).

## Step 3: Read Both Reports

Run:
```bash
cat ~/.sentinel/reports/<RUN_ID_A>.json 2>/dev/null || echo "NOT_FOUND_A"
cat ~/.sentinel/reports/<RUN_ID_B>.json 2>/dev/null || echo "NOT_FOUND_B"
```

If either is NOT_FOUND, report which report is missing and stop.

Store as REPORT_A and REPORT_B.

## Step 4: Compatibility Gate

Check schema_version matches between both reports:

Run:
```bash
VA=$(jq -r '.schema_version' ~/.sentinel/reports/<RUN_ID_A>.json)
VB=$(jq -r '.schema_version' ~/.sentinel/reports/<RUN_ID_B>.json)
echo "A: schema_version=$VA  B: schema_version=$VB"
[ "$VA" = "$VB" ] && echo COMPATIBLE || echo INCOMPATIBLE
```

If INCOMPATIBLE, tell the user:
"Reports have different schema versions (A: <VA>, B: <VB>). Cannot compare across schema versions."
Stop here.

## Step 5: Extract and Index Findings

Extract all findings from both reports, indexed by finding_id:

Run:
```bash
# All findings from A
jq '[.results[] | {finding_id, check_id, title, category, severity, status}]' \
  ~/.sentinel/reports/<RUN_ID_A>.json > /tmp/sentinel_diff_a.json

# All findings from B
jq '[.results[] | {finding_id, check_id, title, category, severity, status}]' \
  ~/.sentinel/reports/<RUN_ID_B>.json > /tmp/sentinel_diff_b.json

# Checks that ran in B (status not ERROR, not absent)
jq '[.results[] | select(.status != "ERROR") | .check_id]' \
  ~/.sentinel/reports/<RUN_ID_B>.json > /tmp/sentinel_diff_b_ran.json

echo "A findings: $(jq length /tmp/sentinel_diff_a.json)"
echo "B findings: $(jq length /tmp/sentinel_diff_b.json)"
```

## Step 6: Classify Each Finding

Classify findings from both reports into 5 categories:

**NEW** — finding_id present in B but not in A (regardless of status):
```bash
jq --slurpfile a /tmp/sentinel_diff_a.json '
  . as $b |
  ($a[0] | map(.finding_id) | unique) as $a_ids |
  map(select(.finding_id as $fid | $a_ids | index($fid) == null))
' /tmp/sentinel_diff_b.json > /tmp/sentinel_diff_new.json
```

**RESOLVED** — finding_id in A but not in B, AND the check_id ran successfully in B:
```bash
jq --slurpfile b /tmp/sentinel_diff_b.json --slurpfile b_ran /tmp/sentinel_diff_b_ran.json '
  . as $a |
  ($b[0] | map(.finding_id) | unique) as $b_ids |
  ($b_ran[0]) as $ran_in_b |
  map(
    select(
      (.finding_id as $fid | $b_ids | index($fid) == null) and
      (.check_id as $cid | $ran_in_b | index($cid) != null)
    )
  )
' /tmp/sentinel_diff_a.json > /tmp/sentinel_diff_resolved.json
```

**INCONCLUSIVE** — finding_id in A but not in B, AND check_id was excluded/error/absent in B:
```bash
jq --slurpfile b /tmp/sentinel_diff_b.json --slurpfile b_ran /tmp/sentinel_diff_b_ran.json '
  . as $a |
  ($b[0] | map(.finding_id) | unique) as $b_ids |
  ($b_ran[0]) as $ran_in_b |
  map(
    select(
      (.finding_id as $fid | $b_ids | index($fid) == null) and
      (.check_id as $cid | $ran_in_b | index($cid) == null)
    )
  )
' /tmp/sentinel_diff_a.json > /tmp/sentinel_diff_inconclusive.json
```

**CHANGED** — finding_id in both A and B, but status or severity differs:
```bash
jq --slurpfile b /tmp/sentinel_diff_b.json '
  . as $a |
  ($b[0] | map({(.finding_id): .}) | add // {}) as $b_map |
  map(
    select(.finding_id as $fid | $b_map | has($fid)) |
    . as $af |
    ($b_map[.finding_id]) as $bf |
    select($af.status != $bf.status or $af.severity != $bf.severity) |
    {
      finding_id: $af.finding_id,
      check_id: $af.check_id,
      title: $af.title,
      category: $af.category,
      from_status: $af.status,
      to_status: $bf.status,
      from_severity: $af.severity,
      to_severity: $bf.severity
    }
  )
' /tmp/sentinel_diff_a.json > /tmp/sentinel_diff_changed.json
```

**UNCHANGED** — finding_id in both, same status and severity:
```bash
jq --slurpfile b /tmp/sentinel_diff_b.json '
  . as $a |
  ($b[0] | map({(.finding_id): .}) | add // {}) as $b_map |
  map(
    select(.finding_id as $fid | $b_map | has($fid)) |
    . as $af |
    ($b_map[.finding_id]) as $bf |
    select($af.status == $bf.status and $af.severity == $bf.severity)
  )
' /tmp/sentinel_diff_a.json > /tmp/sentinel_diff_unchanged.json
```

## Step 7: Compute Deltas

Run:
```bash
SCORE_A=$(jq '.scoring.total' ~/.sentinel/reports/<RUN_ID_A>.json)
SCORE_B=$(jq '.scoring.total' ~/.sentinel/reports/<RUN_ID_B>.json)
VERDICT_A=$(jq -r '.verdict' ~/.sentinel/reports/<RUN_ID_A>.json)
VERDICT_B=$(jq -r '.verdict' ~/.sentinel/reports/<RUN_ID_B>.json)
DATE_A=$(jq -r '.meta.completed_at' ~/.sentinel/reports/<RUN_ID_A>.json)
DATE_B=$(jq -r '.meta.completed_at' ~/.sentinel/reports/<RUN_ID_B>.json)

echo "A: $VERDICT_A  $SCORE_A/100  ($DATE_A)"
echo "B: $VERDICT_B  $SCORE_B/100  ($DATE_B)"
DELTA=$((SCORE_B - SCORE_A))
echo "Delta: ${DELTA:+$DELTA}  (${DELTA#-} point change)"

echo "NEW:          $(jq length /tmp/sentinel_diff_new.json)"
echo "RESOLVED:     $(jq length /tmp/sentinel_diff_resolved.json)"
echo "INCONCLUSIVE: $(jq length /tmp/sentinel_diff_inconclusive.json)"
echo "CHANGED:      $(jq length /tmp/sentinel_diff_changed.json)"
echo "UNCHANGED:    $(jq length /tmp/sentinel_diff_unchanged.json)"
```

## Step 8: Render Diff Report

Present the diff in this order:

### Header
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Sentinel Diff: <RUN_ID_A> → <RUN_ID_B>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Baseline : <verdict_a>  <score_a>/100  <date_a>
Current  : <verdict_b>  <score_b>/100  <date_b>
Score    : <score_a> → <score_b>  (<+/->delta points)
```

### Findings Change Table
```
| Category         | NEW | RESOLVED | CHANGED | INCONCLUSIVE | UNCHANGED |
|-----------------|-----|----------|---------|--------------|-----------|
| <totals row>    |  N  |    N     |    N    |      N       |     N     |
```

### Section: NEW Findings (if any)
```
NEW FINDINGS (<count>)
──────────────────────
[critical/high/medium/low] <title>
  Check: <check_id>   Category: <category>
  Finding ID: <finding_id>
```

### Section: RESOLVED Findings (if any)
```
RESOLVED FINDINGS (<count>)
────────────────────────────
[<severity>] <title>
  Check: <check_id>   Was: <status>
```

### Section: CHANGED Findings (if any)
```
CHANGED FINDINGS (<count>)
───────────────────────────
[<severity>] <title>
  Check: <check_id>
  Status: <from_status> → <to_status>
  Severity: <from_severity> → <to_severity>  (if changed)
```

### Section: INCONCLUSIVE (if any)
```
INCONCLUSIVE (<count>)  — check did not run in B
──────────────────────────────────────────────────
[<severity>] <title>  (check_id not run in B)
```

### Section: UNCHANGED (summary only)
```
UNCHANGED: <count> findings (same status and severity in both reports)
```

## Step 9: LLM Analysis (if --deep)

If DEEP=true, provide analysis:
1. Is the security posture improving or degrading? Why?
2. Are any NEW findings high-severity — what is the immediate risk?
3. Are RESOLVED findings genuinely fixed or could they reappear?
4. Are INCONCLUSIVE findings a concern (checks not running)?
5. What should the user focus on next?

Keep the analysis to 5–8 sentences. No commands.

## Step 10: Footer

```
──────────────────────────────────────────
Run /sentinel-fix <RUN_ID_B> to remediate remaining findings.
Run /sentinel to create a new baseline.
──────────────────────────────────────────
```

Clean up temp files:
```bash
rm -f /tmp/sentinel_diff_*.json
```

## Error Handling

- If `~/.sentinel/reports/` does not exist: "No reports found. Run /sentinel first."
- If schema versions differ: stop with compatibility error (see Step 4)
- If both run IDs are the same: "Cannot diff a report against itself. Provide two different run IDs."
