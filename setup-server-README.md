# Hetzner Ubuntu Server Setup Scripts

This repository contains two scripts for setting up a fresh Ubuntu server (22.04/24.04 LTS) on Hetzner (or any other provider) with best practices for security and usability.

## Scripts

### setup-essential.sh (Required)
Minimal, fast, secure setup (~2-3 minutes)
- **Non-Root User**: Creates a secure non-root user with sudo privileges
- **SSH Hardening**:
  - Disables root SSH login
  - Disables password authentication (key-based only)
  - Configures secure SSH settings
- **Firewall (UFW)**: Configures and enables UFW with SSH/HTTP/HTTPS ports allowed

### setup-extras.sh (Optional)
Additional features and services
- **System Updates**: Updates all system packages to the latest version
- **Fail2Ban**: Installs and configures Fail2Ban to protect against brute-force attacks
- **Automatic Security Updates**: Enables unattended-upgrades for security patches
- **Optional Docker**: Installs Docker and adds user to the docker group
- **Optional Monitoring Tools**: Installs glances, net-tools, and iptraf-ng

### setup-server.sh (Full)
Convenience script that runs both essential and extras scripts in sequence

## Usage

### Quick Start (Recommended)

1. Copy both scripts to your server:
   ```bash
   scp setup-essential.sh setup-extras.sh root@<server-ip>:/root/
   ```

2. SSH into your server as root:
   ```bash
   ssh root@<server-ip>
   ```

3. Run essential setup first:
   ```bash
   chmod +x setup-essential.sh
   ./setup-essential.sh
   ```

4. **VERIFY IT WORKS** - Log in as the new user:
   ```bash
   ssh samarth@<server-ip> -p <port>
   ```

5. Run extras setup (optional):
   ```bash
   sudo ./setup-extras.sh
   ```

### Full Setup (All-in-One)

If you want to run everything at once:
```bash
chmod +x setup-server.sh
./setup-server.sh
```

### Non-Interactive Mode

For automation, provide SSH key via environment variable:
```bash
SSH_KEY="$(cat ~/.ssh/id_rsa.pub)" ./setup-essential.sh
```

**Note:** Always verify SSH works after essential setup before running extras.

## Configuration

### setup-essential.sh
Edit the configuration variables at the top of `setup-essential.sh`:

```bash
# CONFIGURATION VARIABLES
NEW_USER="samarth"                   # Default username
SSH_PORT="22"                        # SSH port (change for security)
SSH_KEY=""                           # Leave empty to prompt, or provide public key
```

### setup-extras.sh
Edit the configuration variables at the top of `setup-extras.sh`:

```bash
# CONFIGURATION VARIABLES
NEW_USER="samarth"                   # Must match essential script
SSH_PORT="22"                        # Must match essential script
INSTALL_DOCKER="yes"                 # yes/no
INSTALL_MONITORING="yes"             # yes/no
AUTO_UPDATES="yes"                   # yes/no
```

### Setting SSH Key

You can provide your SSH public key in three ways:

1. **Environment variable** (recommended for non-interactive):
   ```bash
   SSH_KEY="ssh-rsa AAAAB3NzaC1yc2E..." ./setup-server.sh
   ```

2. **Edit the script**: Set `SSH_KEY="your-public-key-here"` in the configuration section

3. **Interactive prompt**: Leave `SSH_KEY=""` and run the script interactively (not via `curl | bash`)

**Important**: When running non-interactively (e.g., via `curl ... | bash`), you MUST provide the SSH key via option 1 or 2 above.

### Customizing SSH Port

For better security, change `SSH_PORT` to a non-standard port (e.g., `2222`):

```bash
SSH_PORT="2222"
```

**Important:** If you change the SSH port, make sure to update your SSH client configuration or specify the port when connecting:
```bash
ssh -p 2222 ubuntu@<server-ip>
```

## Post-Setup Steps

### After Essential Setup

1. **Log in as the new user**:
   ```bash
   ssh <new-user>@<server-ip> -p <ssh-port>
   ```

2. **Test sudo access**:
   ```bash
   sudo whoami
   ```
   Should return `root`

