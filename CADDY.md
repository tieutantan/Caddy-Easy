# Optional
brew install mkcert
mkcert -install   # Install CA to system trust store

# macOS
brew install caddy

# Map (HTTPS auto for domain .localhost)
nano $(brew --prefix)/etc/Caddyfile

myapp.localhost {
    reverse_proxy localhost:3000
}

brew services start caddy     # Start + autostart
brew services stop caddy      # Stop
brew services restart caddy   # Restart after edit Caddyfile
