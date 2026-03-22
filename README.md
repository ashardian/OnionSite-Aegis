![OnionSite-Aegis](https://github.com/ashardian/OnionSite-Aegis/blob/1128aa00d9f5cfb59266958a8838d76adf382855/Onionsite-Aegis.jpeg)

# 🛡️ OnionSite-Aegis (v10.0 Bare Metal Edition)

> **Military-Grade Tor Hidden Service Orchestrator**
> *Automated. Hardened. Anti-Forensic. Privacy-First.*

**The most privacy-focused and secure Tor hidden service deployment tool available.**

---

## ⚠️ v10.0 Notice — Docker Support Removed

Starting with v10.0, **Docker support has been permanently removed.**

Docker was found to be fundamentally incompatible with Aegis's core security features:

- **sysctl kernel hardening** cannot be applied inside a container without `--privileged`, which defeats isolation entirely.
- **NFTables firewall** conflicts with Docker's own iptables/nftables management on the host.
- **Tor Sandbox mode** (`Sandbox 1`) crashes inside Docker due to seccomp profile conflicts.
- **tmpfs RAM logging** behaves differently in containers, causing permission failures.

Bare metal deployment gives you **full, direct control** over every layer of the stack — which is exactly what a privacy-hardened hidden service requires.

---

## 🎯 Key Features

- 🔒 **Impossible to Track** — Comprehensive anti-tracking measures make correlation attacks extremely difficult
- 🛡️ **Hardened Firewall** — Balanced NFTables ruleset blocks attacks while maintaining Tor connectivity
- 🧠 **Neural Sentry** — Real-time attack detection and automatic circuit-killing defense
- 💾 **Amnesic Logging** — RAM-only logs that vanish on reboot (anti-forensics)
- 🚫 **Zero Fingerprinting** — Complete header removal and response padding
- ⚡ **Traffic Analysis Resistant** — Response size padding and timing randomization
- 🖥️ **Live System HUD** — Real-time terminal dashboard for monitoring threats
- 🔥 **WAF Protection** — OWASP ModSecurity Core Rule Set blocks SQLi, XSS, and more
- 🔑 **Kernel Hardening** — Extended sysctl settings for network privacy and exploit prevention

---

## 📖 Setup Guide

👉 For full installation instructions, see [SETUP.md](SETUP.md)

---

## 🚀 Quick Start

```bash
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
chmod +x install.sh
sudo ./install.sh
```

The **v10.0 Architect Installer** will prompt you to configure:

- **WAF & IPS** — Enable for high security, disable for low RAM usage
- **Lua Padding** — Enable for anti-fingerprinting
- **SSH Access** — CRITICAL: Enable this if using a Cloud VPS (AWS/DigitalOcean) to prevent lockout
- **Wipe Identity** — Choose to keep existing Tor keys or generate a new address

After installation, get your onion address:

```bash
sudo cat /var/lib/tor/hidden_service/hostname
```

---

## ⚠️ System Requirements

- **OS:** Debian 11+ (Bookworm/Trixie), Kali Linux, or Parrot OS
- **Access:** Root required
- **Disk:** 500MB minimum free space
- **Note:** Designed for dedicated servers or fresh VMs only

---

## 🚀 Features Detail

### 1. Amnesic Logging (Anti-Forensics)

All logs are written to a RAM-disk (`tmpfs`) at `/var/log/tor`. Nginx and Tor logs are symlinked here. Rebooting or pulling the plug makes traffic logs physically unrecoverable. A **Privacy Log Sanitizer** also strips IPs, hostnames, and sensitive data from logs in real time.

### 2. Neural Sentry v5.0 (Active Defense)

A Python daemon (`neural_sentry.py`) acting as a localized IDS:

- **Circuit Breaker** — Monitors circuit creation rates. On DDoS or deanonymization attack detection, signals `NEWNYM` to Tor, killing all circuits instantly.
- **File Integrity** — Uses inotify for instant detection of unauthorized file changes.
- **Privacy Monitor** — Continuously verifies Tor privacy settings (SafeLogging, etc.).

### 3. Hardened NFTables Firewall

- DDoS protection (SYN flood, connection rate limiting)
- Per-IP connection limits
- Blocks all unsolicited input (port scanning protection)
- Optional SSH safety valve for VPS deployments

### 4. Anti-Tracking & Traffic Analysis Protection

- **Response Size Padding** — All responses padded to uniform sizes (defeats size correlation)
- **Timing Randomization** — Random delays prevent timing correlation attacks
- **DNS Leak Prevention** — All DNS queries blocked except through Tor
- **Header Removal** — ETag, Last-Modified, and all identifying headers stripped

### 5. Web Application Firewall (WAF)

- OWASP ModSecurity Core Rule Set (CRS)
- Blocks SQL injection, XSS, and shell uploads
- Application-layer protection via Nginx

### 6. Kernel Hardening

Direct `sysctl` hardening applied at the kernel level — only possible on bare metal:

- Network privacy settings
- Kernel pointer restrictions
- Exploit mitigation flags

---

## 🔧 Maintenance

### Edit Website Content

```bash
sudo aegis-edit
```

### Monitor System Health

```bash
sudo ./aegis_monitor.sh
```

### Check Privacy Status

```bash
sudo /usr/local/bin/privacy_monitor.sh
```

### Backup Tor Keys (CRITICAL)

⚠️ Losing your keys means losing your onion address forever.

```bash
# Built-in tool (recommended)
sudo ./SAVE_MY_ONION.sh

# Manual backup
sudo tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz /var/lib/tor/hidden_service/
```

### Uninstall

```bash
sudo ./uninstall.sh
```

---

## 📚 Documentation

All documentation is in the [`docs/`](docs/) directory:

- [Quick Start Guide](docs/QUICKSTART.md)
- [Anti-Tracking Guide](docs/ANTI_TRACKING_GUIDE.md)
- [Privacy Improvements](docs/PRIVACY_IMPROVEMENTS.md)
- [Verification Report](docs/VERIFICATION_REPORT.md)

---

## 📋 Changelog

### v10.0 — Bare Metal Edition
- 🗑️ **Removed Docker support** — Docker was fundamentally incompatible with Aegis's core security stack (sysctl kernel hardening, NFTables, Tor Sandbox mode, tmpfs RAM logging). Bare metal only from this version forward.
- 🔍 **`detect_tor_service()`** — New function that auto-detects whether the system uses `tor` or `tor@default` as the systemd service name. Fixes silent failures on Debian systems where Tor runs under a different unit name.
- 📁 **`INSTALL_DIR` path fix** — Changed from `$(pwd)` to `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`. The installer now correctly resolves its own location even when run from a different working directory (e.g. `sudo /opt/OnionSite-Aegis/install.sh`).
- 🛡️ **`set -E` added** — The ERR trap now fires inside functions and subshells, not just the top level. Prevents errors from being silently swallowed deep in the script.
- ⏱️ **Privacy monitor systemd timer** — Privacy compliance checks now run automatically on a schedule as a proper `systemd` timer unit, instead of requiring manual execution.
- 🧹 **Uninstaller updated** — `uninstall.sh` now correctly removes all systemd units added in v9.0+ (`privacy-monitor.timer`, `traffic-protection.service`, etc.) and handles both NFTables and UFW on cleanup.

### v9.0 — Architect Edition
- Integrated advanced NFTables balanced firewall (fixes Tor connectivity issues from v7/v8)
- SSH Safety Valve — interactive prompt prevents Cloud VPS lockout
- Post-install dashboard with live system HUD (`aegis_monitor.sh`)
- Fixed all variable initialization crashes
- Full RAM-disk compliance for anti-forensic logging

### v7.0 / v8.0
- Initial Docker + bare metal dual deployment
- Neural Sentry v1–v4
- Basic NFTables firewall (aggressive rate limiting — caused Tor blockages)

---

## 🤝 Contributing

Privacy-focused contributions are welcome. See [ATTRIBUTION.md](ATTRIBUTION.md) for credit guidelines.

## 📄 License

**MIT License — See [LICENSE](LICENSE) for full terms.**

Attribution is required when using, redistributing, or showcasing OnionSite-Aegis. See [ATTRIBUTION.md](ATTRIBUTION.md).

---

**⚠️ WARNING:** This tool applies aggressive system hardening. Use on dedicated servers or fresh VMs only. The author is not responsible for illegal use of this software.
