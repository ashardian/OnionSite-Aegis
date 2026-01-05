
# 🚀 OnionSite-Aegis Setup Guide (v7.0 Architect)

Complete setup instructions for both Docker and bare metal deployments.

## Table of Contents

1. Quick Start
2. Bare Metal Installation
3. Docker Installation
4. Post-Installation
5. Troubleshooting
6. Maintenance

---

## Quick Start

### Docker (Fastest)

```bash
mkdir -p data/tor-keys webroot
echo "<h1>My Site</h1>" > webroot/index.html
docker-compose build && docker-compose up -d
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname

```

### Bare Metal (Architect Installer)

```bash
sudo chmod +x install.sh
sudo ./install.sh
# Follow the interactive prompts to configure WAF, IPS, and Lua padding
sudo cat /var/lib/tor/hidden_service/hostname

```

---

## Bare Metal Installation

### Step 1: Prerequisites

**System Requirements:**

* Debian 11+ (Bookworm/Trixie), Kali Linux, or Parrot OS (Ubuntu 20.04+ may work)
* Root/sudo access
* At least 500MB free disk space
* Internet connection

**Verify System:**

```bash
# Check OS
cat /etc/os-release

# Check disk space
df -h /

# Check if running as root
whoami  # Should be 'root' or use sudo

```

### Step 2: Download and Extract

```bash
# If downloaded as zip
unzip OnionSite-Aegis.zip
cd OnionSite-Aegis

# Or if cloned from git
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis

```

### Step 3: Run Installer (v7.0 Architect)

The v7.0 installer is interactive. It will ask you to customize your security stack.

```bash
# Make executable
sudo chmod +x install.sh

# Run installer
sudo ./install.sh

```

**Configuration Prompts:**
You will be asked to enable or disable the following:

1. **ModSecurity WAF:** [y/N] (Recommended for dynamic sites)
2. **Lua Response Padding:** [y/N] (Recommended for anti-fingerprinting)
3. **Neural Sentry IPS:** [y/N] (Active defense daemon)
4. **Privacy Monitor:** [y/N] (Periodic compliance checks)
5. **Wipe Identity:** If keys exist, choose to keep them or securely wipe them.

**What the v7.0 installer does:**

1. ✅ **Nuclear Sanitization:** Purges "ghost configs" and conflicting modules.
2. ✅ **Dependency Check:** Installs Tor, Nginx, NDK, NFTables, Python packages.
3. ✅ **Ram-Based Logging:** Configures `tmpfs` for `/var/log/tor` (Anti-Forensics).
4. ✅ **Kernel Hardening:** Applies `sysctl` security rules.
5. ✅ **Firewall Lock:** Applies whitelist-only NFTables rules.
6. ✅ **Tor Hardening:** Configures Sandbox, V3 Hidden Service, and Privacy directives.
7. ✅ **Nginx Architecture:** Enforces correct load order (NDK -> Lua -> WAF).
8. ✅ **Active Defense:** Installs Neural Sentry and ModSecurity (if selected).
9. ✅ **Stabilization:** Uses patched error trapping for reliable bootstrapping.

**Expected Output:**

```
=== ONIONSITE-AEGIS ARCHITECT v7.0 ===
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
----------------------------------------------------------------
Edit your site: sudo aegis-edit
================================================================

```

### Step 4: Verify Installation

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

### Step 5: Add Your Content

Use the built-in secure editor to avoid permission issues:

```bash
sudo aegis-edit

```

*Or manually:*

```bash
# Place your website files here
sudo cp -r /path/to/your/website/* /var/www/onion_site/

# Set correct permissions
sudo chown -R www-data:www-data /var/www/onion_site
sudo find /var/www/onion_site -type f -exec chmod 644 {} \;
sudo find /var/www/onion_site -type d -exec chmod 755 {} \;

```

---

## Docker Installation

### Step 1: Prerequisites

**Required:**

* Docker Engine 20.10+ (`docker --version`)
* Docker Compose 2.0+ (`docker-compose --version`)

**Install Docker (if needed):**

```bash
# Debian/Ubuntu
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt-get install docker-compose-plugin

```

### Step 2: Prepare Directories

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

### Step 3: Build and Run

```bash
# Build the Docker image
docker-compose build

# Start the container
docker-compose up -d

# View logs (wait for "Onion address" message)
docker-compose logs -f aegis

```

**Expected Output:**

```
[AEGIS] Starting OnionSite-Aegis v7.0 (Docker)
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

### Step 4: Get Your Onion Address

```bash
# Method 1: From container
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname

