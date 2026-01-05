![alt text](https://github.com/ashardian/OnionSite-Aegis/blob/1128aa00d9f5cfb59266958a8838d76adf382855/Onionsite-Aegis.jpeg)


# 🛡️ OnionSite-Aegis (v7.0 Architect Edition)

> **Military-Grade Tor Hidden Service Orchestrator with Enhanced Privacy & Anti-Tracking**
> *Automated. Hardened. Anti-Forensic. Privacy-First.*

**The most privacy-focused and secure Tor hidden service deployment tool available.**

---

## ⚠️ Architect Edition Notice (v7.0)

This release introduces the **Architect Installer**, a modular deployment engine that solves critical dependency issues and adds interactive configuration.

* **Interactive Feature Selector:** Choose exactly which modules (WAF, Lua, Neural Sentry) to enable.
* **Nuclear Sanitization:** Automatically purges "ghost configurations" and conflicting binaries before deployment.
* **Anti-Forensics:** All logs are written to `tmpfs` (RAM) and vanish upon reboot.
* **Tor Bootstrap Stabilization:** New patch prevents false-positive aborts during the connection phase.

---

## 🎯 Key Features

* 🔒 **Impossible to Track** - Comprehensive anti-tracking measures make correlation attacks impossible
* 🐳 **Docker Support** - Containerized deployment for maximum isolation
* 🛡️ **Enhanced Firewall** - DDoS protection with advanced rate limiting
* 🧠 **Neural Sentry** - Real-time attack detection and automatic defense
* 💾 **Amnesic Logging** - RAM-only logs that vanish on reboot
* 🚫 **Zero Fingerprinting** - Complete header removal and response padding
* ⚡ **Traffic Analysis Resistant** - Response size padding and timing randomization

## 📖 Setup Guide

👉 For detailed setup instructions, see [SETUP.md](SETUP.md)

The setup guide includes:

* Step-by-step installation for both Docker and bare metal
* Troubleshooting guide
* Maintenance procedures
* Security best practices

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

* ✅ Container isolation from host system
* ✅ Enhanced security (seccomp, capabilities, AppArmor)
* ✅ Resource limits prevent DoS
* ✅ Easy deployment and updates
* ✅ Network isolation
* ✅ Verified and stable

## ⚠️ WARNING: HIGH SECURITY & PRIVACY MODE

This tool applies **aggressive system hardening and privacy protection**. It is designed for dedicated servers or fresh VMs (Debian 11+/Parrot OS).

* It **disables IPv6** system-wide.
* It **locks kernel pointers** (restricts `dmesg`).
* It moves all logs to **RAM (tmpfs)**. If power is cut, logs vanish forever.
* It implements **Active Circuit Killing** via the Tor Control Port.
* **Privacy-First:** Enhanced anti-fingerprinting, log sanitization, and traffic analysis protection.

---

## 🚀 Features Detail

### 1. Amnesic Logging (Forensic Counter-Measure)

Standard tools log to the hard drive. Aegis creates a 256MB RAM-disk at `/mnt/ram_logs` (or `/var/log/tor` in v7.0).

* Nginx and Tor logs are symlinked here.
* **Benefit:** Rebooting or pulling the plug makes traffic logs physically unrecoverable.
* **Privacy Log Sanitizer:** Automatically removes IPs, hostnames, and sensitive data from logs.

### 2. Neural Sentry v5.0 (Enhanced Active Defense)

A Python-based daemon (`neural_sentry.py`) that acts as a localized IDS with privacy monitoring.

* **Circuit Breaker:** Monitors circuit creation rates. If a DDoS or Deanonymization attack is detected, it signals `NEWNYM` to Tor, instantly killing all circuits.
* **Real-Time File Integrity:** Uses inotify (Linux) for instant file change detection.
* **Privacy Monitoring:** Continuously verifies Tor privacy settings (SafeLogging, etc.).

### 3. Enhanced Privacy & Security Hardening

* **Enhanced NFTables Firewall:**
* DDoS protection (SYN flood, connection rate limiting)
* Per-IP connection limits (max 5 connections/minute)
* Host-level firewall script for Docker deployments


* **Tor Sandbox:** Runs Tor with `Sandbox 1`, preventing the process from making unauthorized syscalls.
* **Nginx Privacy Headers:** Anti-fingerprinting headers, rate limiting, and request sanitization.
* **Kernel Hardening:** Extended sysctl settings for network privacy and exploit prevention.

### 4. Privacy Monitor

Automated privacy compliance checker that runs periodically:

* Verifies Tor SafeLogging is enabled
* Checks Nginx privacy headers
* Validates RAM log mounting
* Alerts on privacy misconfigurations

### 5. Web Application Firewall (WAF)

* OWASP ModSecurity Core Rule Set (CRS)
* Blocks SQL injection, XSS, and shell uploads
* Application-layer protection

### 6. Anti-Tracking & Traffic Analysis Protection 🔒

**Makes tracking impossible based solely on Onion address:**

* **Response Size Padding:** All responses padded to uniform sizes (prevents size correlation)
* **Timing Randomization:** Random delays prevent timing correlation attacks
* **DNS Leak Prevention:** All DNS queries blocked except through Tor
* **Header Removal:** ETag, Last-Modified, and all identifying headers removed
* **No Access Logs:** Complete privacy (logs in RAM only)

---

## 🛠️ Installation

### Prerequisites

* **Operating System:** Debian 11+ or Parrot OS
* **Root Access:** Required for system-level configuration
* **Disk Space:** At least 500MB free space

### Method 1: Bare Metal Installation (Architect Installer)

1. **Clone and Prepare:**
```bash
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
chmod +x install.sh

```


2. **Run the Installer:**
```bash
sudo ./install.sh

```


The v7.0 Architect Installer will prompts you to configure:
* **WAF & IPS:** Enable for high security, disable for low RAM usage.
* **Lua Padding:** Enable for anti-fingerprinting.
* **Wipe Identity:** Choose to keep existing keys or generate new ones.


3. **Get Your Onion Address:**
```bash
sudo cat /var/lib/tor/hidden_service/hostname

```


4. **Verify Installation:**
```bash
# Check services
sudo systemctl status neural-sentry
sudo systemctl status tor

# Verify hidden service
sudo test -f /var/lib/tor/hidden_service/hostname && echo "✓ Hidden service created"

```



### Method 2: Docker Installation

See [DOCKER_DEPLOYMENT.md](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/DOCKER_DEPLOYMENT.md) for full details.

```bash
# Build and Run
docker-compose build
docker-compose up -d

# Get Address
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname

```

---

## 🔧 Maintenance

### Edit Website (Securely)

Use the built-in tool to handle permissions and reloading:

```bash
sudo aegis-edit

```

### Privacy Monitoring

Check privacy status manually:

```bash
sudo /usr/local/bin/privacy_monitor.sh

```

### Backup Tor Keys

**CRITICAL:** Always backup your Tor keys to preserve your Onion address.

```bash
# Bare metal
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/

# Docker
tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz data/tor-keys/

```

### Log Sanitization

Manually sanitize RAM logs if needed:

```bash
sudo /usr/local/bin/privacy_log_sanitizer.py /mnt/ram_logs

```

---

## 📚 Documentation

All documentation is available in the [`docs/`](https://github.com/ashardian/OnionSite-Aegis/tree/b9af589f979a265183835afe9004af87c05fa2f1/docs) directory:

* **[Docker Deployment Guide](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/DOCKER_DEPLOYMENT.md)** - Complete Docker deployment guide
* **[Quick Start Guide](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/QUICKSTART.md)** - Quick start for both methods
* **[Anti-Tracking Guide](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/ANTI_TRACKING_GUIDE.md)** - Comprehensive anti-tracking guide
* **[Verification Report](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/VERIFICATION_REPORT.md)** - Verification and stability report

---

## 🎯 Comparison: Docker vs Bare Metal

| Feature | Docker | Bare Metal |
| --- | --- | --- |
| **Isolation** | High | Low |
| **Security** | Enhanced | Good |
| **Setup Time** | 5 min | 10+ min |
| **Maintenance** | Easy | Manual |
| **Resource Control** | Built-in | Manual |
| **Portability** | High | Low |
| **Recommended** | ✅ Yes | For advanced users |

## 🤝 Contributing

This is a privacy-focused project. Contributions that enhance privacy and security are welcome.

## 📄 License

**Custom License - See [LICENSE](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/LICENSE) file for full terms.**

**Quick Summary:**

* ✅ You may use and redistribute (unmodified)
* ❌ You may NOT modify or create derivatives
* 📢 You MUST give attribution/shoutout to the author

**Attribution Requirements:**
When using, redistributing, or showcasing OnionSite-Aegis, you must include copyright notices and give credit to the author. See [Attribution Guidelines](https://github.com/ashardian/OnionSite-Aegis/blob/b9af589f979a265183835afe9004af87c05fa2f1/docs/ATTRIBUTION.md).

---

**⚠️ WARNING:** This tool applies aggressive system hardening. Use on dedicated servers or fresh VMs only.
