#!/bin/bash
# Tailscale Installation & Configuration Script
# Run as root on Ubuntu 22.04/24.04 server

set -e
export DEBIAN_FRONTEND=noninteractive

TAILSCALE_AUTH_KEY=""  # Set via environment or leave empty to prompt
TS_KEEP_FW=0         # 1 to keep existing firewall rules

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}❯❯${NC} $1"; }
print_info() { echo -e "${BLUE}❯❯${NC} $1"; }
print_error() { echo -e "${RED}❯❯${NC} $1" >&2; }

if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_info "Installing Tailscale..."

curl -fsSL https://tailscale.com/install.sh | sh

print_success "Tailscale installed"

print_info "Starting Tailscale daemon..."
systemctl start tailscaled --quiet || /usr/local/bin/tailscaled &
sleep 2

if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
    print_info "To authenticate Tailscale, you need an auth key."
    print_info "Get one at: https://login.tailscale.com/admin/settings/keys"
    print_info "Then run: tailscale up --auth-key=YOUR_AUTH_KEY"
    print_info ""
    print_info "Or connect to the machine locally and run:"
    print_info "  sudo tailscale up --auth-key=YOUR_AUTH_KEY --operator=samarth"
    print_info ""
    print_info "After authenticating, verify with: tailscale status"
else
    print_info "Authenticating with Tailscale..."
    tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --operator=samarth
    print_success "Tailscale authenticated"
fi

print_info "Configuring firewall rules for Tailscale..."

if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    if [[ $TS_KEEP_FW -eq 0 ]]; then
        ufw allow 41641/udp comment "Tailscale"
        print_info "UFW: Allowed Tailscale UDP port 41641"
    else
        print_info "Skipping firewall changes (TS_KEEP_FW=1)"
    fi
fi

if command -v iptables &> /dev/null; then
    iptables -I INPUT -p udp --dport 41641 -j ACCEPT 2>/dev/null || true
    iptables -I OUTPUT -p udp --sport 41641 -j ACCEPT 2>/dev/null || true
    print_info "iptables: Added rules for Tailscale"
fi

print_info "Enabling Tailscale to start on boot..."
systemctl enable tailscaled --quiet 2>/dev/null || true

print_success "========================================"
print_success "Tailscale setup completed!"
print_success "========================================"
print_success ""
print_success "Commands:"
print_success "  tailscale status    - Check connection"
print_success "  tailscale ip      - Get Tailscale IP"
print_success "  tailscale down     - Disconnect"
print_success "  tailscale up      - Reconnect"
print_success ""
print_info "To allow services via Tailscale, add them to your Caddyfile or configure in tailscale admin console"