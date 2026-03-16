#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code OTel Setup — Attri.ai (All-in-One)
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/Attri-Inc/claude-otel-audit/main/install.sh | bash
#   — or —
#   ./install.sh
#
# What it does:
#   1. Detects your shell and profile file
#   2. Auto-reads your name/email from git config
#   3. Asks for your team and Max plan number
#   4. Removes any stale OTel config (safe to re-run)
#   5. Writes a managed config block with your identity
#   6. Verifies everything works (env vars, connectivity, profile)
#
# Idempotent: safe to run multiple times. Re-run to update your config.
# ============================================================================

OTEL_ENDPOINT="http://otel.attri.live:4317"
MARKER_START="# >>> claude-otel-audit >>>"
MARKER_END="# <<< claude-otel-audit <<<"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN++)) || true; }

# ============================================================================
# PHASE 1: SETUP
# ============================================================================

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
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Claude Code OTel Setup — Attri.ai          ║${NC}"
    echo -e "${BOLD}${CYAN}║   Per-developer usage tracking               ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    # Developer name
    if [[ -n "$git_name" ]]; then
        read -r -p "  Your name [${git_name}]: " input_name
        DEV_NAME="${input_name:-$git_name}"
    else
        read -r -p "  Your name (e.g., Rahul Sharma): " DEV_NAME
        if [[ -z "$DEV_NAME" ]]; then
            echo -e "${RED}Error: Name is required.${NC}" >&2
            exit 1
        fi
    fi

    # Developer email
    if [[ -n "$git_email" ]]; then
        read -r -p "  Your email [${git_email}]: " input_email
        DEV_EMAIL="${input_email:-$git_email}"
    else
        read -r -p "  Your email (e.g., you@attri.ai): " DEV_EMAIL
        if [[ -z "$DEV_EMAIL" ]]; then
            echo -e "${RED}Error: Email is required.${NC}" >&2
            exit 1
        fi
    fi

    # Sanitize: OTel resource attributes cannot contain spaces, commas, or equals
    DEV_NAME=$(echo "$DEV_NAME" | tr ' ,=' '___')
    DEV_EMAIL=$(echo "$DEV_EMAIL" | tr ' ,=' '___')

    # Team
    echo ""
    echo "  Teams:"
    echo "    1) ai-architecture     5) data-engineering"
    echo "    2) backend             6) product"
    echo "    3) frontend            7) qa"
    echo "    4) devops              8) other (type your own)"
    echo ""
    read -r -p "  Your team [number or name]: " team_input
    case "$team_input" in
        1) TEAM_ID="ai-architecture" ;;
        2) TEAM_ID="backend" ;;
        3) TEAM_ID="frontend" ;;
        4) TEAM_ID="devops" ;;
        5) TEAM_ID="data-engineering" ;;
        6) TEAM_ID="product" ;;
        7) TEAM_ID="qa" ;;
        "") TEAM_ID="general" ;;
        *)  TEAM_ID=$(echo "$team_input" | tr ' ,=' '___') ;;
    esac

    # Max plan
    echo ""
    echo "  Which shared Max plan account are you using?"
    echo "  (Ask your team lead if unsure — enter 1-7)"
    echo ""
    read -r -p "  Plan number [1-7]: " plan_input
    if [[ -z "$plan_input" ]]; then
        echo -e "${RED}Error: Plan number is required. Ask your lead which plan you're on.${NC}" >&2
        exit 1
    fi
    PLAN_ID="plan-${plan_input}"
}

remove_existing_block() {
    local profile_file="$1"
    if grep -q "$MARKER_START" "$profile_file" 2>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "/${MARKER_START}/,/${MARKER_END}/d" "$profile_file"
        else
            sed -i "/${MARKER_START}/,/${MARKER_END}/d" "$profile_file"
        fi
    fi
}

remove_stale_otel_lines() {
    local profile_file="$1"
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
    for pattern in "${patterns[@]}"; do
        if grep -q "$pattern" "$profile_file" 2>/dev/null; then
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "/$pattern/d" "$profile_file"
            else
                sed -i "/$pattern/d" "$profile_file"
            fi
        fi
    done
    # Clean up orphaned comment
    if grep -q "^# Claude Code Telemetry" "$profile_file" 2>/dev/null; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' '/^# Claude Code Telemetry/d' "$profile_file"
        else
            sed -i '/^# Claude Code Telemetry/d' "$profile_file"
        fi
    fi
}

