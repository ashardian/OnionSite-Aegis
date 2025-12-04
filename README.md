# 🛡️ OnionSite-Aegis (Insane Grade)
**v4.0 | Military-Grade Tor Hidden Service Orchestrator**

## ⚠️ WARNING: HIGH SECURITY MODE
This tool applies **aggressive system hardening**. It is designed for dedicated servers or fresh VMs (Debian 11+/Parrot OS).
- It **disables IPv6** system-wide.
- It **locks kernel pointers** (restricts `dmesg`).
- It moves all logs to **RAM (tmpfs)**. If power is cut, logs vanish forever.
- It implements **Active Circuit Killing** via the Tor Control Port.

## 🚀 Features

### 1. Amnesic Logging (Forensic Counter-Measure)
Standard tools log to the hard drive. Aegis creates a 256MB RAM-disk at `/mnt/ram_logs`.
- Nginx and Tor logs are symlinked here.
- **Benefit:** Rebooting or pulling the plug makes traffic logs physically unrecoverable.

### 2. Neural Sentry (Active Defense)
A Python-based daemon (`neural_sentry.py`) that acts as a localized IDS.
- **Circuit Breaker:** Monitors circuit creation rates. If a DDoS or Deanonymization attack (Guard forcing) is detected, it signals `NEWNYM` to Tor, instantly killing all circuits.
- **File Integrity:** Hashes your webroot. If a file is modified (e.g., shell upload), it alerts immediately.

### 3. Kernel & Network Hardening
- **NFTables Bunker:** Whitelist-only firewall. Blocks everything except Loopback (internal) and established connections. SSH is optional.
- **Tor Sandbox:** Runs Tor with `Sandbox 1`, preventing the process from making unauthorized syscalls.

## 🛠️ Installation

1. **Unzip the suite:**
   ```bash
   unzip OnionSite-Aegis.zip
   cd OnionSite-Aegis


2. **Run the Installer:**

```Bash

sudo chmod +x install.sh
sudo ./install.sh
Verify Status:

Bash

systemctl status neural-sentry
ls -la /mnt/ram_logs

```

3.**🧠 Usage**
```Web Root: Place your site files in /var/www/onion_site.

Onion Address: Found in /var/lib/tor/hidden_service/hostname.

Logs: View logs at /mnt/ram_logs/ (Remember: these are temporary).
```

🗑️ Uninstallation
To revert changes, remove the RAM disk, and unlock the firewall:

Bash

sudo ./uninstall.sh
