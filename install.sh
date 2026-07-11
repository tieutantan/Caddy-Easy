#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Caddy Easy — install.sh
# Install Caddy + CA trust for local development.
# Supports: macOS (Homebrew), Ubuntu, Debian, CentOS/RHEL, AWS Linux
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Config ────────────────────────────────────────────────────────────────────
# Leave empty (or set via env: export SUDO_PASSWORD="mypass") to type manually
SUDO_PASSWORD="${SUDO_PASSWORD:-}"

# ─── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

die()    { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }
info()   { echo -e "${CYAN}Info:${NC} $*"; }
ok()     { echo -e "${GREEN}✓${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC} $*"; }
header() { echo ""; echo -e "${CYAN}═══ $* ═══${NC}"; }

# ─── Platform detection ───────────────────────────────────────────────────

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu)  echo "ubuntu"  ;;
                    debian)  echo "debian"  ;;
                    centos|rhel) echo "centos" ;;
                    amzn|aws) echo "aws"    ;;
                    *)       echo "linux"   ;;
                esac
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

detect_package_manager() {
    case "$PLATFORM" in
        macos)     echo "brew" ;;
        ubuntu|debian) echo "apt" ;;
        centos)    echo "yum" ;;
        aws)       echo "yum" ;;
        linux)     echo "apt" ;;  # fallback guess
        *)         echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"
PKG_MANAGER="$(detect_package_manager)"

# ─── Sudo helpers ─────────────────────────────────────────────────────────

# Check if we are already running as root (no sudo needed)
is_root() {
    [[ $EUID -eq 0 ]]
}

# Run a command with elevated privileges (silent, used for setup commands).
sudo_run() {
    if is_root; then
        "$@" >/dev/null 2>&1
    elif [[ -n "$SUDO_PASSWORD" ]]; then
        echo "$SUDO_PASSWORD" | sudo -S "$@" >/dev/null 2>&1
    else
        sudo "$@" >/dev/null
    fi
}

# Run a command with elevated privileges and visible output (used for installers).
sudo_run_visible() {
    if is_root; then
        "$@" 2>&1 || true
    elif [[ -n "$SUDO_PASSWORD" ]]; then
        echo "$SUDO_PASSWORD" | sudo -S "$@" 2>&1 || true
    else
        sudo "$@" 2>&1 || true
    fi
}

# ─── Dependency checks ─────────────────────────────────────────────────

check_caddy() {
    command -v caddy &>/dev/null
}

check_caddy_service() {
    case "$PLATFORM" in
        macos)
            brew services info caddy 2>/dev/null | grep -qE "PID|started"
            ;;
        linux|ubuntu|debian|centos|aws)
            systemctl is-active --quiet caddy 2>/dev/null
            ;;
        *) return 1 ;;
    esac
}

check_mkcert() {
    command -v mkcert &>/dev/null
}

check_mkcert_ca() {
    # Verify that the mkcert CA root file exists and is valid
    if ! command -v mkcert &>/dev/null; then
        return 1
    fi
    local ca_root ca_file
    ca_root="$(mkcert -CAROOT 2>/dev/null)" || return 1
    ca_file="$ca_root/rootCA.pem"
    [[ -f "$ca_file" ]] && grep -q "BEGIN CERTIFICATE" "$ca_file" 2>/dev/null
}

# ─── Installers ──────────────────────────────────────────────────────────

install_caddy_macos() {
    info "Installing Caddy via Homebrew..."
    brew install caddy >/dev/null 2>&1 || die "Homebrew install failed."
    ok "Caddy installed"

    # Create a default Caddyfile if one does not exist
    local caddyfile
    caddyfile="$(brew --prefix 2>/dev/null)/etc/Caddyfile"
    if [[ ! -f "$caddyfile" ]]; then
        touch "$caddyfile"
        ok "Created empty Caddyfile at $caddyfile"
    fi

    info "Starting Caddy service..."
    brew services start caddy >/dev/null 2>&1 || warn "Could not start Caddy service."
    ok "Caddy service started"
}

install_caddy_linux_apt() {
    info "Installing Caddy via apt (official repository)..."

    # Register the official Caddy repository
    sudo_run_visible apt-get update -qq
    sudo_run_visible apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl

    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' 2>/dev/null | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null 2>&1 || true

    sudo_run_visible apt-get update -qq
    sudo_run_visible apt-get install -y -qq caddy
    ok "Caddy installed"

    sudo_run systemctl enable caddy 2>/dev/null || true
    sudo_run systemctl start caddy 2>/dev/null || true
    ok "Caddy service started"
}

install_caddy_linux_yum() {
    info "Installing Caddy via yum (official repository)..."

    sudo_run_visible yum install -y yum-utils
    sudo_run_visible yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/g/caddy/caddy/repo/epel-9/caddy-caddy-epel-9.repo 2>/dev/null || \
    sudo_run_visible yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/g/caddy/caddy/repo/epel-8/caddy-caddy-epel-8.repo 2>/dev/null || true

    sudo_run_visible yum install -y caddy
    ok "Caddy installed"

    sudo_run systemctl enable caddy 2>/dev/null || true
    sudo_run systemctl start caddy 2>/dev/null || true
    ok "Caddy service started"
}

install_mkcert_macos() {
    info "Installing mkcert via Homebrew..."
    brew install mkcert >/dev/null 2>&1 || die "mkcert install failed."
    ok "mkcert installed"

    info "Installing CA to system trust store..."
    mkcert -install >/dev/null 2>&1 || die "mkcert -install failed."
    ok "CA installed to system trust store"
}

