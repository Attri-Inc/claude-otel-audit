#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code OTel Setup — Attri.ai
# Run once per developer machine to configure per-developer telemetry
# Usage: ./setup-claude-otel.sh
# ============================================================================

OTEL_ENDPOINT="http://otel.attri.live:4317"
MARKER_START="# >>> claude-otel-audit >>>"
MARKER_END="# <<< claude-otel-audit <<<"

detect_profile() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        bash)
            if [[ -f "${HOME}/.bash_profile" ]]; then
                echo "${HOME}/.bash_profile"
            else
                echo "${HOME}/.bashrc"
            fi
            ;;
        *)    echo "${HOME}/.profile" ;;
    esac
}

gather_identity() {
    echo ""
    echo "=== Claude Code OTel Setup (Attri.ai) ==="
    echo ""

    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    # Developer name
    if [[ -n "$git_name" ]]; then
        read -r -p "Developer name [${git_name}]: " input_name
        DEV_NAME="${input_name:-$git_name}"
    else
        read -r -p "Developer name (e.g., sattyam): " DEV_NAME
        if [[ -z "$DEV_NAME" ]]; then
            echo "Error: Developer name is required." >&2
            exit 1
        fi
    fi

    # Developer email
    if [[ -n "$git_email" ]]; then
        read -r -p "Developer email [${git_email}]: " input_email
        DEV_EMAIL="${input_email:-$git_email}"
    else
        read -r -p "Developer email (e.g., you@attri.ai): " DEV_EMAIL
        if [[ -z "$DEV_EMAIL" ]]; then
            echo "Error: Developer email is required." >&2
            exit 1
        fi
    fi

    # Sanitize values for OTel: no spaces, commas, or equals signs
    DEV_NAME=$(echo "$DEV_NAME" | tr ' ,=' '___')
    DEV_EMAIL=$(echo "$DEV_EMAIL" | tr ' ,=' '___')

    # Team ID
    echo ""
    echo "Available teams (or type your own):"
    echo "  1) ai-architecture"
    echo "  2) backend"
    echo "  3) frontend"
    echo "  4) devops"
    echo "  5) data-engineering"
    read -r -p "Team [enter name or number]: " team_input
    case "$team_input" in
        1) TEAM_ID="ai-architecture" ;;
        2) TEAM_ID="backend" ;;
        3) TEAM_ID="frontend" ;;
        4) TEAM_ID="devops" ;;
        5) TEAM_ID="data-engineering" ;;
        "") TEAM_ID="general" ;;
        *)  TEAM_ID=$(echo "$team_input" | tr ' ,=' '___') ;;
    esac

    # Max plan ID
    echo ""
    read -r -p "Which Max plan number are you on? (1-7): " plan_input
    PLAN_ID="plan-${plan_input:-unknown}"
}

remove_existing_block() {
    local profile_file="$1"
    if grep -q "$MARKER_START" "$profile_file" 2>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "/${MARKER_START}/,/${MARKER_END}/d" "$profile_file"
        else
            sed -i "/${MARKER_START}/,/${MARKER_END}/d" "$profile_file"
        fi
        echo "Removed existing Claude OTel config block from $profile_file"
    fi
}

remove_stale_otel_lines() {
    local profile_file="$1"
    # Remove individual OTel/Claude telemetry lines that exist OUTSIDE the managed block
    local patterns=(
        'export CLAUDE_CODE_ENABLE_TELEMETRY='
        'export OTEL_METRICS_EXPORTER='
        'export OTEL_LOGS_EXPORTER='
        'export OTEL_EXPORTER_OTLP_PROTOCOL='
        'export OTEL_EXPORTER_OTLP_ENDPOINT='
        'export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE='
        'export OTEL_RESOURCE_ATTRIBUTES='
        'export OTEL_LOG_USER_PROMPTS='
    )
    local removed=0
    for pattern in "${patterns[@]}"; do
        if grep -q "$pattern" "$profile_file" 2>/dev/null; then
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "/$pattern/d" "$profile_file"
            else
                sed -i "/$pattern/d" "$profile_file"
            fi
            ((removed++))
        fi
    done
    # Also remove the comment line "# Claude Code Telemetry" if present
    if grep -q "^# Claude Code Telemetry" "$profile_file" 2>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' '/^# Claude Code Telemetry/d' "$profile_file"
        else
            sed -i '/^# Claude Code Telemetry/d' "$profile_file"
        fi
        ((removed++))
    fi
    if [[ $removed -gt 0 ]]; then
        echo "Removed $removed stale OTel config lines from $profile_file"
    fi
}

write_config() {
    local profile_file="$1"
    local resource_attrs="developer.name=${DEV_NAME},developer.email=${DEV_EMAIL},team.id=${TEAM_ID},max.plan.id=${PLAN_ID}"

    cat >> "$profile_file" << EOF

${MARKER_START}
# Claude Code OTel telemetry — per-developer identity for Attri.ai
# Re-run setup-claude-otel.sh to update. Do not edit manually.
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_ENDPOINT}"
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta
export OTEL_RESOURCE_ATTRIBUTES="${resource_attrs}"
${MARKER_END}
EOF
}

main() {
    local profile_file
    profile_file=$(detect_profile)

    gather_identity

    # Clean up: remove managed block first, then stale individual lines
    remove_existing_block "$profile_file"
    remove_stale_otel_lines "$profile_file"

    write_config "$profile_file"

    echo ""
    echo "=== Configuration Written ==="
    echo ""
    echo "  Profile:    $profile_file"
    echo "  Endpoint:   $OTEL_ENDPOINT"
    echo "  Name:       $DEV_NAME"
    echo "  Email:      $DEV_EMAIL"
    echo "  Team:       $TEAM_ID"
    echo "  Plan:       $PLAN_ID"
    echo ""
    echo "  OTEL_RESOURCE_ATTRIBUTES:"
    echo "    developer.name=${DEV_NAME}"
    echo "    developer.email=${DEV_EMAIL}"
    echo "    team.id=${TEAM_ID}"
    echo "    max.plan.id=${PLAN_ID}"
    echo ""

    # Apply to current shell
    set +u
    # shellcheck disable=SC1090
    source "$profile_file"
    set -u

    echo "Config applied to current shell."
    echo ""
    echo "Next steps:"
    echo "  1. Run ./verify-claude-otel.sh to confirm everything works"
    echo "  2. Restart any open Claude Code sessions"
}

main "$@"
