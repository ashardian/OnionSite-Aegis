# Improvements Summary

## v10.0 — Bare Metal Edition

### 🗑️ Docker Support Removed

Docker was found to be fundamentally incompatible with Aegis's core security stack:

| Feature | Problem in Docker |
|---------|-------------------|
| `sysctl` kernel hardening | Requires `--privileged`, which defeats container isolation |
| NFTables firewall | Conflicts with Docker's own iptables/nftables on the host |
| Tor `Sandbox 1` mode | Crashes due to container seccomp profile blocking required syscalls |
| `tmpfs` RAM logging | Permission failures with `debian-tor` and `www-data` users in containers |

Bare metal gives full, direct control over every security layer — which is the correct architecture for a privacy-hardened hidden service.

---

### 🔍 `detect_tor_service()` — Auto Tor Service Detection

**Problem:** On some Debian systems Tor runs as `tor@default`, on others as `tor`. The old installer hardcoded `tor@default` which caused silent failures on systems using the plain `tor` unit name.

**Fix:** New `detect_tor_service()` function checks which unit is actually registered via `systemctl list-unit-files` and sets `$TOR_SERVICE` accordingly. The rest of the installer uses this variable everywhere.

```bash
detect_tor_service() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^tor@\.service'; then
        TOR_SERVICE="tor@default"
    else
        TOR_SERVICE="tor"
    fi
}
```

---

### 📁 `INSTALL_DIR` Path Resolution Fix

**Problem:** The old installer used `INSTALL_DIR=$(pwd)`, which breaks if you run it from a different directory — e.g. `sudo /opt/OnionSite-Aegis/install.sh` would set `INSTALL_DIR` to `/opt` instead of `/opt/OnionSite-Aegis`.

**Fix:** Changed to `BASH_SOURCE`-based resolution:

```bash
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Now the installer always knows where it lives, regardless of where it is called from.

---

### 🛡️ `set -E` — Deeper Error Propagation

**Problem:** The original `set -o pipefail` + `trap ... ERR` only caught errors at the top level of the script. Errors inside functions or subshells could be silently swallowed.

**Fix:** Added `set -E`, which causes the ERR trap to inherit into functions, command substitutions, and subshells. No error goes undetected.

---

### ⏱️ Privacy Monitor as systemd Timer

**Problem:** The privacy compliance checker (`privacy_monitor.sh`) previously had to be run manually. Most users would forget to run it.

**Fix:** The installer now registers it as a proper `systemd` timer unit so it runs automatically on a schedule:

```
privacy-monitor.service  — runs the check
privacy-monitor.timer    — triggers it periodically
```

Enabled automatically during install if `ENABLE_PRIVACY=1`.

---

### 🧹 Uninstaller Completeness

**Problem:** `uninstall.sh` in v9.0 did not clean up all systemd units added by the installer.

**Fix:** Updated to remove all units:
- `neural-sentry.service`
- `aegis-ram-init.service`
- `privacy-monitor.service`
- `privacy-monitor.timer`
- `traffic-protection.service`

Also now handles both **NFTables** and **UFW** cleanup gracefully, skipping whichever is not present on the system.

---

## v9.0 — Architect Edition

### Balanced NFTables Firewall

**Problem:** v7/v8 used aggressive rate limiting (5 conn/min) that occasionally blocked Tor circuit establishment, causing "Onion Site Not Found" errors.

**Fix:** New "balanced" ruleset explicitly allows `ct state established,related` traffic, ensuring Tor directory fetches always succeed while still blocking unsolicited input.

### SSH Safety Valve

Interactive prompt during install: `Allow SSH Access? [y/N]`

If enabled, automatically modifies the firewall to whitelist port 22. Prevents accidental lockouts on Cloud VPS deployments (AWS, DigitalOcean, Linode).

### Session-Based Monitoring HUD

`aegis_monitor.sh` v5.0 — ignores historical log noise, only tracks threats from the current session. Live CPU/RAM tracking for Tor and Nginx processes.

### Variable Initialization Fixes

All state flags (`ENABLE_WAF`, `ENABLE_LUA`, etc.) now initialized before use, preventing `unary operator expected` crashes on some systems.

---

## v7.0 / v8.0 — Earlier Versions

- Initial dual Docker + bare metal support
- Neural Sentry v1–v4
- Basic NFTables firewall (aggressive — caused Tor blockages)
- Manual privacy monitor

---

## 📊 Version Comparison

| Feature | v7/v8 | v9.0 | v10.0 |
|---------|-------|------|-------|
| Docker support | ✅ | ✅ | ❌ Removed |
| Tor service auto-detect | ❌ | ❌ | ✅ |
| Safe INSTALL_DIR | ❌ | ❌ | ✅ |
| set -E error propagation | ❌ | ❌ | ✅ |
| Privacy monitor (auto) | ❌ | ❌ | ✅ systemd timer |
| SSH Safety Valve | ❌ | ✅ | ✅ |
| Balanced NFTables | ❌ | ✅ | ✅ |
| Session HUD | ❌ | ✅ | ✅ |
| Amnesic RAM logging | ✅ | ✅ | ✅ |
| Neural Sentry | ✅ | ✅ | ✅ |
