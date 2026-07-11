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

- **BEGIN / END markers** — each domain is a clean block, removal deletes everything
- **Timestamp** — adds `# Added: YYYY-MM-DD HH:MM:SS` on creation
- **Auto /etc/hosts** — non-`.localhost` domains get a hosts entry automatically on local machines
- **Auto SSL** — Caddy handles certificates automatically:
  - `.localhost` → Caddy auto HTTPS (no config needed)
  - Real domain → **Let's Encrypt** auto-provisioning (no `tls internal` needed)
- **Cross-platform** — macOS (Homebrew) / Linux (systemctl)
- **Port status** — shows active (◉) vs inactive (○) ports in the list

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

### Sudo handling — tự động, không cần config

Script tự động phát hiện quyền và dùng cách phù hợp:

| Tình huống | `SUDO_PASSWORD` | Hành vi |
|---|---|---|
| **Login là root** (VPS) | Không cần set | Chạy trực tiếp, bỏ qua sudo |
| **User có NOPASSWD sudo** | Không cần set | `sudo` chạy im lặng |
| **User cần password sudo** | `export SUDO_PASSWORD="pass"` | `sudo -S` dùng password |
| **User muốn gõ tay** | Để trống | `sudo` prompt qua terminal |

### Caddyfile permissions

Trên Linux, Caddyfile thường thuộc `root`. Script tự động dùng `sudo tee` để ghi khi cần.
Trên macOS, Caddyfile thuộc user — ghi trực tiếp.

### Auto SSL

Caddy tự động xử lý chứng chỉ — script **không thêm** bất kỳ directive `tls` nào:

- `.localhost` → Caddy auto HTTPS (built-in)
- Domain thật trên VPS → **Let's Encrypt** tự động
- Domain thật trên máy local → Caddy thử Let's Encrypt (nếu DNS public) hoặc báo lỗi

Script tự phát hiện môi trường qua `has_private_ip()`:
- IP private (192.168.x, 10.x, ...) → thêm `/etc/hosts` để domain trỏ về local
- IP public (VPS) → **không** thêm `/etc/hosts` (DNS thật xử lý)

## Install Script (`install.sh`)

Auto-detect OS + architecture và cài đặt:

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

