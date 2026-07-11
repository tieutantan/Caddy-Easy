# Optional — local CA for browsers that require it
brew install mkcert
mkcert -install

# macOS
brew install caddy

# Edit the Caddyfile (`.localhost` domains get auto HTTPS)
nano $(brew --prefix)/etc/Caddyfile

myapp.localhost {
    reverse_proxy localhost:3000
}

brew services start caddy     # Start + enable at login
brew services stop caddy      # Stop
brew services restart caddy   # Restart after editing Caddyfile
