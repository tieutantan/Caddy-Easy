# Caddy Easy

Manage local domains with Caddy — add, remove, list. Works on macOS, Ubuntu, CentOS, AWS Linux.

## Quick Start

```bash
# 1. Install Caddy + mkcert + CA (skip if already installed)
./install.sh

# 2. Add domains
./caddy.sh add myapp.localhost 127.0.0.1:3000
./caddy.sh add myapp.com 127.0.0.1:8080

# 3. List
./caddy.sh list
```

## Usage

```bash
./caddy.sh add <domain> <ip:port>   # Add a domain
./caddy.sh remove <domain>          # Remove a domain
./caddy.sh rm <domain>              # Remove (shorthand)
./caddy.sh list                     # List all domains
./caddy.sh --help                   # Show help
```

## Examples

```bash
# .localhost domain (auto HTTPS, no /etc/hosts needed)
./caddy.sh add myapp.localhost 127.0.0.1:3000

# Real domain (auto /etc/hosts + tls internal)
./caddy.sh add myapp.test 127.0.0.1:8080

# List domains and their status
./caddy.sh list

# Remove
./caddy.sh remove myapp.localhost
```

## Features

- **BEGIN / END markers** — each domain is a clean block, remove deletes everything
- **Timestamp** — adds `# Added: YYYY-MM-DD HH:MM:SS` on creation
- **Auto /etc/hosts** — non-`.localhost` domains get a hosts entry automatically
- **TLS internal** — real domains use `tls internal` so Caddy generates a local certificate
- **Cross-platform** — macOS (Homebrew) / Linux (systemctl)
- **Port status** — shows active (◉) vs inactive (○) ports in list

## Configuration

Edit the top of `caddy.sh`:

```bash
SUDO_PASSWORD=""           # Sudo password (leave empty to type manually)
CADDYFILE=""               # Caddyfile path (auto-detected if empty)
CADDY_RESTART_CMD=""       # Restart command (auto-detected if empty)
```

Or use environment variables:

```bash
CADDYFILE=/etc/caddy/Caddyfile ./caddy.sh list
```

## Install Script (`install.sh`)

Auto-detect your OS and install missing dependencies:

| Component | macOS | Ubuntu / Debian | CentOS / AWS |
|-----------|-------|-----------------|--------------|
| Caddy     | `brew install caddy` | apt from official repo | yum from official repo |
| mkcert    | `brew install mkcert` | Download binary + `libnss3-tools` | Download binary + `nss-tools` |
| CA trust  | `mkcert -install` | `mkcert -install` | `mkcert -install` |
| Service   | `brew services start` | `systemctl enable --now` | `systemctl enable --now` |
| Caddyfile | `$(brew --prefix)/etc/Caddyfile` | `/etc/caddy/Caddyfile` | `/etc/caddy/Caddyfile` |

The script skips anything already installed, so it's safe to re-run anytime.

```bash
./install.sh
```

## Requirements

- Caddy installed
- `sudo` access for `/etc/hosts` (only needed for non-`.localhost` domains)

## Generated Caddyfile Example

After adding domains, your Caddyfile will look like this:

```caddy
# --- BEGIN myapp.localhost ---
# Added: 2026-06-30 22:19:46
myapp.localhost {
    reverse_proxy 127.0.0.1:3000
}
# --- END myapp.localhost ---

# --- BEGIN myapp.com ---
# Added: 2026-06-30 22:19:50
myapp.com {
    tls internal
    reverse_proxy 127.0.0.1:8080
}
# --- END myapp.com ---
```

Each domain is wrapped in `# --- BEGIN / END ---` markers so removal is always clean and complete.

