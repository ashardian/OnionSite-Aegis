#!/bin/bash
# Reverts Aegis changes
if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi

echo "Uninstalling Aegis..."

# Stop services
systemctl stop tor nginx neural-sentry aegis-ram-init privacy-monitor.timer
systemctl disable neural-sentry aegis-ram-init privacy-monitor.timer

# Remove systemd units
rm -f /etc/systemd/system/neural-sentry.service
rm -f /etc/systemd/system/aegis-ram-init.service
rm -f /etc/systemd/system/privacy-monitor.service
rm -f /etc/systemd/system/privacy-monitor.timer
systemctl daemon-reload

# Revert Logging
sed -i '/ram_logs/d' /etc/fstab
umount /mnt/ram_logs || true
rm -rf /var/log/nginx /var/log/tor
mkdir /var/log/nginx /var/log/tor
chown www-data:www-data /var/log/nginx
chown debian-tor:debian-tor /var/log/tor

# Remove installed scripts
rm -f /usr/local/bin/neural_sentry.py
rm -f /usr/local/bin/privacy_log_sanitizer.py
rm -f /usr/local/bin/privacy_monitor.sh
rm -f /usr/local/bin/init_ram_logs.sh

# Reset Firewall (UFW default)
nft flush ruleset
ufw disable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw enable

# Remove sysctl config
rm -f /etc/sysctl.d/99-aegis.conf

echo "Uninstallation complete. Logs are back on disk."
