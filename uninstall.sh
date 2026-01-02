#!/bin/bash
# Reverts Aegis changes
if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi

echo "Uninstalling Aegis..."

# Stop services (ignore errors if services don't exist)
systemctl stop tor nginx neural-sentry aegis-ram-init privacy-monitor.timer 2>/dev/null || true
systemctl disable neural-sentry aegis-ram-init privacy-monitor.timer 2>/dev/null || true

# Remove systemd units
rm -f /etc/systemd/system/neural-sentry.service
rm -f /etc/systemd/system/aegis-ram-init.service
rm -f /etc/systemd/system/privacy-monitor.service
rm -f /etc/systemd/system/privacy-monitor.timer
systemctl daemon-reload

# Revert Logging
if [ -f /etc/fstab ]; then
    sed -i '/ram_logs/d' /etc/fstab || true
fi
umount /mnt/ram_logs 2>/dev/null || true
rm -rf /var/log/nginx /var/log/tor
mkdir -p /var/log/nginx /var/log/tor
chown www-data:www-data /var/log/nginx 2>/dev/null || true
chown debian-tor:debian-tor /var/log/tor 2>/dev/null || true

# Remove installed scripts
rm -f /usr/local/bin/neural_sentry.py
rm -f /usr/local/bin/privacy_log_sanitizer.py
rm -f /usr/local/bin/privacy_monitor.sh
rm -f /usr/local/bin/traffic_analysis_protection.sh
rm -f /usr/local/bin/aegis-edit
rm -f /usr/local/bin/init_ram_logs.sh

# NOTE: /var/lib/tor/hidden_service/ is NOT deleted to preserve the onion service identity
# If you want to delete it, do so manually: rm -rf /var/lib/tor/hidden_service/

# Reset Firewall
# Flush NFTables ruleset if nftables is available
if command -v nft >/dev/null 2>&1; then
    echo "Resetting NFTables firewall..."
    nft flush ruleset || true
else
    echo "NFTables not found, skipping firewall reset."
fi

# Reset UFW if available (optional - not all systems have UFW)
if command -v ufw >/dev/null 2>&1; then
    echo "Resetting UFW firewall..."
    ufw disable || true
    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw allow ssh || true
    ufw enable || true
else
    echo "UFW not found, skipping UFW reset."
fi

# Remove sysctl config
rm -f /etc/sysctl.d/99-aegis.conf

# Remove NFTables config (if it was installed by Aegis)
if [ -f /etc/nftables.conf ] && grep -q "OnionSite-Aegis\|AEGIS" /etc/nftables.conf 2>/dev/null; then
    echo "Removing Aegis NFTables configuration..."
    # Backup original or remove if it's Aegis-specific
    if [ -f /etc/nftables.conf.backup ]; then
        mv /etc/nftables.conf.backup /etc/nftables.conf
    else
        # Create a minimal default config
        cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    fi
fi

echo ""
echo "Uninstallation complete. Logs are back on disk."
echo ""
echo "NOTE: /var/lib/tor/hidden_service/ was NOT deleted to preserve your onion service identity."
echo "      If you want to delete it, run: rm -rf /var/lib/tor/hidden_service/"
echo ""