install_mkcert_linux() {
    info "Installing mkcert..."
    local tmpdir arch
    tmpdir="$(mktemp -d)"

    # Detect architecture for the correct binary
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)       die "Unsupported architecture for mkcert: $arch" ;;
    esac

    case "$PLATFORM" in
        ubuntu|debian)
            sudo_run_visible apt-get install -y -qq libnss3-tools
            ;;
        centos|aws)
            sudo_run_visible yum install -y nss-tools
            ;;
    esac

    # Fetch the latest mkcert binary URL from GitHub releases
    local latest_url=""
    latest_url="$(curl -sL https://github.com/FiloSottile/mkcert/releases/latest 2>/dev/null \
        | grep -oE "/FiloSottile/mkcert/releases/download/v[^\"]+/mkcert-v[^\"]+-linux-$arch" \
        | head -1)" || true

    # Convert relative path to absolute URL
    if [[ -n "$latest_url" ]]; then
        latest_url="https://github.com$latest_url"
    else
        warn "Could not fetch mkcert latest release URL. Trying fixed version..."
        latest_url="https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-$arch"
    fi

    info "Downloading mkcert ($arch) from $latest_url"
    curl -sL "$latest_url" -o "$tmpdir/mkcert" 2>/dev/null || die "Failed to download mkcert."
    chmod +x "$tmpdir/mkcert"
    sudo_run mv "$tmpdir/mkcert" /usr/local/bin/mkcert
    ok "mkcert installed at /usr/local/bin/mkcert"

    info "Installing CA to system trust store..."
    mkcert -install >/dev/null 2>&1 || warn "mkcert -install failed (may need manual trust store update)."
    ok "CA installed"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Caddy Easy — Installer${NC}"
    echo -e "${CYAN}  Platform: $PLATFORM (pkg: $PKG_MANAGER)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"

    # ── Caddy ───────────────────────────────────────────────────────────────
    header "Caddy"

    if check_caddy; then
        local caddy_ver
        caddy_ver="$(caddy version 2>/dev/null | head -1)" || caddy_ver="unknown version"
        ok "Caddy already installed ($caddy_ver)"
    else
        info "Caddy not found. Installing..."
        case "$PLATFORM" in
            macos)  install_caddy_macos ;;
            ubuntu|debian) install_caddy_linux_apt ;;
            centos|aws)    install_caddy_linux_yum ;;
            linux)  install_caddy_linux_apt ;;  # fallback for unknown distros
            *)      die "Unsupported platform: $PLATFORM" ;;
        esac
    fi

    # ── Caddy service status ──────────────────────────────────────────────
    if check_caddy_service; then
        ok "Caddy service is running"
    else
        warn "Caddy service is not running — start it manually with the appropriate command."
    fi

    # ── mkcert + CA ───────────────────────────────────────────────────────
    header "mkcert + CA"

    if check_mkcert; then
        ok "mkcert already installed"
    else
        info "mkcert not found. Installing..."
        case "$PLATFORM" in
            macos)  install_mkcert_macos ;;
            ubuntu|debian|centos|aws|linux) install_mkcert_linux ;;
            *)      warn "Unsupported platform for mkcert: $PLATFORM" ;;
        esac
    fi

    if check_mkcert_ca; then
        ok "CA is already installed in system trust store"
    else
        info "CA not found in trust store. Installing..."
        if command -v mkcert &>/dev/null; then
            if mkcert -install 2>/dev/null; then
                ok "CA installed to system trust store"
            else
                warn "Could not install CA (try running 'mkcert -install' manually)"
            fi
        else
            warn "mkcert not available — install CA manually with 'mkcert -install'"
        fi
    fi

    # ── Caddyfile ───────────────────────────────────────────────────────────
    header "Caddyfile"
    local caddyfile=""
    case "$PLATFORM" in
        macos)  caddyfile="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")/etc/Caddyfile" ;;
        *)      caddyfile="/etc/caddy/Caddyfile" ;;
    esac

    if [[ -f "$caddyfile" ]]; then
        ok "Caddyfile exists at $caddyfile"
    else
        info "Creating empty Caddyfile at $caddyfile..."
        if [[ "$PLATFORM" == "macos" ]]; then
            touch "$caddyfile"
        else
            sudo_run mkdir -p "$(dirname "$caddyfile")"
            sudo_run touch "$caddyfile"
        fi
        ok "Caddyfile created at $caddyfile"
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    header "Summary"
    echo ""
    echo -e "  ${GREEN}Caddy:${NC}       $(check_caddy && echo "✅ Installed" || echo "❌ Not installed")"
    echo -e "  ${GREEN}Service:${NC}     $(check_caddy_service && echo "✅ Running" || echo "❌ Not running")"
    echo -e "  ${GREEN}mkcert:${NC}      $(check_mkcert && echo "✅ Installed" || echo "❌ Not installed")"
    echo -e "  ${GREEN}CA trust:${NC}    $(check_mkcert_ca && echo "✅ Installed" || echo "❌ Not installed")"
    echo -e "  ${GREEN}Caddyfile:${NC}   $caddyfile"
    echo ""
    echo -e "  ${CYAN}Next step:${NC} Use ./caddy.sh to add domains"
    echo ""

    if ! check_caddy; then
        die "Caddy installation failed. Check errors above."
    fi

    ok "Installation complete"
}

main "$@"
