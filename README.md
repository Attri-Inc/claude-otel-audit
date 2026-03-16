# Claude Code OTel Per-Developer Audit — Attri.ai

Track individual developer Claude Code usage across shared Max plans using OpenTelemetry and SigNoz.

## Problem

30 developers share 6-7 Max plans. Without per-developer identity, all telemetry looks like the same user. This toolkit adds `service.namespace`, `developer.name`, `developer.email`, `team.id`, and `max.plan.id` to every metric and log event via `OTEL_RESOURCE_ATTRIBUTES`.

## Quick Start (One Command)

```bash
curl -sL https://raw.githubusercontent.com/Attri-Inc/claude-otel-audit/main/install.sh | bash
```

The script asks for your name, team, and plan number, then configures everything, verifies it works, and shows next steps. Safe to re-run anytime.

## What It Does

1. Detects your shell (zsh/bash) and profile file
2. Auto-reads your name/email from `git config`
3. Asks for your team and Max plan number
4. Removes any existing OTel config (idempotent)
5. Appends a managed config block to your shell profile:

```bash
# >>> claude-otel-audit >>>
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel.attri.live:4317
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=attri-internal,developer.name=yourname,developer.email=you@attri.ai,team.id=your-team,max.plan.id=plan-N"
# <<< claude-otel-audit <<<
```

6. Runs a 13-point verification (env vars, connectivity, shell profile, Claude Code install)

## SigNoz Dashboard

The **"Claude Code — Developer Audit"** dashboard is pre-configured at [signoz.attri.live](https://signoz.attri.live) with 21 panels:

### Overview (KPI Cards)
- Total Cost (USD)
- Total Tokens
- Total Sessions
- Active Time

### Per-Developer Breakdown
- Cost per Developer (USD) — ranked bar chart
- Tokens per Developer — ranked bar chart
- Sessions per Developer — ranked bar chart
- Token Type Breakdown — input/output/cacheRead/cacheCreation stacked by developer

### Usage Patterns & Misuse Detection
- Cost Over Time (Spike Detection) — time series per developer
- Sessions Over Time (Parallel Usage Detection) — detect concurrent sessions
- Cost by Developer x Model — detect expensive model overuse
- Code Edit Decisions (Coding vs Chatting) — are devs actually coding or just chatting?

### Plan & Team Distribution
- Cost by Max Plan — pie chart across 7 plans
- Cost by Team — pie chart across teams
- Cost by Model — which Claude models are used

### Developer Activity & Productivity
- Developer Leaderboard — table with cost, tokens, sessions, LOC, commits, PRs per developer (includes team + plan columns)
- Lines of Code Over Time — productivity trend
- Commits & PRs Over Time — delivery trend

### Logs & Session Activity
- Recent Developer Activity (Logs) — live log stream showing developer name, event body, session ID
- Activity Volume Over Time — log event count per developer (detect off-hours usage)
- API Errors per Developer — error pattern detection

## Resource Attributes

All telemetry carries these attributes for filtering and grouping:

| Attribute | Example | Purpose |
|-----------|---------|---------|
| `service.namespace` | `attri-internal` | Groups all Claude Code telemetry under one namespace |
| `developer.name` | `Sattyam_Jain` | Individual developer identity |
| `developer.email` | `sattyam@attri.ai` | Developer email |
| `team.id` | `ai-architecture` | Team grouping |
| `max.plan.id` | `plan-1` | Which shared Max plan account |

## Metrics Tracked

| Metric | What It Measures |
|--------|------------------|
| `claude_code.cost.usage` | USD cost per developer |
| `claude_code.token.usage` | Tokens (input/output/cache) per developer |
| `claude_code.session.count` | Number of Claude Code sessions |
| `claude_code.active_time.total` | Active coding time (seconds) |
| `claude_code.lines_of_code.count` | Lines changed with Claude |
| `claude_code.commit.count` | Commits made with Claude |
| `claude_code.pull_request.count` | PRs created with Claude |
| `claude_code.code_edit_tool.decision` | Code edit tool decisions |

## Log Events Tracked

| Event | What It Captures |
|-------|------------------|
| `claude_code.user_prompt` | Developer prompts (length, session ID) |
| `claude_code.tool_result` | Tool usage patterns |
| `claude_code.api_request` | API calls made |
| `claude_code.api_error` | Errors and failures |
| `claude_code.tool_decision` | Tool selection decisions |

## Troubleshooting

**Verification fails for endpoint connectivity**
- Check you can reach `otel.attri.live`: `nc -zv otel.attri.live 4317`
- If on VPN, ensure the route to `20.124.117.247` is allowed

**Still seeing localhost:4317 in env**
- Re-run the install script — it cleans up stale lines automatically
- Open a new terminal after running

**Dashboard shows "No Data" or errors**
- Open a **new terminal** after setup (env vars need a fresh shell)
- Start a Claude Code session and run a few prompts
- Check SigNoz after 1-2 minutes — data appears on the next metrics export interval

**git config not set**
```bash
git config --global user.name "Your Name"
git config --global user.email "you@attri.ai"
```

## Prerequisites

- Claude Code CLI installed
- `git config --global user.name` and `user.email` set
- Network access to `otel.attri.live:4317` (Azure VM at `20.124.117.247`)
