#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Claude Code OTel Installer — Attri.ai  (macOS, fleet rollout)
#
# Run (download first — do NOT pipe `curl | sudo bash`):
#   curl -fsSL https://raw.githubusercontent.com/Attri-Inc/claude-otel-audit/main/install.sh -o /tmp/cc-install.sh
#   TEAM_ID=backend sudo bash /tmp/cc-install.sh
#
# Writes two things:
#   1. /Library/Application Support/ClaudeCode/managed-settings.json   (root-owned)
#      — ENFORCED telemetry core (enable + exporters + endpoint). Reaches ALL surfaces
#        (terminal, VS Code, desktop app). Cannot be turned off by the user.
#      NOTE: identity is intentionally NOT here. managed-settings' OTEL_RESOURCE_ATTRIBUTES
#      overrides the shell, which would drop project.cwd. So identity + working-dir live in
#      the wrapper (terminal/CLI). Trade-off: IDE-sidebar/desktop sessions report telemetry
#      but WITHOUT identity attributes (anonymous). Most usage is terminal, so this is by design.
#   2. A managed block in the invoking user's ~/.zshrc
#      — sets identity + dynamic project.cwd/project.name for TERMINAL/CLI sessions.
#
# Identity (host.name / os.user / machine.id / developer.*) is AUTO-DERIVED — nothing typed.
# Only team.id is human-supplied (via TEAM_ID env var, or prompted if a TTY is present).
# Transport: OTLP over HTTPS (TLS). No ingest token (encrypted, open ingest for now).
# Idempotent: safe to re-run to update.
# ============================================================================

# ---- Config ---------------------------------------------------------------
OTEL_ENDPOINT="https://otel.attri.live"        # OTLP/HTTP over TLS (port 443)
# ---------------------------------------------------------------------------

MANAGED_DIR="/Library/Application Support/ClaudeCode"
MANAGED_FILE="${MANAGED_DIR}/managed-settings.json"
MARKER_START="# >>> claude-otel-audit >>>"
MARKER_END="# <<< claude-otel-audit <<<"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
say()  { echo "${CYAN}$1${NC}"; }
ok()   { echo "  ${GREEN}[OK]${NC} $1"; }
warn() { echo "  ${YELLOW}[WARN]${NC} $1"; }
die()  { echo "${RED}Error: $1${NC}" >&2; exit 1; }

# ---- Preconditions ---------------------------------------------------------
[[ "$(uname)" == "Darwin" ]] || die "This installer is macOS-only."
[[ "$(id -u)" == "0" ]] || die "Must run with sudo (writes a root-owned managed-settings file).  Try: sudo bash $0"

# Identify the REAL user (sudo makes whoami=root); their home, shell profile, git config.
REAL_USER="${SUDO_USER:-$(whoami)}"
[[ "$REAL_USER" != "root" ]] || die "Could not determine the invoking user. Run via 'sudo bash $0' as your normal account."
REAL_HOME=$(dscl . -read "/Users/${REAL_USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || REAL_HOME="/Users/${REAL_USER}"
PROFILE="${REAL_HOME}/.zshrc"   # macOS default shell is zsh

# Require TLS — never ship prompt content over cleartext.
case "$OTEL_ENDPOINT" in
    https://*) : ;;
    *) die "OTEL_ENDPOINT must be HTTPS. Got: $OTEL_ENDPOINT" ;;
esac

# ---- Auto-derive identity (nothing typed) ----------------------------------
HOST_NAME=$(hostname -s)
OS_USER="$REAL_USER"
MACHINE_ID=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4}')
[[ -n "$MACHINE_ID" ]] || MACHINE_ID="unknown-$(hostname -s)"
DEV_EMAIL=$(sudo -u "$REAL_USER" git config --global user.email 2>/dev/null || echo "")
DEV_NAME=$(sudo -u "$REAL_USER" git config --global user.name 2>/dev/null || echo "$REAL_USER")

# team.id: env var, else prompt if a TTY exists, else 'general'
TEAM_ID="${TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
    if [[ -t 0 ]]; then read -r -p "  team.id [general]: " TEAM_ID; fi
    TEAM_ID="${TEAM_ID:-general}"
fi

