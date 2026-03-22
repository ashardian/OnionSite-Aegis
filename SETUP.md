# 🚀 OnionSite-Aegis Setup Guide (v10.0 Bare Metal Edition)

Complete setup instructions for bare metal deployment.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Post-Installation](#post-installation)
5. [Troubleshooting](#troubleshooting)
6. [Maintenance](#maintenance)

---

## Quick Start

```bash
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
chmod +x install.sh
sudo ./install.sh
sudo cat /var/lib/tor/hidden_service/hostname
```

---

## Prerequisites

**System Requirements:**

- Debian 11+ (Bookworm/Trixie), Kali Linux, or Parrot OS
- Root/sudo access
- At least 500MB free disk space
- Internet connection
- Dedicated server or fresh VM (not a shared host)

**Verify your system:**

```bash
cat /etc/os-release
df -h /
whoami  # Must be root or use sudo
```

---

## Installation

### Step 1: Download

```bash
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
```

Or if downloaded as a zip:

```bash
unzip OnionSite-Aegis.zip
cd OnionSite-Aegis
```

### Step 2: Run the Architect Installer

```bash
chmod +x install.sh
sudo ./install.sh
```

The installer is interactive and will ask you to configure:

1. **ModSecurity WAF** `[Y/n]` — Recommended for production sites
2. **Lua Response Padding** `[Y/n]` — Recommended for anti-fingerprinting
3. **Neural Sentry IPS** `[Y/n]` — Active defense daemon
4. **Privacy Monitor** `[Y/n]` — Periodic compliance checks
5. **Traffic Analysis Protection** `[Y/n]` — Advanced timing randomization
6. **SSH Access** `[y/N]` — **CRITICAL: Enable this if on a Cloud VPS (AWS/DigitalOcean/Linode) to prevent lockout**

**What the installer does:**

- ✅ Nuclear Sanitization — Purges ghost configs and conflicting modules
- ✅ Dependency Install — Tor, Nginx, NFTables, Python packages
- ✅ RAM Logging — Configures tmpfs at `/var/log/tor` (anti-forensics)
- ✅ Balanced Firewall — NFTables rules that allow Tor while blocking attacks
- ✅ Tor Hardening — V3 Hidden Service, Sandbox, Privacy directives
- ✅ Nginx Architecture — Correct module load order (NDK → Lua → WAF)
- ✅ Active Defense — Neural Sentry and ModSecurity (if selected)
- ✅ SSH Safety — Whitelist SSH in firewall if selected

### Step 3: Get Your Onion Address

```bash
sudo cat /var/lib/tor/hidden_service/hostname
```

### Step 4: Verify Installation

```bash
# Check all services
sudo systemctl status tor
sudo systemctl status nginx
sudo systemctl status neural-sentry

# Verify hidden service files exist
sudo ls -la /var/lib/tor/hidden_service/
# Should show: hostname, hs_ed25519_public_key, hs_ed25519_secret_key

# Confirm RAM logs are active
sudo mount | grep tmpfs | grep tor
```

### Step 5: Add Your Website Content

Use the built-in secure editor:

```bash
sudo aegis-edit
```

Or manually:

```bash
sudo cp -r /path/to/your/website/* /var/www/onion_site/
sudo chown -R www-data:www-data /var/www/onion_site
sudo find /var/www/onion_site -type f -exec chmod 644 {} \;
sudo find /var/www/onion_site -type d -exec chmod 755 {} \;
```

---

## Post-Installation

### Access Your Site

1. Download Tor Browser from [https://www.torproject.org/download/](https://www.torproject.org/download/)
2. Open Tor Browser
3. Navigate to `http://your-address.onion`

### Important File Locations

| File | Path |
|------|------|
| Onion Address | `/var/lib/tor/hidden_service/hostname` |
| Tor Keys | `/var/lib/tor/hidden_service/` |
| Web Root | `/var/www/onion_site` |
| Tor Logs (RAM) | `/var/log/tor/` |
| Tor Config | `/etc/tor/torrc` |
| Nginx Config | `/etc/nginx/sites-available/onion_site` |

### Backup Tor Keys (CRITICAL)

⚠️ **Losing your keys = losing your onion address forever. There is no recovery.**

```bash
# Built-in backup tool (recommended)
sudo ./SAVE_MY_ONION.sh

# Manual backup
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/
```

Store the backup encrypted and off-site.

---

## Troubleshooting

### Hidden Service Not Created

**Symptoms:** No `hostname` file, or address shows empty.

```bash
# 1. Check Tor status
sudo systemctl status tor

# 2. Check Tor logs
sudo tail -f /var/log/tor/notices.log

# 3. Fix permissions
sudo chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
sudo chmod 700 /var/lib/tor/hidden_service

# 4. Restart Tor
sudo systemctl restart tor
sleep 10
sudo cat /var/lib/tor/hidden_service/hostname
```

### SSH Lockout / NFTables Errors

**Symptoms:** Cannot SSH in after install, or `nftables.service failed`.

Access your server via your VPS provider's web console (VNC), then:

```bash
# Emergency: flush all firewall rules
sudo nft flush ruleset

# Re-run installer and select YES for SSH Access
sudo ./install.sh
```

### Nginx Fails to Start (Lua Error)

**Symptoms:** `undefined symbol: ndk_set_var_value`

This is a module load order issue. Re-running the installer fixes it automatically:

```bash
sudo ./install.sh
```

Or fix manually:

```bash
sudo ln -sf /usr/share/nginx/modules-available/mod-http-ndk.conf /etc/nginx/modules-enabled/10-ndk.conf
sudo ln -sf /usr/share/nginx/modules-available/mod-http-lua.conf /etc/nginx/modules-enabled/20-lua.conf
sudo systemctl restart nginx
```

### Can't Access Site via Tor Browser

Checklist:

- ✅ Tor Browser is open and connected
- ✅ Using `http://` not `https://`
- ✅ Onion address is correct (check `hostname` file)
- ✅ All services are running (`systemctl status tor nginx`)

```bash
# Test Nginx is responding locally
curl -v http://127.0.0.1:80

# Check what ports Nginx is listening on
sudo ss -tulpn | grep nginx
```

---

## Maintenance

### Edit Website

```bash
sudo aegis-edit
```

### Monitor System (Live HUD)

```bash
sudo ./aegis_monitor.sh
```

### Check Privacy Compliance

```bash
sudo /usr/local/bin/privacy_monitor.sh
```

### View Logs

```bash
# Tor logs (RAM — lost on reboot by design)
sudo tail -f /var/log/tor/notices.log

# Nginx logs
sudo tail -f /var/log/nginx/access.log
```

### Update Tor Config

```bash
sudo nano /etc/tor/torrc
sudo systemctl restart tor
```

### Update Nginx Config

```bash
sudo nano /etc/nginx/sites-available/onion_site
sudo nginx -t
sudo systemctl reload nginx
```

### Full Backup

```bash
sudo tar -czf aegis-backup-$(date +%Y%m%d).tar.gz \
    /var/lib/tor/hidden_service/ \
    /etc/tor/torrc \
    /etc/nginx/sites-available/onion_site \
    /var/www/onion_site
```

### Uninstall

```bash
sudo ./uninstall.sh
```

---

## Security Best Practices

- **Back up Tor keys** — Store encrypted, off-site, immediately after installation
- **Use a dedicated machine** — Do not run other services on the same host
- **Keep system updated** — `sudo apt update && sudo apt upgrade` regularly
- **Monitor regularly** — Run `./aegis_monitor.sh` to check for threats
- **Never disable RAM logging** — Persistent logs defeat the anti-forensics design
- **Enable SSH safety valve** — Only if you need remote access via VPS console

---

⚠️ **Remember:** Logs are in RAM and will be lost on reboot. This is by design for privacy.
