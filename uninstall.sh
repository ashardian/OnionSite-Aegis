#!/bin/bash
# Reverts Aegis changes
if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi

echo "Uninstalling Aegis..."

# Stop services
systemctl stop tor nginx neural-sentry aegis-ram-init
systemctl disable neural-sentry aegis-ram-init

# Remove systemd units
rm /etc/systemd/system/neural-sentry.service
rm /etc/systemd/system/aegis-ram-init.service
systemctl daemon-reload

# Revert Logging
sed -i '/ram_logs/d' /etc/fstab
umount /mnt/ram_logs || true
rm -rf /var/log/nginx /var/log/tor
mkdir /var/log/nginx /var/log/tor
chown www-data:www-data /var/log/nginx
chown debian-tor:debian-tor /var/log/tor

# Reset Firewall (UFW default)
nft flush ruleset
ufw disable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw enable

echo "Uninstallation complete. Logs are back on disk."
