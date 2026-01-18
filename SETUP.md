# 🚀 OnionSite-Aegis Setup Guide (v9.0 Architect)

Complete setup instructions for both Docker and bare metal deployments.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Bare Metal Installation](#bare-metal-installation)
3. [Docker Installation](#docker-installation)
4. [Post-Installation](#post-installation)
5. [Troubleshooting](#troubleshooting)
6. [Maintenance](#maintenance)

---

## Quick Start

### Docker (Fastest)

```bash
mkdir -p data/tor-keys webroot
echo "<h1>My Site</h1>" > webroot/index.html
docker-compose build && docker-compose up -d
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```

Bare Metal (Architect Installer)

 Bash

```bash
sudo chmod +x install.sh
sudo ./install.sh
# Follow the interactive prompts (Enable SSH if using Cloud VPS)
sudo cat /var/lib/tor/hidden_service/hostname
```

Bare Metal Installation

Step 1: Prerequisites

System Requirements:
Debian 11+ (Bookworm/Trixie), Kali Linux, or Parrot OS (Ubuntu 20.04+ may work)
Root/sudo access
At least 500MB free disk space
Internet connection

Verify System:

Bash

```bash
# Check OS
cat /etc/os-release

# Check disk space
df -h /

# Check if running as root
whoami  # Should be 'root' or use sudo
```

Step 2: Download and Extract

Bash

```bash
# If downloaded as zip
unzip OnionSite-Aegis.zip
cd OnionSite-Aegis

# Or if cloned from git
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
```

Step 3: Run Installer (v9.0 Architect)

The v9.0 installer is interactive. It will ask you to customize your security stack.

Bash

```bash
# Make executable
sudo chmod +x install.sh

# Run installer
sudo ./install.sh
```
```
Configuration Prompts:

You will be asked to enable or disable the following:
ModSecurity WAF: [y/N] (Recommended for dynamic sites)
Lua Response Padding: [y/N] (Recommended for anti-fingerprinting)
Neural Sentry IPS: [y/N] (Active defense daemon)
Privacy Monitor: [y/N] (Periodic compliance checks)
Traffic Analysis Protection: [y/N] (Advanced timing randomization)
SSH Access: [y/N] (CRITICAL: Enable this if using AWS/DigitalOcean/Linode to prevent lockout)

What the v9.0 installer does:
✅ Nuclear Sanitization: Purges "ghost configs" and conflicting modules.
✅ Dependency Check: Installs Tor, Nginx, NDK, NFTables, Python packages.
✅ Ram-Based Logging: Configures tmpfs for /var/log/tor (Anti-Forensics).
✅ Balanced Firewall: Applies optimized NFTables rules that allow Tor connectivity while blocking attacks.
✅ Tor Hardening: Configures Sandbox, V3 Hidden Service, and Privacy directives.
✅ Nginx Architecture: Enforces correct load order (NDK -> Lua -> WAF).
✅ Active Defense: Installs Neural Sentry and ModSecurity (if selected).
✅ SSH Safety: Automatically whitelist SSH if selected to prevent lockout.
```
Expected Output:

```
=== ONIONSITE-AEGIS ARCHITECT v9.0 ===
[INFO] Performing Pre-Flight Environment Checks...
[INFO] Sanitizing Environment...
[INFO] Installing Dependencies...
[INFO] Configuring RAM Logging...
[INFO] Hardening Tor Configuration...
[INFO] Building Nginx Architecture...
[INFO] Bootstrapping Network...
Waiting for Onion Address generation..........

================================================================
>>> SYSTEM ONLINE: abc123def456.onion <<<
----------------------------------------------------------------
 [ON] WAF (ModSecurity)
 [ON] Lua (Padding)
 [ON] Neural Sentry
 [ON] SSH Access (Safe Mode)
----------------------------------------------------------------
Edit your site: sudo aegis-edit
================================================================
```

Step 4: Verify Installation

Bash

```bash
# Check services are running
sudo systemctl status tor
sudo systemctl status nginx
sudo systemctl status neural-sentry

# Get your onion address
sudo cat /var/lib/tor/hidden_service/hostname

# Verify hidden service directory
sudo ls -la /var/lib/tor/hidden_service/
# Should show: hostname, hs_ed25519_public_key, hs_ed25519_secret_key

# Check RAM logs
sudo ls -la /var/log/tor/
# or
sudo ls -la /mnt/ram_logs/
```

Step 5: Add Your Content

Use the built-in secure editor to avoid permission issues:

Bash

```bash
sudo aegis-edit
```

Or manually:

Bash

```bash
# Place your website files here
sudo cp -r /path/to/your/website/* /var/www/onion_site/

# Set correct permissions
sudo chown -R www-data:www-data /var/www/onion_site
sudo find /var/www/onion_site -type f -exec chmod 644 {} \;
sudo find /var/www/onion_site -type d -exec chmod 755 {} \;
```

Docker Installation

Step 1: Prerequisites

Required:
Docker Engine 20.10+ (docker --version)
Docker Compose 2.0+ (docker-compose --version)

Install Docker (if needed):

Bash

```bash
# Debian/Ubuntu
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt-get install docker-compose-plugin
```

Step 2: Prepare Directories

Bash

```bash
# Navigate to project directory
cd OnionSite-Aegis

# Create required directories
mkdir -p data/tor-keys webroot

# Create your web content
cat > webroot/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>My Onion Site</title>
</head>
<body>
    <h1>Welcome to My Onion Site</h1>
    <p>This site is accessible only via Tor.</p>
</body>
</html>
EOF
```

Step 3: Build and Run

Bash

```bash
# Build the Docker image
docker-compose build

# Start the container
docker-compose up -d

# View logs (wait for "Onion address" message)
docker-compose logs -f aegis
```

Expected Output:

```
[AEGIS] Starting OnionSite-Aegis v9.0 (Docker)
[AEGIS] Setting up RAM-based logging...
[AEGIS] Configuring Tor...
[AEGIS] Creating hidden service directory...
[AEGIS] Deploying Web Application Firewall...
[AEGIS] Starting services...
[AEGIS] Starting Tor...
[AEGIS] Waiting for Tor to create hidden service hostname...
[AEGIS] Hidden service hostname created successfully!
[AEGIS] Onion address: abc123def456.onion
[AEGIS] Starting Neural Sentry...
[AEGIS] Starting Nginx...
```

Step 4: Get Your Onion Address

Bash

```bash
# Method 1: From container
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname

# Method 2: From logs
docker-compose logs aegis | grep "Onion address"

# Method 3: From host (if volume mounted)
cat data/tor-keys/hostname
```

Step 5: Verify Installation

Bash

```bash
# Check container status
docker-compose ps
# Should show: State: Up, Health: healthy

# Check health
docker-compose exec aegis test -f /var/lib/tor/hidden_service/hostname && echo "✓ Hidden service created"

# Check services inside container
docker-compose exec aegis ps aux | grep -E 'tor|nginx|python'

# View all logs
docker-compose logs --tail=50 aegis
```

Step 6: Update Web Content

Bash

```bash
# Edit files in webroot directory
nano webroot/index.html

# Changes are reflected immediately (volume is mounted)
# No need to restart container
```

Post-Installation
```bash
Access Your Site
Install Tor Browser: https://www.torproject.org/download/
Open Tor Browser
Navigate to: http://your-onion-address.onion
Replace your-onion-address.onion with the address from /var/lib/tor/hidden_service/hostname
```
Important Files and Directories

Bare Metal:
- Onion Address: /var/lib/tor/hidden_service/hostname
- Web Root: /var/www/onion_site
- Logs: /var/log/tor/ or /mnt/ram_logs/ (RAM - volatile!)
- Tor Config: /etc/tor/torrc
- Nginx Config: /etc/nginx/sites-available/onion_site

Docker:
- Onion Address: data/tor-keys/hostname (on host)
- Web Root: webroot/ (on host)
- Logs: Inside container at /mnt/ram_logs/ (RAM - volatile!)
- Container Name: onionsite-aegis

Backup Tor Keys (CRITICAL!)

⚠️ WARNING: Losing your Tor keys means losing your Onion address forever!

Bare Metal:

Bash

```bash
# Create backup (Use the included script for safety)
sudo ./SAVE_MY_ONION.sh

# Or Manual Backup
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/
```

Docker:

Bash

```bash
# Backup the keys directory
tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz data/tor-keys/
```

Monitoring

Check Service Status:

Bash

```bash
# Bare Metal (Use the HUD v5.0)
sudo ./aegis_monitor.sh

# Docker
docker-compose ps
docker-compose logs --tail=50 aegis
```

View Logs:

Bash

```bash
# Bare Metal (RAM logs - temporary!)
sudo tail -f /var/log/tor/notices.log
sudo tail -f /var/log/nginx/access.log

# Docker
docker-compose logs -f aegis
```

Troubleshooting

Hidden Service Not Created

Symptoms:
No hostname file in /var/lib/tor/hidden_service/
Onion address shows "Pending..." or empty

Bare Metal Fix:

Bash

```bash
# 1. Check Tor service
sudo systemctl status tor

# 2. Check Tor logs
sudo tail -f /var/log/tor/notices.log

# 3. Verify directory permissions
sudo ls -la /var/lib/tor/hidden_service/
sudo chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
sudo chmod 700 /var/lib/tor/hidden_service

# 4. Restart Tor
sudo systemctl restart tor
sleep 10
sudo cat /var/lib/tor/hidden_service/hostname
```

NFTables Errors / SSH Lockout

Symptoms:
Job for nftables.service failed
You cannot SSH into your server after install

Fix:
v9.0 includes an SSH Safety Valve. If you are locked out, you may need to access your VPS via the provider's Web Console (VNC) and run:

Bash

```bash
# Emergency Flush
sudo nft flush ruleset

# Re-run installer and select 'YES' for SSH Access
sudo ./install.sh
```

Service Won't Start (Nginx/Lua Error)

Symptoms:
undefined symbol: ndk_set_var_value
Nginx fails to start

Fix (v9.0 Architect):
This is caused by incorrect module load order. Rerun the installer to apply the automatic fix:

Bash

```bash
sudo ./install.sh
```

Maintenance

Update Web Content

Bare Metal:

Bash

```bash
sudo aegis-edit
# or
sudo cp -r /path/to/new/content/* /var/www/onion_site/
sudo chown -R www-data:www-data /var/www/onion_site
```

Uninstallation

Bare Metal:

Bash

```bash
sudo ./uninstall.sh
```

Docker:

Bash

```bash
docker-compose down
docker-compose rm -f
docker rmi onionsite-aegis  # Remove image
rm -rf data/ webroot/  # Remove volumes (WARNING: Deletes Tor keys!)
```

Security Best Practices

- Backup Tor Keys: Store encrypted backups off-site.
- Use Strong Passwords: If implementing authentication.
- Limit Access: Use firewall rules to restrict access.
- Regular Backups: Backup web content and configurations.
- Monitor Services: Use ./aegis_monitor.sh regularly.
- Review Logs: Regularly review logs for anomalies.

Support

For issues, check:
- This guide's troubleshooting section
- Logs (/var/log/tor/ or docker-compose logs)
- Service status (systemctl status or docker-compose ps)
- Configuration files (/etc/tor/torrc, /etc/nginx/)

⚠️ Remember: Logs are in RAM and will be lost on reboot. This is by design for privacy!
