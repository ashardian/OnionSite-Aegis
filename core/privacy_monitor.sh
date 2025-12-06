#!/bin/bash
# Privacy Monitor - Checks for privacy leaks and misconfigurations
# Run periodically via cron or systemd timer

LOG_FILE="/mnt/ram_logs/privacy_monitor.log"
ALERT_THRESHOLD=5

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_tor_safelogging() {
    if systemctl is-active --quiet tor; then
        SAFELOG=$(tor --verify-config -f /etc/tor/torrc 2>&1 | grep -i "SafeLogging")
        if ! echo "$SAFELOG" | grep -q "1"; then
            log_message "ALERT: SafeLogging may not be enabled in Tor"
            return 1
        fi
    fi
    return 0
}

check_nginx_headers() {
    if systemctl is-active --quiet nginx; then
        # Check if server tokens are off
        if grep -q "server_tokens off" /etc/nginx/sites-available/onion_site; then
            log_message "OK: Nginx server tokens disabled"
        else
            log_message "ALERT: Nginx server tokens may be enabled"
            return 1
        fi
    fi
    return 0
}

check_ram_logs() {
    if mountpoint -q /mnt/ram_logs; then
        log_message "OK: RAM logs mounted correctly"
        return 0
    else
        log_message "CRITICAL: RAM logs not mounted - logs may be on disk!"
        return 1
    fi
}

check_file_permissions() {
    # Check web root permissions
    WEB_ROOT="/var/www/onion_site"
    if [ -d "$WEB_ROOT" ]; then
        PERMS=$(stat -c "%a" "$WEB_ROOT")
        if [ "$PERMS" != "755" ] && [ "$PERMS" != "750" ]; then
            log_message "WARNING: Web root permissions are $PERMS (recommended: 755 or 750)"
        fi
    fi
}

check_firewall() {
    if systemctl is-active --quiet nftables; then
        log_message "OK: NFTables firewall active"
        return 0
    else
        log_message "ALERT: NFTables firewall not active"
        return 1
    fi
}

check_disk_usage() {
    # Check if logs are accumulating on disk (should be minimal)
    DISK_LOGS=$(du -sh /var/log/nginx /var/log/tor 2>/dev/null | awk '{sum+=$1} END {print sum}')
    if [ -n "$DISK_LOGS" ] && [ "$DISK_LOGS" != "0" ]; then
        log_message "WARNING: Logs found on disk (should be in RAM only)"
    fi
}

# Main execution
log_message "=== Privacy Monitor Check Started ==="

ALERTS=0
check_tor_safelogging || ((ALERTS++))
check_nginx_headers || ((ALERTS++))
check_ram_logs || ((ALERTS++))
check_file_permissions
check_firewall || ((ALERTS++))
check_disk_usage

log_message "=== Privacy Monitor Check Complete (Alerts: $ALERTS) ==="

if [ $ALERTS -ge $ALERT_THRESHOLD ]; then
    log_message "CRITICAL: Multiple privacy issues detected!"
    exit 1
fi

exit 0

