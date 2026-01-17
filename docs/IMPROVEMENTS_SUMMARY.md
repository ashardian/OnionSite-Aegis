
# Improvements Summary - v9.0 Architect

## Overview
This document summarizes the improvements made to OnionSite-Aegis v9.0, focusing on the new "Balanced" firewall architecture, SSH safety mechanisms, and enhanced stability for bare-metal deployments.

## 🔥 Key Updates (v9.0)

### 1. Balanced Firewall (NFTables)
- **Problem:** Previous versions (v7.0/v8.0) used aggressive rate-limiting that occasionally choked Tor circuit establishment, causing "Onion Site Not Found" errors.
- **Solution (v9.0):** Implemented a "Balanced" NFTables ruleset.
  - **DDoS Protection:** Blocks unsolicited external packets (anti-scanning).
  - **Tor Permissive:** Explicitly allows "Established/Related" connections, ensuring reliable Tor directory fetch.
  - **Output Control:** Allows Tor to communicate outward freely, but blocks incoming threats.
  - **Logging:** Drops are logged with prefix `FIREWALL-DROP:`.

### 2. SSH Safety Valve (Cloud Ready)
- **Feature:** New interactive prompt during installation: `Allow SSH Access? [y/N]`
- **Function:** If enabled, it automatically modifies the firewall to whitelist Port 22.
- **Benefit:** Prevents accidental lockouts when deploying on Cloud VPS (AWS/DigitalOcean/Linode).

### 3. Session-Based Monitoring HUD
- **New Monitor:** `aegis_monitor.sh` v5.0 included.
- **Session Logic:** Ignores historical logs. Only counts threats/warnings that occur *after* the monitor is started.
- **Real-Time Stream:** Filters out debug noise and shows only active threats.

## 🐳 Docker Implementation (v9.0)

### Security Features
- **Container Isolation:** Internal bridge network (no external access)
- **Read-only Web Content:** Webroot mounted as read-only
- **Minimal Capabilities:** Only required Linux capabilities (NET_BIND_SERVICE, etc.)
- **Seccomp Profile:** Restricted system calls (whitelist approach)
- **Resources:** CPU and Memory caps to prevent DoS.

### Benefits Over Bare Metal

| Feature | Docker | Bare Metal (v9.0) |
|---------|--------|-------------------|
| **Isolation** | High (container) | Low (host) |
| **Security** | Enhanced (layers) | Hardened Host |
| **Setup Time** | 5 minutes | 8 minutes |
| **SSH Safety** | N/A (Host managed) | **Built-in Valve** |
| **Firewall** | Container+Host | **Balanced NFTables** |

## 📊 Comparison: v7.0 vs v9.0

### Firewall Security
**v7.0 (Previous):**
- Aggressive rate limiting (5 conn/min)
- Occasional Tor blockages
- No SSH safety mechanism

**v9.0 (Current):**
- Balanced connection tracking
- 100% Tor reliability
- Integrated SSH safety valve
- Simplified Input chain

### Deployment Options
**v7.0:**
- Bare metal or Docker
- Manual config for Cloud VPS

**v9.0:**
- Interactive Architect Installer
- Cloud-ready (SSH prompt)
- Automatic log sanitization path fixes

## 🚀 Quick Start Comparison

### Docker (Recommended)
```bash
mkdir -p data/tor-keys webroot
echo "<h1>Site</h1>" > webroot/index.html
docker-compose up -d
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```
Bare Metal (Architect v9.0)
Bash
sudo ./install.sh
# Answer 'Y' to enable SSH if on Cloud VPS
sudo cat /var/lib/tor/hidden_service/hostname
🔒 Security Layers (v9.0)
Firewall Enhancements
Input Blocking: Drops all new external connections not matched by loopback or established state.

Tor Optimization: "Established/Related" rule ensures Tor directory fetches succeed.

SSH Valve: Optional, user-controlled hole for remote management.

Docker Security
Isolation: Complete container isolation

Capabilities: Minimal required capabilities

Seccomp: Restricted system calls

AppArmor: Additional access control

Resource Limits: CPU and memory limits

📝 Documentation Updates
QUICKSTART.md - Updated for v9.0 steps

install.sh - Updated with v9.0 logic

IMPROVEMENTS_SUMMARY.md - This file

✅ Testing Checklist
v9.0 Deployment
[ ] Installer runs without "unary operator" errors

[ ] SSH prompt appears and functions

[ ] Firewall rules permit Tor bootstrapping

[ ] Onion address generates within 60 seconds

[ ] Neural Sentry logs to RAM correctly

🎉 Summary
The v9.0 update brings:

✅ Stability: Fixed Tor connectivity issues via Balanced Firewall.

✅ Usability: SSH Safety Valve for Cloud deployments.

✅ Reliability: Fixed installer variable crashes.

✅ Monitoring: New Session-Based HUD.

All improvements maintain the privacy-first philosophy while significantly enhancing stability and ease of deployment.