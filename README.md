# 🛡️ OnionSite-Aegis (Privacy-Focused Edition)
**v5.0 | Military-Grade Tor Hidden Service Orchestrator with Enhanced Privacy**

## 🐳 Docker Deployment (Recommended)

For enhanced security and isolation, **Docker deployment is recommended**. See [DOCKER_DEPLOYMENT.md](DOCKER_DEPLOYMENT.md) for complete guide.

**Quick Start:**
```bash
mkdir -p data/tor-keys webroot
echo "<h1>My Site</h1>" > webroot/index.html
docker-compose up -d
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```

**Benefits:**
- ✅ Container isolation from host system
- ✅ Enhanced security (seccomp, capabilities, AppArmor)
- ✅ Resource limits prevent DoS
- ✅ Easy deployment and updates
- ✅ Network isolation

## ⚠️ WARNING: HIGH SECURITY & PRIVACY MODE
This tool applies **aggressive system hardening and privacy protection**. It is designed for dedicated servers or fresh VMs (Debian 11+/Parrot OS).
- It **disables IPv6** system-wide.
- It **locks kernel pointers** (restricts `dmesg`).
- It moves all logs to **RAM (tmpfs)**. If power is cut, logs vanish forever.
- It implements **Active Circuit Killing** via the Tor Control Port.
- **Privacy-First:** Enhanced anti-fingerprinting, log sanitization, and traffic analysis protection.

## 🚀 Features

### 1. Amnesic Logging (Forensic Counter-Measure)
Standard tools log to the hard drive. Aegis creates a 256MB RAM-disk at `/mnt/ram_logs`.
- Nginx and Tor logs are symlinked here.
- **Benefit:** Rebooting or pulling the plug makes traffic logs physically unrecoverable.
- **Privacy Log Sanitizer:** Automatically removes IPs, hostnames, and sensitive data from logs.

### 2. Neural Sentry v5.0 (Enhanced Active Defense)
A Python-based daemon (`neural_sentry.py`) that acts as a localized IDS with privacy monitoring.
- **Circuit Breaker:** Monitors circuit creation rates with dual-threshold detection (1-minute and 10-second burst windows). If a DDoS or Deanonymization attack (Guard forcing) is detected, it signals `NEWNYM` to Tor, instantly killing all circuits.
- **Real-Time File Integrity:** Uses inotify (Linux) for instant file change detection. Falls back to efficient polling if unavailable. Detects suspicious file types (PHP, shell scripts, executables).
- **Privacy Monitoring:** Continuously verifies Tor privacy settings (SafeLogging, etc.).
- **Enhanced Error Handling:** Automatic reconnection, graceful shutdown, and health monitoring.

### 3. Enhanced Privacy & Security Hardening
- **Enhanced NFTables Firewall:** 
  - DDoS protection (SYN flood, connection rate limiting)
  - Per-IP connection limits (max 5 connections/minute)
  - ICMP restrictions
  - Comprehensive logging
  - Host-level firewall script for Docker deployments
- **Tor Sandbox:** Runs Tor with `Sandbox 1`, preventing the process from making unauthorized syscalls.
- **Enhanced Tor Privacy:** Connection padding, circuit padding, guard node optimization, and reduced connection metadata.
- **Nginx Privacy Headers:** Anti-fingerprinting headers, rate limiting, and request sanitization.
- **Kernel Hardening:** Extended sysctl settings for network privacy and exploit prevention.
- **Docker Security:** Seccomp profiles, minimal capabilities, AppArmor, resource limits, network isolation.

### 4. Privacy Monitor (New)
Automated privacy compliance checker that runs every 6 hours:
- Verifies Tor SafeLogging is enabled
- Checks Nginx privacy headers
- Validates RAM log mounting
- Monitors file permissions
- Alerts on privacy misconfigurations

### 5. Web Application Firewall (WAF)
- OWASP ModSecurity Core Rule Set (CRS)
- Blocks SQL injection, XSS, and shell uploads
- Application-layer protection

## 🛠️ Installation

1. **Unzip the suite:**
   ```bash
   unzip OnionSite-Aegis.zip
   cd OnionSite-Aegis


2. **Run the Installer:**

```bash
sudo chmod +x install.sh
sudo ./install.sh
```

3. **Verify Status:**

```bash
systemctl status neural-sentry
systemctl status privacy-monitor.timer
ls -la /mnt/ram_logs
```

## 🧠 Usage

**Web Root:** Place your site files in `/var/www/onion_site`.

**Onion Address:** Found in `/var/lib/tor/hidden_service/hostname`.

**Logs:** View logs at `/mnt/ram_logs/` (Remember: these are temporary and in RAM).

**Privacy Monitoring:** Check privacy status:
```bash
sudo /usr/local/bin/privacy_monitor.sh
```

**Log Sanitization:** Manually sanitize logs:
```bash
sudo /usr/local/bin/privacy_log_sanitizer.py /mnt/ram_logs
```

## 🔒 Privacy Features

- **Anti-Fingerprinting:** Server tokens disabled, identifying headers removed
- **Rate Limiting:** Prevents traffic analysis through connection patterns
- **Log Sanitization:** Automatic removal of IPs, hostnames, and sensitive data
- **Enhanced Tor Privacy:** Connection padding, circuit padding, optimized guard selection
- **Request Anonymization:** Minimal logging, no access logs by default
- **Real-Time Monitoring:** Instant detection of privacy violations

🗑️ Uninstallation
To revert changes, remove the RAM disk, and unlock the firewall:

Bash

sudo ./uninstall.sh
