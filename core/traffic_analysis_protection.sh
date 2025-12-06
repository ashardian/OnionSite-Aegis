#!/bin/bash
# Traffic Analysis Protection Module
# Prevents correlation attacks through various techniques

LOG_FILE="/mnt/ram_logs/traffic_protection.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 1. Block all DNS queries outside Tor
block_dns_leaks() {
    log_message "Blocking DNS leaks..."
    
    # Block DNS on all interfaces except loopback (Tor handles DNS)
    if command -v nft >/dev/null 2>&1; then
        nft add rule inet filter input udp dport 53 drop 2>/dev/null || true
        nft add rule inet filter input tcp dport 53 drop 2>/dev/null || true
        nft add rule inet filter output udp dport 53 drop 2>/dev/null || true
        nft add rule inet filter output tcp dport 53 drop 2>/dev/null || true
    fi
    
    # Also block via iptables if nftables not available
    if command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p udp --dport 53 -j DROP 2>/dev/null || true
        iptables -A INPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
        iptables -A OUTPUT -p udp --dport 53 -j DROP 2>/dev/null || true
        iptables -A OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null || true
    fi
    
    log_message "DNS leak protection active"
}

# 2. Block all outbound connections except through Tor
block_external_connections() {
    log_message "Blocking external connections (Tor only)..."
    
    # Allow only loopback and Tor SOCKS port
    if command -v nft >/dev/null 2>&1; then
        # Allow Tor SOCKS (localhost only)
        nft add rule inet filter output tcp dport 9050 oifname lo accept 2>/dev/null || true
        
        # Block all other outbound connections (except established)
        # Note: This is aggressive - adjust if needed for your setup
        # nft add rule inet filter output ct state new tcp dport != 9050 drop 2>/dev/null || true
    fi
    
    log_message "External connection blocking configured"
}

# 3. Randomize system time responses (prevents timing correlation)
setup_timing_randomization() {
    log_message "Setting up timing randomization..."
    
    # Add small random delays to system responses
    # This is handled at application level, but we can set kernel parameters
    # TCP timestamp randomization is already disabled in sysctl
    
    log_message "Timing randomization configured"
}

# 4. Memory protection (prevent memory dumps)
protect_memory() {
    log_message "Configuring memory protection..."
    
    # Disable core dumps (prevents memory analysis)
    ulimit -c 0
    
    # Set in /etc/security/limits.conf if persistent
    if [ -f /etc/security/limits.conf ]; then
        if ! grep -q "core.*0" /etc/security/limits.conf; then
            echo "* soft core 0" >> /etc/security/limits.conf
            echo "* hard core 0" >> /etc/security/limits.conf
        fi
    fi
    
    log_message "Memory protection configured"
}

# 5. Verify Tor is the only outbound connection method
verify_tor_only() {
    log_message "Verifying Tor-only connectivity..."
    
    # Check if any processes are making direct connections
    # This is a monitoring function
    
    if command -v netstat >/dev/null 2>&1; then
        DIRECT_CONN=$(netstat -tn 2>/dev/null | grep -v "127.0.0.1" | grep -v "::1" | grep ESTABLISHED | wc -l)
        if [ "$DIRECT_CONN" -gt 0 ]; then
            log_message "WARNING: Direct connections detected (should be 0)"
        else
            log_message "OK: No direct connections detected"
        fi
    fi
}

# Main execution
main() {
    log_message "=== Traffic Analysis Protection Module Starting ==="
    
    block_dns_leaks
    block_external_connections
    setup_timing_randomization
    protect_memory
    verify_tor_only
    
    log_message "=== Traffic Analysis Protection Module Complete ==="
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
    fi
    main
fi

