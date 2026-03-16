# Claude Code OTel Per-Developer Audit — Attri.ai

Track individual developer Claude Code usage across shared Max plans using OpenTelemetry and SigNoz.

## Problem

30 developers share 6-7 Max plans. Without per-developer identity, all telemetry looks like the same user. This toolkit adds `developer.name`, `developer.email`, `team.id`, and `max.plan.id` to every metric and log event via `OTEL_RESOURCE_ATTRIBUTES`.

## Quick Start

```bash
# 1. Clone or download
git clone <repo-url> && cd claude-otel-audit

# 2. Run setup (interactive — takes 30 seconds)
./setup-claude-otel.sh

# 3. Verify everything works
./verify-claude-otel.sh

# 4. Restart any open Claude Code sessions
```

## What setup-claude-otel.sh Does

1. Detects your shell (zsh/bash) and profile file
2. Auto-reads your name/email from `git config`
3. Asks for your team and Max plan number
4. Removes any existing OTel config (idempotent — safe to re-run)
5. Appends a managed config block to your shell profile:

```bash
# >>> claude-otel-audit >>>
# Claude Code OTel telemetry — per-developer identity for Attri.ai
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel.attri.live:4317
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta
export OTEL_RESOURCE_ATTRIBUTES="developer.name=yourname,developer.email=you@attri.ai,team.id=your-team,max.plan.id=plan-N"
# <<< claude-otel-audit <<<
```

## Re-running Setup

Just run `./setup-claude-otel.sh` again. It removes the old block and writes a fresh one. Your other shell config is untouched.

## SigNoz Dashboard

Import `dashboard-claude-audit.json` into SigNoz:

1. Go to https://signoz.attri.live
2. Dashboards -> New Dashboard -> Import JSON
3. Select `dashboard-claude-audit.json`
4. Dashboard shows: cost, tokens, sessions, active time, LOC, commits, PRs — all per developer

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

## Troubleshooting

**verify-claude-otel.sh shows FAIL for endpoint connectivity**
- Check you're on VPN / can reach `otel.attri.live`
- Test: `nc -zv otel.attri.live 4317`

**Still seeing localhost:4317 in env**
- You may have old config lines outside the managed block
- Re-run `./setup-claude-otel.sh` — it cleans up stale lines too

**Metrics not showing up in SigNoz**
- Open a new terminal after setup (env vars need a fresh shell)
- Restart Claude Code session
- Run a few prompts, then check SigNoz after 1-2 minutes

**git config not set**
- Run: `git config --global user.name "Your Name"`
- Run: `git config --global user.email "you@attri.ai"`

## Prerequisites

- Claude Code CLI installed
- `git config --global user.name` and `user.email` set
- Network access to `otel.attri.live:4317`
