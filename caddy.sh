#!/usr/bin/env bash
set -euo pipefail

# ─── Caddy Domain Manager ─────────────────────────────────────────────────────
# Cross-platform: macOS, Ubuntu, CentOS, AWS Linux
# Usage: ./caddy.sh add <domain> <ip:port>
#        ./caddy.sh remove <domain>
#        ./caddy.sh list
#        ./caddy.sh --help
# ───────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG — Edit these to match your system
# ═══════════════════════════════════════════════════════════════════════════════

# System password for sudo (used when adding/removing /etc/hosts entries)
# Leave empty to be prompted for password when needed
SUDO_PASSWORD="12143"

# Caddyfile path — auto-detected by default, override here if needed
# macOS (Homebrew):  /opt/homebrew/etc/Caddyfile or /usr/local/etc/Caddyfile
# Linux (package):   /etc/caddy/Caddyfile
# Linux (custom):    /etc/caddy/Caddyfile or ~/Caddyfile
CADDYFILE="${CADDYFILE:-}"

# Caddy restart command — auto-detected by default
# macOS:    brew services restart caddy
# Linux:    systemctl restart caddy  (or  caddy reload)
CADDY_RESTART_CMD="${CADDY_RESTART_CMD:-}"

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-DETECT: Platform, Caddyfile, Restart command
# ═══════════════════════════════════════════════════════════════════════════════

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu) echo "ubuntu" ;;
                    centos|rhel) echo "centos" ;;
                    amzn|aws) echo "aws" ;;
                    debian) echo "debian" ;;
                    *) echo "linux" ;;
                esac
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"

# Auto-detect Caddyfile if not set
if [[ -z "$CADDYFILE" ]]; then
    case "$PLATFORM" in
        macos)
            BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"
            CADDYFILE="$BREW_PREFIX/etc/Caddyfile"
            ;;
        linux|ubuntu|debian|centos|aws)
            if [[ -f /etc/caddy/Caddyfile ]]; then
                CADDYFILE="/etc/caddy/Caddyfile"
            elif [[ -f /etc/caddy/caddy.json ]]; then
                CADDYFILE="/etc/caddy/caddy.json"
            else
                CADDYFILE="/etc/caddy/Caddyfile"
            fi
            ;;
        *)
            CADDYFILE="/etc/caddy/Caddyfile"
            ;;
    esac
fi

# Auto-detect restart command if not set
if [[ -z "$CADDY_RESTART_CMD" ]]; then
    case "$PLATFORM" in
        macos)
            CADDY_RESTART_CMD="brew services restart caddy"
            ;;
        linux|ubuntu|debian|centos|aws)
            if command -v systemctl &>/dev/null; then
                CADDY_RESTART_CMD="systemctl restart caddy"
            else
                CADDY_RESTART_CMD="caddy reload --config \"$CADDYFILE\""
            fi
            ;;
        *)
            CADDY_RESTART_CMD="caddy reload --config \"$CADDYFILE\""
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════════
# COLORS — Disabled if not a terminal
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# ═══════════════════════════════════════════════════════════════════════════════
# HELP
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    cat <<EOF
Caddy Domain Manager (cross-platform)

Usage:
  $(basename "$0") add <domain> <ip:port>    Add a domain proxy
  $(basename "$0") remove <domain>           Remove a domain proxy
  $(basename "$0") list                      List all managed domains
  $(basename "$0") --help                    Show this help message

Examples:
  $(basename "$0") add myapp.localhost 127.0.0.1:3000
  $(basename "$0") add myapp.test 127.0.0.1:8080
  $(basename "$0") remove myapp.localhost
  $(basename "$0") list

Platform: $PLATFORM
Caddyfile: $CADDYFILE
Restart: $CADDY_RESTART_CMD
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

die() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}Info:${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Escape domain for use in regex/sed patterns
escape_domain() {
    echo "$1" | sed 's/\([.[\\*^$+?{}|()]\)/\\\1/g'
}

# Cross-platform mktemp
safe_mktemp() {
    mktemp 2>/dev/null || mktemp -t caddy
}

# Sudo with optional password
sudo_run() {
    if [[ -n "$SUDO_PASSWORD" ]]; then
        echo "$SUDO_PASSWORD" | sudo -S "$@" >/dev/null 2>&1
    else
        sudo "$@" >/dev/null 2>&1
    fi
}

# Check if a port is listening (cross-platform)
is_port_listening() {
    local port="$1"
    case "$PLATFORM" in
        macos)
            command -v lsof &>/dev/null && lsof -i ":$port" -P -n 2>/dev/null | grep -q LISTEN
            ;;
        linux|ubuntu|debian|centos|aws)
            if command -v ss &>/dev/null; then
                ss -tlnp "sport = :$port" 2>/dev/null | grep -qE "LISTEN|users:"
            elif command -v netstat &>/dev/null; then
                netstat -tlnp 2>/dev/null | grep -qE ":$port[[:space:]]"
            else
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# CADDYFILE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

domain_exists() {
    local domain="$1" escaped
    escaped="$(escape_domain "$domain")"
    [[ -f "$CADDYFILE" ]] && grep -qE "^# --- BEGIN $escaped ---$" "$CADDYFILE"
}

get_proxy_target() {
    local domain="$1" escaped
    escaped="$(escape_domain "$domain")"
    [[ ! -f "$CADDYFILE" ]] && return 1
    sed -n "/^# --- BEGIN $escaped ---$/,/^# --- END $escaped ---$/p" "$CADDYFILE" \
        | grep -E "^\s+reverse_proxy" | awk '{print $2}' | head -1
}