3. **Verify security settings**:
   ```bash
   # Check SSH status
   sudo systemctl status ssh

   # Check UFW status
   sudo ufw status
   ```

### After Extras Setup

4. **Verify additional services**:
   ```bash
   # Check Fail2Ban status
   sudo systemctl status fail2ban

   # Check Docker (if installed)
   docker --version

   # Check automatic updates
   cat /etc/apt/apt.conf.d/20auto-upgrades
   ```

## Why Split?

The scripts are split for **testing and validation**:

1. **Run essential first** - Gets a working, secure server in ~2-3 minutes
2. **Verify SSH works** - Log in as the new user to confirm everything works
3. **Run extras if needed** - Add Docker, monitoring, etc. later

**Benefits:**
- ✅ **Faster initial deployment** - Essential is much quicker
- ✅ **Error recovery** - If extras fail, essential part is still usable
- ✅ **Test validation** - Verify basic setup before adding complexity
- ✅ **Modularity** - Run extras later or skip entirely

## Security Notes

- **Root SSH is disabled**: You can only SSH as the non-root user
- **Password authentication is disabled**: Only SSH keys are accepted
- **Firewall is enabled**: Only allowed ports are accessible
- **Fail2Ban is active**: Protects against brute-force attacks (extras)
- **Automatic updates**: Security patches are applied automatically (extras)

## Troubleshooting

### Can't SSH after running script

1. Ensure you're using the correct username and port
2. Make sure your SSH key is correctly added to `~/.ssh/authorized_keys`
3. If locked out, use the Hetzner Console to access via web-based shell
4. Check `/etc/ssh/sshd_config` for any misconfigurations

### Port already in use

If you change SSH port and it's already in use, modify the script or choose a different port.

### Permission denied when SSH'ing as new user

**Problem**: `ssh samarth@server-ip` returns "Permission denied"

**Solutions**:
1. **Did you provide the SSH key?** If running non-interactively, you MUST set the `SSH_KEY` variable:
   ```bash
   SSH_KEY="$(cat ~/.ssh/id_rsa.pub)" ./setup-essential.sh
   ```
   or
   ```bash
   SSH_KEY="ssh-rsa AAAAB3NzaC1yc2E..." ./setup-essential.sh
   ```

2. **Check if root has an SSH key**: The script can auto-detect keys from `/root/.ssh/authorized_keys`. If root has no key, you must provide one.

3. **Verify the script completed successfully**: Check the output for any errors.

4. **Check authorized_keys file**:
   ```bash
   cat /home/samarth/.ssh/authorized_keys
   ```
   Should contain your public key.

5. **Check file permissions**:
   ```bash
   ls -la /home/samarth/.ssh/
   ```
   Should show:
   - `.ssh/` directory: `drwx------` (700)
   - `authorized_keys`: `-rw-------` (600)

6. **Check SSH configuration**:
   ```bash
   sudo cat /etc/ssh/sshd_config | grep AllowUsers
   ```
   Should show: `AllowUsers samarth`

### Docker permission issues

After Docker installation, log out and log back in for group changes to take effect, or run:
```bash
newgrp docker
```

## Customization

### Essential Script
The essential script is designed to be minimal and secure. You can modify:
- `NEW_USER`: Change the default username
- `SSH_PORT`: Change the SSH port for security
- `SSH_KEY`: Provide a specific SSH key
- Add custom SSH configuration to the heredoc section

### Extras Script
The extras script can be customized:
- `INSTALL_DOCKER`: Set to "no" to skip Docker installation
- `INSTALL_MONITORING`: Set to "no" to skip monitoring tools
- `AUTO_UPDATES`: Set to "no" to disable automatic updates
- Add more packages to the `apt-get install` command
- Modify UFW rules to allow additional ports
- Adjust Fail2Ban settings in the jail configuration

### Running Scripts Separately
You can run the scripts independently:
```bash
# Just essential setup
./setup-essential.sh

# Later, add extras
sudo ./setup-extras.sh
```

## License

This script is provided as-is for educational and practical use. Review and understand each step before running on production systems.
