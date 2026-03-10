---
name: sentinel-fix
description: >
  Guided security remediation from sentinel audit report.
  Use when user says "/sentinel-fix", "fix security issues",
  "remediate findings". Requires a run_id argument.
  Reads JSON report, walks through FAIL/WARN findings
  with What/Why/How for each. NEVER auto-executes commands.
---

# /sentinel-fix — Guided Security Remediation

You are guiding the user through remediating findings from a sentinel audit. Follow each step in order. Use the Bash tool only to read files.

## Step 0: Parse Arguments

Extract from the user's message:
- First positional argument → RUN_ID (required)
- `--deep` flag → set DEEP=true (add LLM risk explanations per finding)

If RUN_ID is missing, tell the user:
"Usage: /sentinel-fix <run_id>  — run /sentinel first to generate a report."
Stop here.

## Step 1: Validate Run ID Format

Validate RUN_ID matches the pattern `^[0-9]{8}T[0-9]{6}Z$` (e.g., `20260310T143022Z`).

Run:
```bash
echo "20260310T143022Z" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' && echo VALID || echo INVALID
```

Replace the literal value with the actual RUN_ID. If INVALID, tell the user:
"Run ID format invalid. Expected format: YYYYMMDDTHHMMSSZ (e.g., 20260310T143022Z)"
Stop here.

## Step 2: Read the Report

Run:
```bash
REPORT_PATH=~/.sentinel/reports/<RUN_ID>.json
cat "$REPORT_PATH" 2>/dev/null || echo "NOT_FOUND"
```

If output is `NOT_FOUND`, tell the user:
"Report not found: ~/.sentinel/reports/<RUN_ID>.json  — run /sentinel first."
Stop here.

Store the full JSON as REPORT_JSON.

## Step 3: Extract Findings to Remediate

From REPORT_JSON, extract findings where status is FAIL or WARN, ordered by severity:
1. critical
2. high
3. medium
4. low

Run:
```bash
jq '[.results[] | select(.status == "FAIL" or .status == "WARN")] |
  sort_by(
    if .severity == "critical" then 0
    elif .severity == "high" then 1
    elif .severity == "medium" then 2
    elif .severity == "low" then 3
    else 4 end
  )' ~/.sentinel/reports/<RUN_ID>.json
```

If the array is empty, tell the user:
"No FAIL or WARN findings in report <RUN_ID>. Your setup looks clean!"
Show the overall verdict and score from `jq '.verdict, .scoring.total' ~/.sentinel/reports/<RUN_ID>.json`.
Stop here.

## Step 4: Show Audit Summary

Before walking through findings, show a brief summary:

```
Sentinel Audit  <RUN_ID>
Verdict: <verdict>   Score: <total>/100
FAIL: <count>   WARN: <count>
```

Run:
```bash
jq -r '"Verdict: \(.verdict)  Score: \(.scoring.total)/100\nFAIL: \([.results[] | select(.status=="FAIL")] | length)  WARN: \([.results[] | select(.status=="WARN")] | length)"' ~/.sentinel/reports/<RUN_ID>.json
```

## Step 5: Walk Through Each Finding

For each finding from Step 3, present a structured block. Do NOT skip any FAIL finding.

### Finding Block Format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[<N>/<TOTAL>] <SEVERITY> — <TITLE>
Check: <check_id>   Category: <category>   Status: <status>
Finding ID: <finding_id>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**What**
<title> — <evidence summary>

Evidence:
  <list each evidence item: path, description, value if present>

**Why**
<Risk explanation based on category and severity — see Risk Explanations below>

**How** [<risk_badge>]
<remediation command block>
```

### Risk Badge Rules

Determine the risk badge from the remediation's `risk` field in the report (if present), or infer from the command:
- `safe` — read-only operations, creating files, adding configurations
- `caution` — modifying existing configs, changing permissions
- `dangerous` — deleting files, revoking credentials, system-wide changes

Display the badge as: `[SAFE]`, `[CAUTION]`, or `[DANGEROUS]`

### Remediation Command

The command comes ONLY from `remediation.argv` in the finding's JSON. Display it as a copyable code block:

```bash
<command from remediation.argv joined with spaces>
```

If `remediation` is null or `remediation.argv` is empty, display:
"No automated remediation available — manual action required."

IMPORTANT: Do NOT generate new commands. Do NOT modify the command from the report. Display it exactly as stored.

### Risk Explanations by Category and Severity

**secrets / critical**: Plaintext secrets in files or environment are directly readable by any process, AI agent, or MCP server running in this session. Immediate credential rotation may be required.

**secrets / high**: Secret exposure in git history or dotfiles persists even after deletion and can be retrieved by anyone with repository access.

**mcp / critical**: MCP server credentials in plaintext allow any tool or plugin to authenticate as you to third-party services.

**mcp / medium**: Unpinned MCP versions or missing allowlists allow supply-chain attacks — a compromised package update could execute arbitrary code.

**plugins / high**: Plugin scope leakage means a plugin has access to more filesystem paths or tools than it needs, expanding the blast radius of a compromise.

**plugins / medium**: Unverified plugins have not been audited and may contain malicious code.

**hooks / critical**: Missing PreToolUse hook means no tool call can be intercepted or blocked before execution — an AI agent or prompt injection could execute destructive commands unimpeded.

**hooks / high**: Subagent hook gap means sub-agents spawned by Claude Code do not inherit security hooks — the enforcement boundary breaks for multi-agent workflows.

**trust / medium**: Missing .claudeignore means AI agents can read any file in the project, including files with credentials, private keys, or internal data.

**trust / high**: Broad permissions or injection surface allows an attacker who controls input content to potentially execute code or exfiltrate data through prompt injection.

**config / medium**: Insecure defaults (e.g., permissive session tokens, disabled security features) can be exploited if any component is compromised.

**config / low**: Stale sessions accumulate access tokens that may no longer be needed. Clean up reduces the attack surface.

For categories/severities not listed above, use: "This finding indicates a security gap in <category> that could allow unauthorized access or data exposure."

### --deep Mode

If DEEP=true, after the How block, add:

**Risk Context**
<LLM explanation: what an attacker could realistically do with this vulnerability, what data or systems are at risk, and why fixing it should be prioritized. Keep it to 3–5 sentences. No commands.>

## Step 6: Post-Walkthrough Summary

After all findings:

```
──────────────────────────────────────────
Remediation walkthrough complete.
<N> FAIL + <M> WARN findings reviewed.

To verify fixes, run:
  /sentinel

To compare before/after:
  /sentinel-diff <previous_run_id> <new_run_id>
──────────────────────────────────────────
```

## Notes

- Always show findings in severity order (critical first)
- Never auto-execute any command — present it for the user to run
- Never generate commands beyond what is in the report
- If a finding has no remediation.argv, say so explicitly — do not invent one
- WARN findings are shown after all FAILs
