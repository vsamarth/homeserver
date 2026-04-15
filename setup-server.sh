#!/bin/bash
# Hetzner Ubuntu Server Complete Setup Script
# Combines essential setup and extras features
# Run as root on a fresh Ubuntu 22.04/24.04 server

set -e  # Exit on any error

# ============================================
# CONFIGURATION VARIABLES
# ============================================
NEW_USER="samarth"                    # Default username
SSH_PORT="22"                        # SSH port (change for security)
SSH_KEY=""                           # Leave empty to prompt, or provide public key
INSTALL_DOCKER="yes"                 # yes/no
INSTALL_MONITORING="yes"             # yes/no
AUTO_UPDATES="yes"                   # yes/no

# ============================================
# OUTPUT PREFIXES WITH COLORS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}❯❯${NC} $1"
}

print_info() {
    echo -e "${BLUE}❯❯${NC} $1"
}

print_error() {
    echo -e "${RED}❯❯${NC} $1" >&2
}

# ============================================
# VALIDATION
# ============================================
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_success "Running as root"

# Check if Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    print_error "This script is designed for Ubuntu servers only"
    exit 1
fi

print_success "Ubuntu detected"

# ============================================
# TASK 1: Create Non-Root User
# ============================================
print_info "Creating non-root user: $NEW_USER"

# Check if user already exists
if id "$NEW_USER" &>/dev/null; then
    print_info "User $NEW_USER already exists"
else
    useradd -m -s /bin/bash "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    # Add passwordless sudo for the new user
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$NEW_USER"
    chmod 440 /etc/sudoers.d/"$NEW_USER"
    print_success "User $NEW_USER created and added to sudo group with passwordless sudo"
fi

# ============================================
# TASK 2: SSH Configuration & Key Setup
# ============================================
print_info "Configuring SSH..."

# Create .ssh directory for new user
mkdir -p /home/"$NEW_USER"/.ssh
chmod 700 /home/"$NEW_USER"/.ssh
chown "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.ssh

# Get SSH public key
if [[ -z "$SSH_KEY" ]]; then
    if [[ -t 0 ]]; then
        print_info "Enter SSH public key for $NEW_USER (starts with ssh-rsa or ssh-ed25519):"
        read -r SSH_KEY
    else
        print_error "ERROR: No SSH key provided."
        print_error "Please provide SSH key via:"
        print_error "  1. Setting SSH_KEY variable: SSH_KEY=\"ssh-ed25519 AAAA...\" bash setup-server.sh"
        print_error "  2. Running interactively (not via curl | bash)"
        exit 1
    fi
fi

if [[ -n "$SSH_KEY" ]]; then
    echo "$SSH_KEY" >> /home/"$NEW_USER"/.ssh/authorized_keys
    chmod 600 /home/"$NEW_USER"/.ssh/authorized_keys
    chown "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.ssh/authorized_keys
    print_success "SSH key added for $NEW_USER"
else
    print_error "No SSH key provided. This script hardens SSH for key-only login, so it cannot continue without a key."
    exit 1
fi

# Ensure the account is usable for SSH public key authentication.
# useradd commonly leaves the account locked, which can cause PAM to reject
# key-based SSH until the account has a valid password hash.
account_status="$(passwd -S "$NEW_USER" 2>/dev/null | awk '{print $2}')"
if [[ "$account_status" != "P" ]]; then
    print_info "Initializing account state for $NEW_USER so SSH key login works..."
    temp_password="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
    printf '%s:%s\n' "$NEW_USER" "$temp_password" | chpasswd
    print_success "Account state initialized for SSH key authentication"
fi

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Configure SSH
cat > /etc/ssh/sshd_config << EOF
# SSH Server Configuration
Port $SSH_PORT
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication
LoginGraceTime 120
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 5

# Key Authentication
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Password Authentication (disabled for security)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
AuthenticationMethods publickey

# GSSAPI options
GSSAPIAuthentication no

# Tunneling
X11Forwarding no
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes

# Accept environment variables
AcceptEnv LANG LC_*

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server

# Allow specific users
AllowUsers $NEW_USER
EOF

# Validate SSH config before restarting the daemon.
if ! sshd -t -f /etc/ssh/sshd_config; then
    print_error "SSH configuration validation failed; restoring original config"
    cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
    exit 1
fi

# Restart SSH service (service name varies by Ubuntu version)
if systemctl is-active --quiet sshd; then
    systemctl restart sshd --quiet
elif systemctl is-active --quiet ssh; then
    systemctl restart ssh --quiet
else
    print_info "Starting SSH service..."
    systemctl start ssh --quiet
fi
print_success "SSH configured (Root login disabled, Password auth disabled)"

# ============================================
# TASK 3: Firewall Configuration (UFW)
# ============================================
print_info "Configuring UFW firewall..."

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow "$SSH_PORT"/tcp comment "SSH"

# Allow common ports (optional)
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Enable UFW
ufw --force enable > /dev/null 2>&1

print_success "UFW firewall configured and enabled"

# ============================================
# TASK 4: System Update & Essential Packages
# ============================================
print_info "Updating system packages..."
apt update -qq > /dev/null 2>&1
apt upgrade -y -qq > /dev/null 2>&1

print_info "Installing essential packages..."
apt install -y -qq curl wget git htop vim ufw fail2ban unattended-upgrades apt-listchanges > /dev/null 2>&1

print_success "System updated and essential packages installed"

# ============================================
# TASK 5: Fail2Ban Configuration
# ============================================
print_info "Configuring fail2ban..."

