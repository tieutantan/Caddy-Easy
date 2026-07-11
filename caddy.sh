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

# Sudo password (leave empty to type manually when needed)
# Can also be set via environment variable: export SUDO_PASSWORD="mypass"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"

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
# COLORS — Disabled when not in a terminal
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
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

die() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}Info:${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Escape domain special chars for use in regex/sed patterns
escape_domain() {
    echo "$1" | sed 's/\([.[\\*^$+?{}|()]\)/\\\1/g'
}

# Cross-platform temp file creation
safe_mktemp() {
    mktemp 2>/dev/null || mktemp -t caddy
}

# Check if we are already running as root (no sudo needed)
is_root() {
    [[ $EUID -eq 0 ]]
}

# Run a command with elevated privileges.
# Supports: already root, NOPASSWD sudo, or password-based sudo.
sudo_run() {
    if is_root; then
        # Already root — run directly, no sudo needed
        "$@" >/dev/null 2>&1
    elif [[ -n "$SUDO_PASSWORD" ]]; then
        # Password provided — use sudo -S with stdin
        echo "$SUDO_PASSWORD" | sudo -S "$@" >/dev/null 2>&1
    else
        # No password configured — try NOPASSWD sudo or prompt interactively
        # Stderr kept visible so user can see the password prompt
        sudo "$@" >/dev/null
    fi
}

# Check if a TCP port is currently listening (cross-platform)
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

# Check whether an IP falls in a private / local range
is_private_ip() {
    local ip="$1"
    [[ "$ip" =~ ^127\. ]] && return 0   # loopback
    [[ "$ip" =~ ^10\. ]] && return 0     # 10.0.0.0/8
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0  # 172.16.0.0/12
    [[ "$ip" =~ ^192\.168\. ]] && return 0  # 192.168.0.0/16
    return 1
}

# Check if this machine has any private IP address (i.e. is a local dev machine)
has_private_ip() {
    local ips
    case "$PLATFORM" in
        macos)
            ips="$(ifconfig 2>/dev/null | grep -E 'inet ' | awk '{print $2}')" || return 1
            ;;
        linux|ubuntu|debian|centos|aws)
            ips="$(hostname -I 2>/dev/null)" || return 1
            ;;
        *) return 1 ;;
    esac
    [[ -z "$ips" ]] && return 1
    local ip
    for ip in $ips; do
        is_private_ip "$ip" && return 0
    done
    return 1
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

# Add a /etc/hosts entry for a domain (only on local machines, skip .localhost)
ensure_hosts_entry() {
    local domain="$1"
    [[ "$domain" == *.localhost ]] && return
    has_private_ip || return
    has_hosts_entry "$domain" && { ok "/etc/hosts entry already exists for '$domain'"; return; }

    info "Adding /etc/hosts entry for '$domain'..."
    local hosts_entry="127.0.0.1  $domain"
    if sudo_run sh -c "echo \"$hosts_entry\" >> /etc/hosts"; then
        ok "Added 127.0.0.1 $domain to /etc/hosts"
    else
        warn "Could not add /etc/hosts entry (add manually)."
    fi
}

# Remove a /etc/hosts entry for a domain
remove_hosts_entry() {
    local domain="$1"
    [[ "$domain" == *.localhost ]] && return
    has_hosts_entry "$domain" || return

    info "Removing /etc/hosts entry for '$domain'..."
    local escaped tmpfile
    escaped="$(escape_domain "$domain")"
    tmpfile="$(safe_mktemp)"
    # grep returns 1 when no lines match (file would be empty) — ignore that with || true
    grep -vE "^127\.0\.0\.1[[:space:]]+$escaped" /etc/hosts > "$tmpfile" 2>/dev/null || true
    if sudo_run mv "$tmpfile" /etc/hosts; then
        ok "Removed '$domain' from /etc/hosts"
    else
        warn "Could not remove /etc/hosts entry (remove manually)."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMMAND: add
# ═══════════════════════════════════════════════════════════════════════════════

cmd_add() {
    local domain="$1" target="$2"

    # Validate target format (ip:port or host:port)
    if ! [[ "$target" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]]; then
        die "Invalid target '$target'. Expected ip:port or host:port, e.g. 127.0.0.1:3000"
    fi
    # Validate domain format
    if ! [[ "$domain" =~ ^[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}$ ]]; then
        die "Invalid domain '$domain'. Expected e.g. 'myapp.localhost' or 'myapp.test'"
    fi

    # If the domain already exists, offer to overwrite the target
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
                ensure_hosts_entry "$domain"             # <-- re-add hosts entry (fix: was missing before)
                restart_caddy
                ok "Domain '$domain' updated → $target"
            else
                info "Skipped."
            fi
        fi
        return
    fi

    append_block "$domain" "$target"
    ensure_hosts_entry "$domain"
    restart_caddy
    ok "Domain '$domain' added → $target"
}

append_block() {
    local domain="$1" target="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Ensure the Caddyfile exists
    # If the parent directory is not writable, use sudo (Linux: /etc/caddy/ is root-owned)
    if [[ ! -f "$CADDYFILE" ]]; then
        if [[ ! -w "$(dirname "$CADDYFILE")" ]]; then
            sudo_run mkdir -p "$(dirname "$CADDYFILE")"
            sudo_run touch "$CADDYFILE"
        else
            touch "$CADDYFILE"
        fi
    fi

    # Add a blank line separator if the file is non-empty
    if [[ -s "$CADDYFILE" ]]; then
        if [[ -w "$CADDYFILE" ]]; then
            echo "" >> "$CADDYFILE"
        else
            echo "" | sudo tee -a "$CADDYFILE" >/dev/null
        fi
    fi

    local block
    block="$(printf "# --- BEGIN %s ---\n# Added: %s\n%s {\n    reverse_proxy %s\n}\n# --- END %s ---\n" \
        "$domain" "$timestamp" "$domain" "$target" "$domain")"

    # Write the block (use sudo if the Caddyfile is not user-writable)
    if [[ -w "$CADDYFILE" ]]; then
        printf "%s" "$block" >> "$CADDYFILE"
    else
        printf "%s" "$block" | sudo tee -a "$CADDYFILE" >/dev/null
    fi

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

    # Replace the Caddyfile (use sudo on Linux where it is typically root-owned)
    if [[ -w "$CADDYFILE" ]]; then
        mv "$tmpfile" "$CADDYFILE"
    else
        sudo_run mv "$tmpfile" "$CADDYFILE"
    fi

    [[ "$quiet" != "--quiet" ]] && ok "Removed '$domain' from Caddyfile"

    # Also clean up the corresponding /etc/hosts entry
    remove_hosts_entry "$domain"

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
    # Use sudo_run so it works on Linux (systemctl needs root) and macOS alike
    if sudo_run sh -c "$CADDY_RESTART_CMD"; then
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
