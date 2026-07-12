# Caddy Easy

Manage local domains with Caddy — add, remove, list. Works on macOS, Ubuntu, CentOS, AWS Linux.

## Quick Start

```bash
# 0. Get code
git clone https://github.com/tieutantan/Caddy-Easy.git

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
# .localhost domain (Caddy auto HTTPS, no /etc/hosts needed)
./caddy.sh add myapp.localhost 127.0.0.1:3000

# Real domain (Let's Encrypt auto, /etc/hosts added only on local machines)
./caddy.sh add myapp.com 127.0.0.1:8080

# List domains and their status
./caddy.sh list

# Remove
./caddy.sh remove myapp.localhost
```

## Features

- **Zero-config SSL** — add any domain, HTTPS works automatically:
  - `.localhost` → Caddy auto HTTPS (no setup needed)
  - Real domain on VPS → **Let's Encrypt** (auto-provisioned)
- **Cross-platform** — macOS (Homebrew), Ubuntu, Debian, CentOS, AWS Linux
- **Port status** — shows active (◉) vs inactive (○) ports in `list`
- **Auto /etc/hosts** — adds hosts entries on local machines, skips on VPS (real DNS)
- **Clean blocks** — each domain wrapped in `# --- BEGIN/END ---` markers, removal is always clean

## Configuration

Edit the top of `caddy.sh` or use environment variables:

```bash
SUDO_PASSWORD=""           # Sudo password (empty = auto-detect root/NOPASSWD/prompt)
CADDYFILE=""               # Caddyfile path (auto-detected if empty)
CADDY_RESTART_CMD=""       # Restart command (auto-detected if empty)
```

All variables can be set via environment variables:

```bash
# Via env (overrides value in script)
export SUDO_PASSWORD="mypass"
export CADDYFILE=/etc/caddy/Caddyfile
./caddy.sh add myapp.com 127.0.0.1:3000
```

### Sudo handling — automatic, no config needed

Script auto-detects privileges and chooses the right method:

| Scenario | `SUDO_PASSWORD` | Behavior |
|---|---|---|
| **Logged in as root** (VPS) | Not needed | Runs directly, no sudo |
| **User has NOPASSWD sudo** | Not needed | `sudo` runs silently |
| **User needs password sudo** | `export SUDO_PASSWORD="pass"` | `sudo -S` with password |
| **User wants to type password** | Leave empty | `sudo` prompts via terminal |

### Caddyfile permissions

On Linux, the Caddyfile is typically owned by `root`. The script automatically uses `sudo tee` when needed.
On macOS, the Caddyfile is user-owned — writes are direct.

### Auto SSL

Caddy handles certificates automatically — the script **never adds** any `tls` directive:

- `.localhost` → Caddy auto HTTPS (built-in)
- Real domain on a VPS → **Let's Encrypt** auto-provisioning
- Real domain on a local machine → Caddy tries Let's Encrypt (if DNS is public) or warns

The script detects the environment via `has_private_ip()`:
- Private IP (192.168.x, 10.x, ...) → adds `/etc/hosts` entry to resolve the domain locally
- Public IP (VPS) → **skips** `/etc/hosts` (real DNS handles it)


## Install Script (`install.sh`)

Auto-detects OS and architecture, then installs:

| Component | macOS | Ubuntu / Debian | CentOS / AWS |
|-----------|-------|-----------------|--------------|
| **Caddy** | `brew install caddy` | apt from official repo | yum from official repo |
| **mkcert** | `brew install mkcert` | Download binary (`amd64` / `arm64`) | Download binary (`amd64` / `arm64`) |
| **CA trust** | `mkcert -install` | `mkcert -install` | `mkcert -install` |
| **Service** | `brew services start` | `systemctl enable --now` | `systemctl enable --now` |
| **Caddyfile** | `$(brew --prefix)/etc/Caddyfile` | `/etc/caddy/Caddyfile` | `/etc/caddy/Caddyfile` |

Supports both `amd64` (x86_64) and `arm64` (aarch64 / AWS Graviton).
Skips anything already installed — safe to re-run anytime.

```bash
./install.sh
```

## Requirements

- Caddy installed (via `./install.sh` or manually)
- `sudo` access for `/etc/hosts` — only needed for non-`.localhost` domains on local machines

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
    reverse_proxy 127.0.0.1:8080
}
# --- END myapp.com ---
```

Each domain is wrapped in `# --- BEGIN / END ---` markers so removal is always clean and complete.

