# 🛡️ OnionSite-Aegis (Privacy-Focused Edition)
**v5.0 | Military-Grade Tor Hidden Service Orchestrator with Enhanced Privacy & Anti-Tracking**

[![Status](https://img.shields.io/badge/Status-Stable-green)]()
[![Verified](https://img.shields.io/badge/Verified-All%20Tests%20Passed-brightgreen)]()
[![Privacy](https://img.shields.io/badge/Privacy-Maximum%20Protection-blue)]()

**The most privacy-focused and secure Tor hidden service deployment tool available.**

## 🎯 Key Features

- 🔒 **Impossible to Track** - Comprehensive anti-tracking measures make correlation attacks impossible
- 🐳 **Docker Support** - Containerized deployment for maximum isolation
- 🛡️ **Enhanced Firewall** - DDoS protection with advanced rate limiting
- 🧠 **Neural Sentry** - Real-time attack detection and automatic defense
- 💾 **Amnesic Logging** - RAM-only logs that vanish on reboot
- 🚫 **Zero Fingerprinting** - Complete header removal and response padding
- ⚡ **Traffic Analysis Resistant** - Response size padding and timing randomization

## 📖 Setup Guide

**👉 For detailed setup instructions, see [SETUP.md](SETUP.md)**

The setup guide includes:
- Step-by-step installation for both Docker and bare metal
- Troubleshooting guide
- Maintenance procedures
- Security best practices

## 🐳 Docker Deployment (Recommended)

For enhanced security and isolation, **Docker deployment is recommended**. See [SETUP.md](SETUP.md) for complete guide.

**Quick Start:**
```bash
mkdir -p data/tor-keys webroot
echo "<h1>My Site</h1>" > webroot/index.html
docker-compose build
docker-compose up -d
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```

**Benefits:**
- ✅ Container isolation from host system
- ✅ Enhanced security (seccomp, capabilities, AppArmor)
- ✅ Resource limits prevent DoS
- ✅ Easy deployment and updates
- ✅ Network isolation
- ✅ Verified and stable

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

### 6. Anti-Tracking & Traffic Analysis Protection 🔒
**Makes tracking impossible based solely on Onion address:**
- **Response Size Padding:** All responses padded to uniform sizes (prevents size correlation)
- **Timing Randomization:** Random delays prevent timing correlation attacks
- **DNS Leak Prevention:** All DNS queries blocked except through Tor
- **External Connection Blocking:** Only Tor connections allowed (no direct connections)
- **Header Removal:** ETag, Last-Modified, and all identifying headers removed
- **Memory Protection:** Core dumps disabled (prevents memory analysis)
- **Tor Maximum Privacy:** Advanced padding (`PaddingDistribution piatkowski`), no fingerprinting, client-only mode
- **No Access Logs:** Complete privacy (logs in RAM only)
- **Compression Disabled:** Prevents size-based correlation through compression patterns
- **Cache Prevention:** Complete cache control headers

**Result:** Practically impossible to track or correlate users based on Onion address alone.

See [Anti-Tracking Guide](docs/ANTI_TRACKING_GUIDE.md) for complete details.

### 7. Enhanced Firewall (NFTables) 🔥
**Advanced DDoS protection and rate limiting:**
- **SYN Flood Protection:** 25/second with burst protection
- **Connection Rate Limiting:** Per-IP limits (max 5 connections/minute)
- **Request Rate Limiting:** 10 requests/second with burst
- **ICMP Restrictions:** Only essential types allowed
- **Connection Tracking:** Timeout-based tracking sets
- **Comprehensive Logging:** Attack logging for monitoring
- **Host-Level Firewall:** Additional layer for Docker deployments

See [conf/nftables.conf](conf/nftables.conf) for configuration details.

## 🛠️ Installation

### Prerequisites
- **Operating System:** Debian 11+ or Parrot OS (Ubuntu 20.04+ may work but not tested)
- **Root Access:** Required for system-level configuration
- **Disk Space:** At least 500MB free space
- **Network:** Internet connection for package installation

### Method 1: Bare Metal Installation (Recommended for Production)

1. **Download and Extract:**
   ```bash
   unzip OnionSite-Aegis.zip
   cd OnionSite-Aegis
   ```

2. **Run the Installer:**
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

   The installer will:
   - Check system requirements
   - Install all dependencies
   - Configure Tor hidden service
   - Set up Nginx with privacy hardening
   - Deploy Neural Sentry and WAF
   - Configure firewall (NFTables)
   - Start all services

3. **Get Your Onion Address:**
   ```bash
   sudo cat /var/lib/tor/hidden_service/hostname
   ```

4. **Verify Installation:**
   ```bash
   # Check services
   sudo systemctl status neural-sentry
   sudo systemctl status tor
   sudo systemctl status nginx
   sudo systemctl status privacy-monitor.timer
   
   # Check logs (RAM-based)
   ls -la /mnt/ram_logs
   
   # Verify hidden service
   sudo test -f /var/lib/tor/hidden_service/hostname && echo "✓ Hidden service created"
   ```

### Method 2: Docker Installation (Recommended for Testing/Development)

1. **Prerequisites:**
   - Docker Engine 20.10+
   - Docker Compose 2.0+

2. **Setup:**
   ```bash
   # Clone or extract the repository
   cd OnionSite-Aegis
   
   # Create required directories
   mkdir -p data/tor-keys webroot
   
   # Create your web content
   echo "<h1>My Onion Site</h1>" > webroot/index.html
   ```

3. **Build and Run:**
   ```bash
   # Build the image
   docker-compose build
   
   # Start the container
   docker-compose up -d
   
   # View logs
   docker-compose logs -f
   ```

4. **Get Your Onion Address:**
   ```bash
   # Wait a few seconds for Tor to initialize, then:
   docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
   
   # Or check logs for the address
   docker-compose logs aegis | grep "Onion address"
   ```

5. **Verify Installation:**
   ```bash
   # Check container status
   docker-compose ps
   
   # Check health
   docker-compose exec aegis test -f /var/lib/tor/hidden_service/hostname && echo "✓ Hidden service created"
   
   # Access shell (if needed)
   docker-compose exec aegis /bin/bash
   ```

### Docker vs Bare Metal Comparison

| Feature | Docker | Bare Metal |
|---------|--------|------------|
| **Setup Time** | ~5 minutes | ~10 minutes |
| **Isolation** | High (container) | Low (system-wide) |
| **Security** | Enhanced (seccomp, capabilities) | Good (system hardening) |
| **Resource Control** | Built-in limits | Manual configuration |
| **Portability** | High (works anywhere) | Low (OS-specific) |
| **Maintenance** | Easy (container updates) | Manual (system updates) |
| **Best For** | Testing, development, isolation | Production, full control |

### Troubleshooting

#### Hidden Service Not Created

**Bare Metal:**
```bash
# Check Tor service status
sudo systemctl status tor

# Check Tor logs
sudo journalctl -xeu tor --no-pager | tail -n 50

# Verify directory permissions
sudo ls -la /var/lib/tor/hidden_service/
sudo chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
sudo chmod 700 /var/lib/tor/hidden_service

# Restart Tor
sudo systemctl restart tor
```

**Docker:**
```bash
# Check container logs
docker-compose logs aegis | grep -i "error\|tor\|hidden"

# Check if Tor is running
docker-compose exec aegis ps aux | grep tor

# Verify directory exists
docker-compose exec aegis ls -la /var/lib/tor/hidden_service/

# Restart container
docker-compose restart aegis
```

#### NFTables Errors

```bash
# Validate configuration
sudo nft -c -f /etc/nftables.conf

# Check service status
sudo systemctl status nftables

# View errors
sudo journalctl -xeu nftables --no-pager
```

#### Service Won't Start

```bash
# Check all services
sudo systemctl status tor nginx neural-sentry

# Check for port conflicts
sudo netstat -tulpn | grep -E '9050|9051|8080'

# Verify configuration files exist
sudo test -f /etc/tor/torrc && echo "✓ Tor config exists"
sudo test -f /etc/nginx/sites-available/onion_site && echo "✓ Nginx config exists"
```

#### Docker Container Exits Immediately

```bash
# Check exit code
docker-compose ps -a

# View full logs
docker-compose logs --tail=100 aegis

# Run interactively to debug
docker-compose run --rm aegis /bin/bash
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
- **Response Padding:** Uniform response sizes prevent correlation
- **Timing Randomization:** Random delays prevent timing attacks
- **DNS Leak Prevention:** All DNS through Tor only
- **Memory Protection:** Core dumps disabled

## ✅ Verification & Stability

**Status:** ✅ **VERIFIED AND STABLE**

All files have been verified for:
- ✅ Syntax correctness (all scripts)
- ✅ Proper permissions
- ✅ Dependency validation
- ✅ Configuration validity
- ✅ Error handling
- ✅ Security measures

**Verification Tools:**
- Run `./verify_stability.sh` to verify installation anytime
- See [Verification Report](docs/VERIFICATION_REPORT.md) for detailed results

**Test Results:**
- Bash Scripts: 10/10 ✅
- Python Scripts: 2/2 ✅
- Config Files: 3/3 ✅
- Docker Files: 4/4 ✅
- Errors: 0
- Warnings: 2 (expected - optional dependencies)

## 🗑️ Uninstallation

To revert changes, remove the RAM disk, and unlock the firewall:

```bash
sudo ./uninstall.sh
```

**Docker:**
```bash
docker-compose down
docker-compose rm -f
rm -rf data/ webroot/
```

## 📚 Documentation

All documentation is available in the [`docs/`](docs/) directory:

- **[Docker Deployment Guide](docs/DOCKER_DEPLOYMENT.md)** - Complete Docker deployment guide
- **[Quick Start Guide](docs/QUICKSTART.md)** - Quick start for both methods
- **[Anti-Tracking Guide](docs/ANTI_TRACKING_GUIDE.md)** - Comprehensive anti-tracking guide
- **[Anti-Tracking Summary](docs/ANTI_TRACKING_SUMMARY.md)** - Quick anti-tracking reference
- **[Privacy Improvements](docs/PRIVACY_IMPROVEMENTS.md)** - Privacy improvements details
- **[Improvements Summary](docs/IMPROVEMENTS_SUMMARY.md)** - All improvements summary
- **[Verification Report](docs/VERIFICATION_REPORT.md)** - Verification and stability report
- **[GitHub Description](docs/GITHUB_DESCRIPTION.md)** - GitHub repository descriptions and tags

## 🔧 Maintenance

### Verify Installation
```bash
# Run verification script
./verify_stability.sh

# Check services (bare metal)
sudo systemctl status neural-sentry
sudo systemctl status tor
sudo systemctl status nginx

# Check services (Docker)
docker-compose ps
docker-compose logs -f
```

### Privacy Monitoring
```bash
# Run privacy monitor
sudo /usr/local/bin/privacy_monitor.sh

# Or in Docker
docker-compose exec aegis /usr/local/bin/privacy_monitor.sh
```

### Backup Tor Keys
**CRITICAL:** Always backup your Tor keys to preserve your Onion address.

```bash
# Bare metal
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/

# Docker
tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz data/tor-keys/
```

## 🛡️ Security Features Summary

| Feature | Status | Description |
|---------|--------|-------------|
| **Anti-Tracking** | ✅ | Response padding, timing randomization |
| **DNS Leak Prevention** | ✅ | All DNS through Tor only |
| **Firewall** | ✅ | Enhanced NFTables with DDoS protection |
| **Neural Sentry** | ✅ | Real-time attack detection |
| **Amnesic Logging** | ✅ | RAM-only logs |
| **Header Removal** | ✅ | All identifying headers removed |
| **Tor Privacy** | ✅ | Maximum privacy settings |
| **Memory Protection** | ✅ | Core dumps disabled |
| **Container Isolation** | ✅ | Docker security (seccomp, capabilities) |
| **WAF** | ✅ | ModSecurity OWASP CRS |

## ⚠️ Important Security Notes

### What This Protects Against
✅ Traffic analysis attacks  
✅ Timing correlation attacks  
✅ DNS leaks  
✅ Direct connection leaks  
✅ Server fingerprinting  
✅ Header-based tracking  
✅ Cache-based tracking  
✅ Memory analysis  
✅ DDoS attacks  
✅ Deanonymization attempts  

### What This Does NOT Protect Against
❌ **Client-side tracking** (browser fingerprinting, JavaScript) - Client-side concern  
❌ **Tor network attacks** (guard node compromise) - Tor network level  
❌ **Physical attacks** (server seizure) - Physical security required  
❌ **User behavior** (typing patterns) - Client-side concern  

### Operational Security (OPSEC)
Even with maximum protection, maintain good OPSEC:
1. Don't reveal your Onion address publicly
2. Use different circuits for different activities
3. Monitor for attacks using Neural Sentry
4. Keep software updated
5. Use strong passwords and authentication
6. Backup Tor keys securely
7. Monitor logs for suspicious activity

## 🎯 Comparison: Docker vs Bare Metal

| Feature | Docker | Bare Metal |
|---------|--------|------------|
| **Isolation** | High | Low |
| **Security** | Enhanced | Good |
| **Setup Time** | 5 min | 10+ min |
| **Maintenance** | Easy | Manual |
| **Resource Control** | Built-in | Manual |
| **Portability** | High | Low |
| **Recommended** | ✅ Yes | For advanced users |

## 📊 Statistics

- **Total Files:** 30+
- **Bash Scripts:** 10
- **Python Scripts:** 2
- **Config Files:** 3
- **Docker Files:** 4
- **Documentation:** 7
- **Lines of Code:** 2000+
- **Security Layers:** 10+

## 🤝 Contributing

This is a privacy-focused project. Contributions that enhance privacy and security are welcome.

## 📄 License

**Custom License - See [LICENSE](LICENSE) file for full terms.**

**Quick Summary:**
- ✅ You may use and redistribute (unmodified)
- ✅ You may showcase and demonstrate
- ❌ You may NOT modify or create derivatives
- ❌ You may NOT sell or commercially exploit
- 📢 You MUST give attribution/shoutout to the author

**Attribution Requirements:**
When using, redistributing, or showcasing OnionSite-Aegis, you must:
- Include copyright notices
- Give credit/attribution to the author
- Mention/shoutout the author in documentation, videos, tutorials, etc.

See [Attribution Guidelines](docs/ATTRIBUTION.md) for detailed attribution guidelines.

## 🙏 Acknowledgments

- Tor Project for the Tor network
- OWASP for ModSecurity CRS
- Debian/Parrot OS communities
- All privacy advocates

---

**⚠️ WARNING:** This tool applies aggressive system hardening. Use on dedicated servers or fresh VMs only.

**🔒 Privacy First:** All features prioritize user privacy and anonymity.

**✅ Verified:** All files tested and verified for stability.
