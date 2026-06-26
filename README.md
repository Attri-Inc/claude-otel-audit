# claude-otel-audit

Org-wide Claude Code usage monitoring for Attri.ai, via OpenTelemetry → SigNoz.

## Install (macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/Attri-Inc/claude-otel-audit/main/install.sh -o /tmp/cc-install.sh
TEAM_ID=<your-team> sudo bash /tmp/cc-install.sh
```

Then open a **new terminal** — telemetry takes effect for new sessions. Re-run anytime to update.

`TEAM_ID` is the only input (e.g. `ai-architecture`, `backend`, `frontend`, `devops`,
`data-engineering`, `product`, `qa`, or your own). Everything else — hostname, OS user,
machine ID, git email — is auto-detected.

## What it does

1. Writes a root-owned `managed-settings.json` that enables OTLP telemetry to
   `https://otel.attri.live` (TLS). This covers all surfaces (terminal, IDE, desktop app).
2. Adds a managed block to `~/.zshrc` that tags each **terminal/CLI** session with your
   identity (`host.name`, `os.user`, `machine.id`, `developer.email`, `team.id`) plus the
   working directory (`project.cwd`, `project.name`).

Usage metrics, prompts, and per-directory activity are viewable in SigNoz
(`https://signoz.attri.live`).

## Notes

- **macOS only.** Idempotent — safe to re-run.
- IDE-sidebar / desktop-app sessions report telemetry but without identity attributes
  (they don't read `~/.zshrc`); terminal/CLI sessions get full attribution.
- The installer script itself is disposable; the config it writes persists.
