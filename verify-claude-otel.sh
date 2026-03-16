#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code OTel Verification — Attri.ai
# Run after setup to confirm telemetry is correctly configured
# Usage: ./verify-claude-otel.sh
# ============================================================================

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $1"; ((FAIL++)) || true; }
warn() { echo "  [WARN] $1"; ((WARN++)) || true; }

echo ""
echo "=== Claude Code OTel Verification ==="
echo ""

# --- 1. Required env vars ---
echo "1. Environment Variables"

declare -A expected_vars=(
    ["CLAUDE_CODE_ENABLE_TELEMETRY"]="1"
    ["OTEL_METRICS_EXPORTER"]="otlp"
    ["OTEL_LOGS_EXPORTER"]="otlp"
    ["OTEL_EXPORTER_OTLP_PROTOCOL"]="grpc"
)

for var in "${!expected_vars[@]}"; do
    val="${!var:-}"
    expected="${expected_vars[$var]}"
    if [[ -z "$val" ]]; then
        fail "$var is not set"
    elif [[ "$val" != "$expected" ]]; then
        warn "$var = $val (expected: $expected)"
    else
        pass "$var = $val"
    fi
done

# Endpoint check (must be set, should not be localhost)
endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-}"
if [[ -z "$endpoint" ]]; then
    fail "OTEL_EXPORTER_OTLP_ENDPOINT is not set"
elif [[ "$endpoint" == *"localhost"* ]] || [[ "$endpoint" == *"127.0.0.1"* ]]; then
    fail "OTEL_EXPORTER_OTLP_ENDPOINT = $endpoint (still pointing to localhost!)"
else
    pass "OTEL_EXPORTER_OTLP_ENDPOINT = $endpoint"
fi

# --- 2. Resource attributes ---
echo ""
echo "2. Resource Attributes (OTEL_RESOURCE_ATTRIBUTES)"

attrs="${OTEL_RESOURCE_ATTRIBUTES:-}"
if [[ -z "$attrs" ]]; then
    fail "OTEL_RESOURCE_ATTRIBUTES is empty — no developer identity!"
else
    required_keys=("developer.name" "developer.email" "team.id" "max.plan.id")
    for key in "${required_keys[@]}"; do
        if echo "$attrs" | grep -q "${key}="; then
            value=$(echo "$attrs" | tr ',' '\n' | grep "^${key}=" | cut -d= -f2)
            if [[ -z "$value" ]]; then
                fail "$key is set but empty"
            else
                pass "$key = $value"
            fi
        else
            fail "$key missing from OTEL_RESOURCE_ATTRIBUTES"
        fi
    done
fi

# --- 3. Endpoint connectivity ---
echo ""
echo "3. Endpoint Connectivity"

if [[ -n "$endpoint" ]]; then
    host=$(echo "$endpoint" | sed 's|https\?://||' | cut -d: -f1)
    port=$(echo "$endpoint" | sed 's|https\?://||' | cut -d: -f2)
    port="${port:-4317}"

    if nc -z -w 3 "$host" "$port" 2>/dev/null; then
        pass "Connected to $host:$port (gRPC)"
    else
        fail "Cannot reach $host:$port — check network/VPN"
    fi

    # Also check HTTP port
    http_port=$((port + 1))
    if nc -z -w 3 "$host" "$http_port" 2>/dev/null; then
        pass "Connected to $host:$http_port (HTTP)"
    else
        warn "Cannot reach $host:$http_port (HTTP) — gRPC is sufficient"
    fi
else
    fail "No endpoint to test"
fi

# --- 4. Shell profile ---
echo ""
echo "4. Shell Profile"

shell_name=$(basename "${SHELL:-/bin/bash}")
case "$shell_name" in
    zsh)  profile="${HOME}/.zshrc" ;;
    bash) profile="${HOME}/.bash_profile"; [[ -f "$profile" ]] || profile="${HOME}/.bashrc" ;;
    *)    profile="${HOME}/.profile" ;;
esac

if grep -q "claude-otel-audit" "$profile" 2>/dev/null; then
    pass "Managed config block found in $profile"
else
    fail "No managed config block in $profile — run setup-claude-otel.sh"
fi

# Check for stale localhost lines outside the managed block
stale_lines=$(grep -c 'OTEL_EXPORTER_OTLP_ENDPOINT.*localhost' "$profile" 2>/dev/null || echo "0")
if [[ "$stale_lines" -gt 0 ]]; then
    warn "Found stale localhost OTel endpoint in $profile — may override managed config"
fi

# --- 5. Claude Code installation ---
echo ""
echo "5. Claude Code"

if command -v claude &>/dev/null; then
    claude_version=$(claude --version 2>/dev/null || echo "unknown")
    pass "Claude Code installed: $claude_version"
else
    warn "Claude Code CLI not found in PATH"
fi

# --- Summary ---
echo ""
echo "==============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  WARN: $WARN"
echo "==============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "ACTION REQUIRED: Fix the failures above, then re-run this script."
    echo "  Run: ./setup-claude-otel.sh"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo "MOSTLY GOOD: Review warnings above."
    exit 0
else
    echo "ALL GOOD: Telemetry is correctly configured for per-developer auditing."
    exit 0
fi