# Method 2: From logs
docker-compose logs aegis | grep "Onion address"

# Method 3: From host (if volume mounted)
cat data/tor-keys/hostname

```

### Step 5: Verify Installation

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

### Step 6: Update Web Content

```bash
# Edit files in webroot directory
nano webroot/index.html

# Changes are reflected immediately (volume is mounted)
# No need to restart container

```

---

## Post-Installation

### Access Your Site

1. **Install Tor Browser:** [https://www.torproject.org/download/](https://www.torproject.org/download/)
2. **Open Tor Browser**
3. **Navigate to:** `http://your-onion-address.onion`
* Replace `your-onion-address.onion` with the address from `/var/lib/tor/hidden_service/hostname`



### Important Files and Directories

**Bare Metal:**

* Onion Address: `/var/lib/tor/hidden_service/hostname`
* Web Root: `/var/www/onion_site`
* Logs: `/var/log/tor/` or `/mnt/ram_logs/` (RAM - volatile!)
* Tor Config: `/etc/tor/torrc`
* Nginx Config: `/etc/nginx/sites-available/onion_site`

**Docker:**

* Onion Address: `data/tor-keys/hostname` (on host)
* Web Root: `webroot/` (on host)
* Logs: Inside container at `/mnt/ram_logs/` (RAM - volatile!)
* Container Name: `onionsite-aegis`

### Backup Tor Keys (CRITICAL!)

**⚠️ WARNING:** Losing your Tor keys means losing your Onion address forever!

**Bare Metal:**

```bash
# Create backup
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/

# Store backup securely (encrypted, off-site)

```

**Docker:**

```bash
# Backup the keys directory
tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz data/tor-keys/

# Store backup securely

```

### Monitoring

**Check Service Status:**

```bash
# Bare Metal
sudo systemctl status tor nginx neural-sentry

# Docker
docker-compose ps
docker-compose logs --tail=50 aegis

```

**Privacy Monitoring:**

```bash
# Bare Metal
sudo /usr/local/bin/privacy_monitor.sh

# Docker
docker-compose exec aegis /usr/local/bin/privacy_monitor.sh

```

**View Logs:**

```bash
# Bare Metal (RAM logs - temporary!)
sudo tail -f /var/log/tor/notices.log
sudo tail -f /var/log/nginx/access.log

# Docker
docker-compose logs -f aegis

```

---

## Troubleshooting

### Hidden Service Not Created

**Symptoms:**

* No `hostname` file in `/var/lib/tor/hidden_service/`
* Onion address shows "Pending..." or empty

**Bare Metal Fix:**

```bash
# 1. Check Tor service
sudo systemctl status tor

# 2. Check Tor logs
sudo tail -f /var/log/tor/notices.log

# 3. Verify directory permissions
sudo ls -la /var/lib/tor/hidden_service/
sudo chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
sudo chmod 700 /var/lib/tor/hidden_service

# 4. Check Tor configuration
sudo grep -i "HiddenService" /etc/tor/torrc

# 5. Restart Tor
sudo systemctl restart tor
sleep 10
sudo cat /var/lib/tor/hidden_service/hostname

```

**Docker Fix:**

```bash
# 1. Check container logs
docker-compose logs aegis | grep -i "error\|tor\|hidden"

# 2. Check if Tor process is running
docker-compose exec aegis ps aux | grep tor

# 3. Verify directory exists
docker-compose exec aegis ls -la /var/lib/tor/hidden_service/

# 4. Check Tor configuration
docker-compose exec aegis cat /etc/tor/torrc | grep -i "HiddenService"

# 5. Restart container
docker-compose restart aegis
sleep 15
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname

```

### NFTables Errors

**Symptoms:**

* `Job for nftables.service failed`
* Firewall not working

**Fix:**

```bash
# 1. Validate configuration
sudo nft -c -f /etc/nftables.conf

# 2. Check for syntax errors
sudo nft list ruleset

# 3. If errors, check the config file
sudo nano /etc/nftables.conf

# 4. Restart service
sudo systemctl restart nftables
sudo systemctl status nftables

```

### Service Won't Start (Nginx/Lua Error)

**Symptoms:**

* `undefined symbol: ndk_set_var_value`
* Nginx fails to start

**Fix (v7.0 Architect):**
This is usually caused by incorrect module load order. Rerun the installer to apply the automatic fix:

```bash
sudo ./install.sh

```

Or manually fix load order:

