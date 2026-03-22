# ⚡ OnionSite-Aegis Quick Start (v10.0)

Get your hardened Tor hidden service running in minutes.

---

## Prerequisites

- Debian 11+, or Parrot OS
- Root access
- 500MB+ free disk space

---

## Install

```bash
git clone https://github.com/ashardian/OnionSite-Aegis.git
cd OnionSite-Aegis
chmod +x install.sh
sudo ./install.sh
```

Follow the interactive prompts. If you are on a **Cloud VPS**, make sure to enable SSH access when asked.

---

## Get Your Onion Address

```bash
sudo cat /var/lib/tor/hidden_service/hostname
```

---

## Verify Services

```bash
sudo systemctl status tor
sudo systemctl status nginx
sudo systemctl status neural-sentry
```

---

## Add Your Website

```bash
sudo aegis-edit
```

---

## Monitor

```bash
sudo ./aegis_monitor.sh
```

---

## Backup Keys (Do This Now)

⚠️ Losing your keys = losing your onion address forever.

```bash
sudo ./SAVE_MY_ONION.sh
```

---

For full documentation see [SETUP.md](../SETUP.md).