# Create jail.local for SSH protection
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# Restart fail2ban
systemctl restart fail2ban --quiet
systemctl enable fail2ban --quiet

print_success "Fail2Ban configured and enabled"

# ============================================
# TASK 6: Automatic Security Updates
# ============================================
if [[ "$AUTO_UPDATES" == "yes" ]]; then
    print_info "Configuring automatic security updates..."

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    print_success "Automatic security updates enabled"
fi

# ============================================
# TASK 7: Optional - Docker Installation
# ============================================
if [[ "$INSTALL_DOCKER" == "yes" ]]; then
    print_info "Installing Docker..."

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update -qq > /dev/null 2>&1
    apt install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1

    # Add user to docker group
    usermod -aG docker "$NEW_USER" 2>/dev/null

    print_success "Docker installed"
fi

# ============================================
# TASK 8: Optional - Monitoring Tools
# ============================================
if [[ "$INSTALL_MONITORING" == "yes" ]]; then
    print_info "Installing monitoring tools..."

    apt install -y -qq glances net-tools iptraf-ng > /dev/null 2>&1

    print_success "Monitoring tools installed"
fi

# ============================================
# TASK 9: Cleanup
# ============================================
print_info "Cleaning up..."
apt autoremove -y -qq > /dev/null 2>&1
apt clean > /dev/null 2>&1

print_success "Cleanup completed"

# ============================================
# TASK 10: Verification
# ============================================
print_info "Verifying setup..."

verify_passed=0
verify_failed=0

# 1. Verify user exists
if id "$NEW_USER" &>/dev/null; then
    print_success "✓ User '$NEW_USER' exists"
    ((verify_passed++))
else
    print_error "✗ User '$NEW_USER' does not exist"
    ((verify_failed++))
fi

# 2. Verify user is in sudo group
if groups "$NEW_USER" | grep -q "\bsudo\b"; then
    print_success "✓ User '$NEW_USER' is in sudo group"
    ((verify_passed++))
else
    print_error "✗ User '$NEW_USER' is NOT in sudo group"
    ((verify_failed++))
fi

# 3. Verify user is in docker group (if Docker installed)
if [[ "$INSTALL_DOCKER" == "yes" ]]; then
    if groups "$NEW_USER" | grep -q "\bdocker\b"; then
        print_success "✓ User '$NEW_USER' is in docker group"
        ((verify_passed++))
    else
        print_error "✗ User '$NEW_USER' is NOT in docker group"
        ((verify_failed++))
    fi
fi

# 4. Verify SSH configuration
if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
        print_success "✓ Root SSH login disabled"
        ((verify_passed++))
    else
        print_error "✗ Root SSH login NOT disabled"
        ((verify_failed++))
    fi
    
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        print_success "✓ Password authentication disabled"
        ((verify_passed++))
    else
        print_error "✗ Password authentication NOT disabled"
        ((verify_failed++))
    fi
else
    print_error "✗ SSH configuration file not found"
    ((verify_failed++))
fi

# 5. Verify SSH authorized_keys
if [[ -f /home/"$NEW_USER"/.ssh/authorized_keys ]]; then
    print_success "✓ SSH authorized_keys file exists"
    ((verify_passed++))
else
    print_error "✗ SSH authorized_keys file NOT found"
    ((verify_failed++))
fi

# 6. Verify UFW status
if ufw status | grep -q "Status: active"; then
    print_success "✓ UFW firewall is active"
    ((verify_passed++))
else
    print_error "✗ UFW firewall is NOT active"
    ((verify_failed++))
fi

# 7. Verify Fail2Ban status
if systemctl is-active --quiet fail2ban; then
    print_success "✓ Fail2Ban is running"
    ((verify_passed++))
else
    print_error "✗ Fail2Ban is NOT running"
    ((verify_failed++))
fi

# 8. Verify Docker installation (if enabled)
if [[ "$INSTALL_DOCKER" == "yes" ]]; then
    if command -v docker &> /dev/null; then
        print_success "✓ Docker is installed"
        ((verify_passed++))
    else
        print_error "✗ Docker is NOT installed"
        ((verify_failed++))
    fi
fi

# 9. Verify automatic updates
if [[ "$AUTO_UPDATES" == "yes" ]]; then
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        print_success "✓ Automatic updates configured"
        ((verify_passed++))
    else
        print_error "✗ Automatic updates NOT configured"
        ((verify_failed++))
    fi
fi

# Summary of verification
print_info "Verification complete: $verify_passed passed, $verify_failed failed"

if [[ $verify_failed -gt 0 ]]; then
    print_error "WARNING: Some verification checks failed. Review the errors above."
else
    print_success "All verification checks passed!"
fi

# ============================================
# SUMMARY
# ============================================
print_success "========================================"
print_success "Server setup completed successfully!"
print_success "========================================"
print_success ""
print_success "Your server now has:"
print_success "   - Secure non-root user '$NEW_USER' with passwordless sudo"
print_success "   - SSH hardened (root login disabled, password auth disabled)"
print_success "   - UFW firewall configured and enabled"
print_success "   - Fail2Ban protecting SSH"
print_success "   - Automatic security updates"
print_success "   - Docker installed (if enabled)"
print_success "   - Monitoring tools installed (if enabled)"
print_success ""
print_success "Next steps:"
print_success "1. Log in as $NEW_USER: ssh $NEW_USER@<server-ip> -p $SSH_PORT"
print_success "2. Test sudo: sudo whoami (should return 'root')"
print_success "3. Test Docker (if installed): docker info"
print_success ""
print_success "Server IP: $(hostname -I | awk '{print $1}')"
print_success "SSH Port: $SSH_PORT"