has_hosts_entry() {
    local domain="$1" escaped
    escaped="$(escape_domain "$domain")"
    grep -qsE "^127\\.0\\.0\\.1[[:space:]]+$escaped" /etc/hosts 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMMAND: add
# ═══════════════════════════════════════════════════════════════════════════════

cmd_add() {
    local domain="$1" target="$2"

    # Validate
    if ! [[ "$target" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]]; then
        die "Invalid target '$target'. Expected ip:port or host:port, e.g. 127.0.0.1:3000"
    fi
    if ! [[ "$domain" =~ ^[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$ ]]; then
        die "Invalid domain '$domain'. Expected e.g. 'myapp.localhost' or 'myapp.test'"
    fi

    # Check duplicate
    if domain_exists "$domain"; then
        local existing_target
        existing_target="$(get_proxy_target "$domain")"
        if [[ "$existing_target" == "$target" ]]; then
            warn "Domain '$domain' already exists with target '$target' — nothing to change."
        else
            warn "Domain '$domain' already exists (target: '$existing_target')."
            echo -n "  Overwrite to '$target'? [y/N] "
            read -r confirm </dev/tty || confirm="n"
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                cmd_remove "$domain" --quiet
                append_block "$domain" "$target"
                restart_caddy
                ok "Domain '$domain' updated → $target"
            else
                info "Skipped."
            fi
        fi
        return
    fi

    append_block "$domain" "$target"

    # /etc/hosts for non-.localhost
    if [[ "$domain" != *.localhost ]]; then
        if ! has_hosts_entry "$domain"; then
            info "Adding /etc/hosts entry for '$domain'..."
            local hosts_entry="127.0.0.1  $domain"
            if sudo_run sh -c "echo \"$hosts_entry\" >> /etc/hosts"; then
                ok "Added 127.0.0.1 $domain to /etc/hosts"
            else
                warn "Could not add /etc/hosts entry (add manually)."
            fi
        else
            ok "/etc/hosts entry already exists for '$domain'"
        fi
    fi

    restart_caddy
    ok "Domain '$domain' added → $target"
}

append_block() {
    local domain="$1" target="$2" tls_line=""
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Non-.localhost domains need tls internal for local HTTPS
    [[ "$domain" != *.localhost ]] && tls_line="    tls internal\n"

    touch "$CADDYFILE"
    [[ -s "$CADDYFILE" ]] && echo "" >> "$CADDYFILE"

    printf "# --- BEGIN %s ---\n# Added: %s\n%s {\n${tls_line}    reverse_proxy %s\n}\n# --- END %s ---\n" \
        "$domain" "$timestamp" "$domain" "$target" "$domain" >> "$CADDYFILE"

    ok "Added block to Caddyfile"
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMMAND: remove
# ═══════════════════════════════════════════════════════════════════════════════

cmd_remove() {
    local domain="$1" quiet="${2:-}"

    if ! domain_exists "$domain"; then
        [[ "$quiet" != "--quiet" ]] && die "Domain '$domain' not found in Caddyfile."
        return 1
    fi

    local escaped tmpfile
    escaped="$(escape_domain "$domain")"
    tmpfile="$(safe_mktemp)"
    sed "/^# --- BEGIN $escaped ---$/,/^# --- END $escaped ---$/d" "$CADDYFILE" > "$tmpfile"
    mv "$tmpfile" "$CADDYFILE"

    [[ "$quiet" != "--quiet" ]] && ok "Removed '$domain' from Caddyfile"

    # Remove /etc/hosts entry
    if [[ "$domain" != *.localhost ]] && has_hosts_entry "$domain"; then
        info "Removing /etc/hosts entry for '$domain'..."
        local escaped2 tmpfile2
        escaped2="$(escape_domain "$domain")"
        tmpfile2="$(safe_mktemp)"
        grep -vE "^127\\.0\\.0\\.1[[:space:]]+$escaped2" /etc/hosts > "$tmpfile2"
        if sudo_run mv "$tmpfile2" /etc/hosts; then
            ok "Removed '$domain' from /etc/hosts"
        else
            warn "Could not remove /etc/hosts entry (remove manually)."
        fi
    fi

    [[ "$quiet" != "--quiet" ]] && { restart_caddy; ok "Domain '$domain' removed"; }
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMMAND: list
# ═══════════════════════════════════════════════════════════════════════════════

cmd_list() {
    if [[ ! -f "$CADDYFILE" ]]; then
        info "Caddyfile not found at '$CADDYFILE' — no domains configured."
        return
    fi
    if [[ ! -s "$CADDYFILE" ]]; then
        info "Caddyfile is empty — no domains configured."
        return
    fi

    echo -e "${CYAN}Configured domains (Platform: $PLATFORM)${NC}"
    echo ""
    printf "${CYAN}%-35s %-22s %s${NC}\n" "DOMAIN" "TARGET" "HOSTS"
    echo "───────────────────────────────────────────────────────────────────────"

    local count=0
    while IFS='|' read -r domain target; do
        local hosts_status="─"
        if has_hosts_entry "$domain"; then
            hosts_status="✓"
        elif [[ "$domain" == *.localhost ]]; then
            hosts_status="auto"
        fi

        local port="${target##*:}"
        local port_status="${YELLOW}○${NC}"
        if is_port_listening "$port"; then
            port_status="${GREEN}◉${NC}"
        fi

        printf "  %-35s ${port_status} %-20s %s\n" "$domain" "$target" "$hosts_status"
        count=$((count + 1))
    done < <(parse_managed_blocks)

    echo ""
    echo -e "  ${GREEN}◉${NC} port active  ${YELLOW}○${NC} port inactive"
    echo ""
    echo "$count domain(s) configured in $CADDYFILE"
}

parse_managed_blocks() {
    awk '
    /^# --- BEGIN .+ ---$/ { domain = $4; in_block = 1; next }
    in_block && /reverse_proxy/ { target = $2; print domain "|" target }
    in_block && /^# --- END .+ ---$/ { in_block = 0; domain = ""; target = "" }
    ' "$CADDYFILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# CADDY RESTART
# ═══════════════════════════════════════════════════════════════════════════════

restart_caddy() {
    info "Restarting Caddy..."
    if eval "$CADDY_RESTART_CMD" >/dev/null 2>&1; then
        ok "Caddy restarted"
    else
        warn "Caddy restart failed — run manually: $CADDY_RESTART_CMD"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    case "${1:-}" in
        add)
            [[ $# -lt 3 ]] && die "Usage: $(basename "$0") add <domain> <ip:port>"
            cmd_add "$2" "$3"
            ;;
        remove|rm)
            [[ $# -lt 2 ]] && die "Usage: $(basename "$0") remove <domain>"
            cmd_remove "$2"
            ;;
        list|ls)
            cmd_list
            ;;
        --help|-h)
            show_help
            ;;
        *)
            if [[ $# -eq 0 ]]; then show_help
            else die "Unknown command '$1'. Use --help for usage."
            fi
            ;;
    esac
}

main "$@"