write_config() {
    local profile_file="$1"
    local resource_attrs="service.namespace=attri-internal,developer.name=${DEV_NAME},developer.email=${DEV_EMAIL},team.id=${TEAM_ID},max.plan.id=${PLAN_ID}"

    cat >> "$profile_file" << EOF

${MARKER_START}
# Claude Code OTel telemetry — per-developer identity for Attri.ai
# Re-run this installer to update. Do not edit manually.
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_ENDPOINT}"
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta
export OTEL_RESOURCE_ATTRIBUTES="${resource_attrs}"
${MARKER_END}
EOF

    # Export into current shell for verification phase
    export CLAUDE_CODE_ENABLE_TELEMETRY=1
    export OTEL_METRICS_EXPORTER=otlp
    export OTEL_LOGS_EXPORTER=otlp
    export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
    export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_ENDPOINT}"
    export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta
    export OTEL_RESOURCE_ATTRIBUTES="${resource_attrs}"
}

run_setup() {
    local profile_file
    profile_file=$(detect_profile)

    gather_identity

    # Backup profile before modifying
    cp "$profile_file" "${profile_file}.bak.claude-otel" 2>/dev/null || true

    remove_existing_block "$profile_file"
    remove_stale_otel_lines "$profile_file"
    write_config "$profile_file"

    echo ""
    echo -e "${GREEN}${BOLD}Config written to ${profile_file}${NC}"
    echo ""
    echo -e "  Name:     ${BOLD}${DEV_NAME}${NC}"
    echo -e "  Email:    ${BOLD}${DEV_EMAIL}${NC}"
    echo -e "  Team:     ${BOLD}${TEAM_ID}${NC}"
    echo -e "  Plan:     ${BOLD}${PLAN_ID}${NC}"
    echo -e "  Endpoint: ${BOLD}${OTEL_ENDPOINT}${NC}"
    echo ""
}

# ============================================================================
# PHASE 2: VERIFY
# ============================================================================