```bash
sudo ln -sf /usr/share/nginx/modules-available/mod-http-ndk.conf /etc/nginx/modules-enabled/10-ndk.conf
sudo ln -sf /usr/share/nginx/modules-available/mod-http-lua.conf /etc/nginx/modules-enabled/20-lua.conf
sudo systemctl restart nginx

```

### Docker Container Exits Immediately

**Fix:**

```bash
# 1. Check exit code
docker-compose ps -a

# 2. View logs
docker-compose logs aegis

# 3. Run interactively
docker-compose run --rm aegis /bin/bash

# 4. Check for permission issues
docker-compose exec aegis ls -la /var/lib/tor/

# 5. Rebuild if needed
docker-compose down
docker-compose build --no-cache
docker-compose up -d

```

### Can't Access Site

**Checklist:**

1. ✅ Tor Browser is installed and running
2. ✅ Using correct Onion address (check `hostname` file)
3. ✅ Using `http://` not `https://` (unless you configured SSL)
4. ✅ Tor Browser is connected to Tor network
5. ✅ Services are running (check status)

**Debug:**

```bash
# Test from inside container/host
curl -v http://127.0.0.1:8080

# Check Nginx is listening
sudo netstat -tulpn | grep 80  # Bare Metal
docker-compose exec aegis netstat -tulpn | grep 80  # Docker

# Check Nginx logs
sudo tail -f /var/log/nginx/error.log  # Bare Metal
docker-compose logs aegis | grep nginx  # Docker

```

---

## Maintenance

### Update Web Content

**Bare Metal:**

```bash
sudo aegis-edit
# or
sudo cp -r /path/to/new/content/* /var/www/onion_site/
sudo chown -R www-data:www-data /var/www/onion_site

```

**Docker:**

```bash
# Just edit files in webroot/ directory
nano webroot/index.html
# Changes are immediate (volume mounted)

```

### Update Configuration

**Tor Config (Bare Metal):**

```bash
sudo nano /etc/tor/torrc
sudo systemctl restart tor

```

**Nginx Config (Bare Metal):**

```bash
sudo nano /etc/nginx/sites-available/onion_site
sudo nginx -t  # Test configuration
sudo systemctl reload nginx

```

**Docker:**

```bash
# Edit docker-compose.yml or Dockerfile
# Rebuild and restart
docker-compose down
docker-compose build
docker-compose up -d

```

### Backup and Restore

**Backup:**

```bash
# Backup Tor keys (CRITICAL!)
sudo tar -czf backup-$(date +%Y%m%d).tar.gz \
    /var/lib/tor/hidden_service/ \
    /etc/tor/torrc \
    /etc/nginx/sites-available/onion_site \
    /var/www/onion_site

```

**Restore:**

```bash
# Extract backup
sudo tar -xzf backup-YYYYMMDD.tar.gz -C /

# Restart services
sudo systemctl restart tor nginx

```

### Log Rotation

**Note:** Logs are in RAM (`/mnt/ram_logs/` or `/var/log/tor/`), so they don't persist. If you need persistent logs:

```bash
# Create persistent log directory (defeats amnesic logging!)
sudo mkdir -p /var/log/aegis
sudo ln -sf /var/log/aegis/nginx /var/log/nginx
sudo ln -sf /var/log/aegis/tor /var/log/tor

```

### Uninstallation

**Bare Metal:**

```bash
sudo ./uninstall.sh

```

**Docker:**

```bash
docker-compose down
docker-compose rm -f
docker rmi onionsite-aegis  # Remove image
rm -rf data/ webroot/  # Remove volumes (WARNING: Deletes Tor keys!)

```

---

## Security Best Practices

1. **Backup Tor Keys:** Store encrypted backups off-site
2. **Keep Updated:** Regularly update system packages
3. **Monitor Logs:** Check for suspicious activity
4. **Use Strong Passwords:** If implementing authentication
5. **Limit Access:** Use firewall rules to restrict access
6. **Regular Backups:** Backup web content and configurations
7. **Monitor Services:** Set up monitoring/alerting
8. **Review Logs:** Regularly review logs for anomalies

---

## Support

For issues, check:

1. This guide's troubleshooting section
2. Logs (`/var/log/tor/` or `docker-compose logs`)
3. Service status (`systemctl status` or `docker-compose ps`)
4. Configuration files (`/etc/tor/torrc`, `/etc/nginx/`)

---

**⚠️ Remember:** Logs are in RAM and will be lost on reboot. This is by design for privacy!