# Sanitize: OTel attribute values cannot contain spaces, commas, or equals signs.
san() { echo "$1" | tr ' ,=' '___'; }
DEV_NAME=$(san "$DEV_NAME"); DEV_EMAIL=$(san "$DEV_EMAIL"); TEAM_ID=$(san "$TEAM_ID")
HOST_NAME=$(san "$HOST_NAME"); OS_USER=$(san "$OS_USER"); MACHINE_ID=$(san "$MACHINE_ID")
[[ -n "$DEV_EMAIL" ]] || warn "No git email found — developer.email will be empty (os.user/machine.id still identify this machine)."

IDENTITY_ATTRS="service.namespace=attri-internal,developer.name=${DEV_NAME},developer.email=${DEV_EMAIL},team.id=${TEAM_ID},host.name=${HOST_NAME},os.user=${OS_USER},machine.id=${MACHINE_ID}"

# ---- 1. Write managed-settings.json (enforced core + identity, all surfaces) ----
say "Writing ${MANAGED_FILE}"
mkdir -p "$MANAGED_DIR"
cat > "$MANAGED_FILE" <<JSON
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "${OTEL_ENDPOINT}",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta"
  }
}
JSON
chmod 644 "$MANAGED_FILE"
chown root:wheel "$MANAGED_FILE"
python3 -c "import json; json.load(open('$MANAGED_FILE'))" 2>/dev/null && ok "managed-settings.json written and valid JSON" || die "managed-settings.json is not valid JSON"

# ---- 2. Write the shell wrapper (terminal: re-declare identity + dynamic project) ----
say "Updating ${PROFILE}"
touch "$PROFILE"; chown "$REAL_USER" "$PROFILE"
cp "$PROFILE" "${PROFILE}.bak.claude-otel" 2>/dev/null || true
if grep -q "$MARKER_START" "$PROFILE" 2>/dev/null; then
    sed -i '' "/${MARKER_START}/,/${MARKER_END}/d" "$PROFILE"
fi
cat >> "$PROFILE" <<WRAP

${MARKER_START}
# Claude Code telemetry — per-machine identity + per-project attribution (Attri.ai).
# Core on/off + endpoint are ENFORCED in managed-settings.json — not duplicated here.
# Re-run the installer to update. Do not edit manually.
export _CLAUDE_OTEL_BASE_ATTRS="${IDENTITY_ATTRS}"
claude() {
    local p n
    p=\$(echo "\$PWD" | tr ' ,=' '___')
    n=\$(basename "\$PWD" | tr ' ,=' '___')
    OTEL_RESOURCE_ATTRIBUTES="\${_CLAUDE_OTEL_BASE_ATTRS},project.cwd=\${p},project.name=\${n}" command claude "\$@"
}
${MARKER_END}
WRAP
chown "$REAL_USER" "$PROFILE"
ok "managed block added to $PROFILE"

# ---- 3. Verify -------------------------------------------------------------
echo ""; say "── Verify ──"
[[ -f "$MANAGED_FILE" ]] && ok "managed-settings present" || warn "managed-settings missing"
grep -q "claude-otel-audit" "$PROFILE" && ok "wrapper present in profile" || warn "wrapper missing"
command -v claude >/dev/null && ok "claude CLI: $(claude --version 2>/dev/null || echo '?')" || warn "claude CLI not in PATH for this shell (fine if installed per-user)"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 -X POST "${OTEL_ENDPOINT}/v1/logs" 2>/dev/null || echo "000")
case "$code" in
    200|400|415) ok "OTLP endpoint reachable over TLS (${OTEL_ENDPOINT}, HTTP ${code})" ;;
    000) warn "could not reach ${OTEL_ENDPOINT} (VPN/network?)" ;;
    *)   warn "unexpected response from ${OTEL_ENDPOINT}/v1/logs: HTTP ${code}" ;;
esac

echo ""
echo "${GREEN}${BOLD}Done.${NC}  identity: os.user=${OS_USER}  host.name=${HOST_NAME}  team.id=${TEAM_ID}"
echo "  developer.email=${DEV_EMAIL}  machine.id=${MACHINE_ID}"
echo ""
echo "  Open a NEW terminal (or restart the IDE/desktop app) for telemetry to take effect."
echo "  This installer script can now be deleted — the config it wrote persists."