run_verify() {
    echo -e "${BOLD}${CYAN}── Verifying Configuration ──${NC}"
    echo ""

    # 1. Env vars
    echo "1. Environment Variables"

    check_env() {
        local var_name="$1"
        local expected="$2"
        local val="${!var_name:-}"
        if [[ -z "$val" ]]; then
            fail "$var_name is not set"
        elif [[ "$val" != "$expected" ]]; then
            warn "$var_name = $val (expected: $expected)"
        else
            pass "$var_name = $val"
        fi
    }

    check_env "CLAUDE_CODE_ENABLE_TELEMETRY" "1"
    check_env "OTEL_METRICS_EXPORTER" "otlp"
    check_env "OTEL_LOGS_EXPORTER" "otlp"
    check_env "OTEL_EXPORTER_OTLP_PROTOCOL" "grpc"

    # Endpoint
    local endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-}"
    if [[ -z "$endpoint" ]]; then
        fail "OTEL_EXPORTER_OTLP_ENDPOINT is not set"
    elif [[ "$endpoint" == *"localhost"* ]] || [[ "$endpoint" == *"127.0.0.1"* ]]; then
        fail "OTEL_EXPORTER_OTLP_ENDPOINT = $endpoint (still pointing to localhost!)"
    else
        pass "OTEL_EXPORTER_OTLP_ENDPOINT = $endpoint"
    fi

    # 2. Resource attributes
    echo ""
    echo "2. Developer Identity (OTEL_RESOURCE_ATTRIBUTES)"

    local attrs="${OTEL_RESOURCE_ATTRIBUTES:-}"
    if [[ -z "$attrs" ]]; then
        fail "OTEL_RESOURCE_ATTRIBUTES is empty — no developer identity!"
    else
        for key in "service.namespace" "developer.name" "developer.email" "team.id" "max.plan.id"; do
            if echo "$attrs" | grep -q "${key}="; then
                local value
                value=$(echo "$attrs" | tr ',' '\n' | grep "^${key}=" | cut -d= -f2)
                if [[ -z "$value" ]]; then
                    fail "$key is set but empty"
                else
                    pass "$key = $value"
                fi
            else
                fail "$key missing"
            fi
        done
    fi

    # 3. Connectivity
    echo ""
    echo "3. Endpoint Connectivity"

    if [[ -n "$endpoint" ]]; then
        local hostport="${endpoint#*://}"
        local host="${hostport%%:*}"
        local port="${hostport##*:}"
        if [[ "$port" == "$host" ]] || [[ -z "$port" ]]; then
            port="4317"
        fi

        if nc -z -w 3 "$host" "$port" 2>/dev/null; then
            pass "Connected to $host:$port (gRPC)"
        else
            fail "Cannot reach $host:$port — check network/VPN"
        fi
    else
        fail "No endpoint to test"
    fi

    # 4. Shell profile
    echo ""
    echo "4. Shell Profile"

    local profile_file
    profile_file=$(detect_profile)

    if grep -q "claude-otel-audit" "$profile_file" 2>/dev/null; then
        pass "Managed config block in $profile_file"
    else
        fail "No managed block in $profile_file"
    fi

    if grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT.*localhost' "$profile_file" 2>/dev/null; then
        # Check if it's inside or outside the managed block
        local outside
        outside=$(sed "/${MARKER_START}/,/${MARKER_END}/d" "$profile_file" | grep -c 'OTEL_EXPORTER_OTLP_ENDPOINT.*localhost' 2>/dev/null || echo "0")
        if [[ "$outside" -gt 0 ]]; then
            warn "Stale localhost endpoint outside managed block — may override"
        fi
    fi

    # 5. Claude Code
    echo ""
    echo "5. Claude Code"

    if command -v claude &>/dev/null; then
        local claude_version
        claude_version=$(claude --version 2>/dev/null || echo "unknown")
        pass "Claude Code installed: $claude_version"
    else
        warn "Claude Code CLI not found in PATH (install it if not done yet)"
    fi

    # Summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════${NC}"
    echo -e "  ${GREEN}PASS: $PASS${NC}"
    if [[ $FAIL -gt 0 ]]; then
        echo -e "  ${RED}FAIL: $FAIL${NC}"
    else
        echo -e "  FAIL: $FAIL"
    fi
    if [[ $WARN -gt 0 ]]; then
        echo -e "  ${YELLOW}WARN: $WARN${NC}"
    else
        echo -e "  WARN: $WARN"
    fi
    echo -e "${BOLD}═══════════════════════════════════${NC}"
    echo ""

    if [[ $FAIL -gt 0 ]]; then
        echo -e "${RED}${BOLD}Issues found.${NC} Fix the failures above and re-run this script."
        return 1
    elif [[ $WARN -gt 0 ]]; then
        echo -e "${YELLOW}Mostly good.${NC} Review warnings above."
    else
        echo -e "${GREEN}${BOLD}All good!${NC} Your Claude Code telemetry is configured."
    fi
}

# ============================================================================
# PHASE 3: NEXT STEPS
# ============================================================================

print_next_steps() {
    echo ""
    echo -e "${BOLD}${CYAN}── Next Steps ──${NC}"
    echo ""
    echo "  1. Open a NEW terminal window (so env vars take effect)"
    echo "  2. Start a Claude Code session and run a few prompts"
    echo "  3. Check SigNoz at https://signoz.attri.live"
    echo "     → Metrics → search 'claude_code' → filter by developer.name"
    echo ""
    echo "  To re-run this setup (e.g., change team or plan):"
    echo "    curl -sL https://raw.githubusercontent.com/Attri-Inc/claude-otel-audit/main/install.sh | bash"
    echo ""
    echo -e "  ${BOLD}Questions? Ask Sattyam or check #dev-tools on Slack.${NC}"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Check prerequisites
    if ! command -v git &>/dev/null; then
        echo -e "${RED}Error: git is not installed. Install git first.${NC}" >&2
        exit 1
    fi

    if ! command -v nc &>/dev/null; then
        echo -e "${YELLOW}Warning: nc (netcat) not found — connectivity check will be skipped.${NC}"
    fi

    run_setup
    run_verify || true
    print_next_steps
}

# Handle piped execution (curl | bash) — need a TTY for interactive prompts
if [[ ! -t 0 ]]; then
    # stdin is not a terminal (piped from curl)
    # Re-exec with /dev/tty for interactive input
    exec < /dev/tty
fi

main "$@"
