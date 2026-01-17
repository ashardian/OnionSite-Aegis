# Privacy & Functionality Improvements - v9.0

## Overview
This document outlines the privacy-focused and functionality improvements in OnionSite-Aegis v9.0.

## 🔒 Privacy Enhancements

### 1. Balanced Firewall (v9.0 Upgrade)
- **Smart Filtering:** Moved from "Paranoid" blocking (which broke Tor) to "Stateful" filtering.
- **Logic:** Blocks all *new* incoming connections from the internet, but allows *replies* to connections initiated by Tor.
- **Result:** Invisible to port scanners, but fully functional for Tor hidden services.

### 2. Enhanced Neural Sentry (v9.0 Integration)
- **Path Fixes:** Hardcoded paths updated to ensure logs reside in `/var/log/tor` (RAM disk), preventing HDD leaks.
- **Privacy Log Filtering:** Automatic sanitization of IPs and hostnames.
- **Attack Detection:** Monitors circuit creation rates to detect DoS attempts.

### 3. Nginx Privacy Configuration
- **Anti-Fingerprinting:** Server tokens disabled, ETag/Last-Modified headers removed.
- **Privacy Headers:**
  - `Referrer-Policy: no-referrer`
  - `Permissions-Policy`: Blocks geolocation/camera/mic.
- **Access Logs Disabled:** No access logging by default.

### 4. RAM-Only Logging (Enforced)
- **Mechanism:** Installer forcibly mounts `/var/log/tor` as `tmpfs`.
- **Sanitization:** All Tor notices and Sentry logs are written here.
- **Forensics:** Pulling the plug destroys all traces of traffic history.

### 5. Privacy Monitor HUD
- **Session Tracking:** New HUD ignores historical logs (which might persist if not rebooted) and only shows *active* threats in the current session.
- **Visual Validation:** Shows "SECURE (RAM)" status verification on dashboard.

## ⚡ Functionality Improvements

### 1. SSH Safety Valve (v9.0 Feature)
- **Problem:** Users installing on AWS/DigitalOcean were getting locked out by the firewall.
- **Solution:** Interactive prompt (`Enable SSH? [y/N]`) allows whitelisting Port 22 safely.

### 2. Interactive Architect Installer
- **Selectable Modules:**
  - WAF (ModSecurity)
  - Lua Padding
  - Neural Sentry
  - SSH Access
- **Ghost Purge:** Automatically removes conflicting configs before installation.

### 3. Better Error Handling
- **Crash Fixes:** Solved `unary operator` errors in bash scripts.
- **Health Checks:** Post-install menu verifies generation of Onion address.

## 📊 Performance Improvements

- **Firewall Efficiency:** Removed complex rate-limiting rules that consumed CPU and blocked legitimate Tor traffic.
- **Resource Management:** Neural Sentry runs as a systemd service with proper resource caps.

## 🛡️ Security Enhancements

- **AppArmor:** Integration for Nginx process sandboxing.
- **Kernel Hardening:** Sysctl rules to prevent IP spoofing and man-in-the-middle attacks.

## 📈 Version History

- **v9.0**: Architect Edition (Balanced Firewall, SSH Safety, HUD v5.0)
- **v7.0**: Initial Architect Release
- **v5.0**: Docker & Privacy Focus

## 🔄 Migration Notes

Users upgrading from v7.0:
- **Run `install.sh` again:** It will detect the existing install, offer to wipe or keep keys, and apply the v9.0 firewall and script fixes.
- **Firewall:** Will automatically be downgraded to the stable "Balanced" ruleset.