#!/bin/bash
# Docker Entrypoint for OnionSite-Aegis
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${CYAN}[AEGIS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ---- Debian-only execution guard ----
if [ ! -f /etc/os-release ]; then
    echo "[FATAL] Cannot detect container OS."
    exit 1
fi

. /etc/os-release

if [[ "${ID}" != "debian" ]]; then
    echo "[FATAL] Unsupported container OS: ${ID}"
    echo "OnionSite-Aegis containers are designed to run on Debian only."
    exit 1
fi

log "Debian environment detected (version ${VERSION_ID})."

# ---- Version awareness (non-blocking) ----
case "${VERSION_ID}" in
    13)
        log "Debian 13 detected (primary supported platform)."
        ;;
    *)
        log "WARNING: Debian ${VERSION_ID} detected."
        log "This version is not the primary test target (Debian 13)."
        ;;
esac


# Function to setup RAM logging
setup_ram_logs() {
    log "Setting up RAM-based logging..."
    mkdir -p /mnt/ram_logs/nginx /mnt/ram_logs/tor
    chown -R www-data:www-data /mnt/ram_logs/nginx
    chown -R debian-tor:debian-tor /mnt/ram_logs/tor
    chmod 750 /mnt/ram_logs/nginx
    chmod 700 /mnt/ram_logs/tor
    
    # Link logs to RAM
    rm -rf /var/log/nginx /var/log/tor
    ln -sf /mnt/ram_logs/nginx /var/log/nginx
    ln -sf /mnt/ram_logs/tor /var/log/tor
}

# Function to configure Tor
configure_tor() {
    log "Configuring Tor..."
    
    # Ensure hidden service directory exists BEFORE configuring Tor
    log "Creating hidden service directory..."
    mkdir -p /var/lib/tor/hidden_service
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
    chmod 700 /var/lib/tor/hidden_service
    
    # Remove duplicate HiddenServiceDir lines from existing torrc (if any)
    if [ -f /etc/tor/torrc ]; then
        log "Removing duplicate HiddenServiceDir entries..."
        grep -v "^HiddenServiceDir" /etc/tor/torrc > /tmp/torrc.clean 2>/dev/null || true
        sed -i '/^[[:space:]]*HiddenServiceDir/d' /tmp/torrc.clean 2>/dev/null || true
    fi
    
    CORES=$(nproc)
    
    cat > /etc/tor/torrc <<EOF
DataDirectory /var/lib/tor
PidFile /run/tor/tor.pid
RunAsDaemon 0
User debian-tor

# Control Port for Neural Sentry
ControlPort 127.0.0.1:9051
CookieAuthentication 1

# OnionSite-Aegis Hidden Service
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:8080

# Privacy & Security Hardening
Sandbox 1
NoExec 1
HardwareAccel 1
SafeLogging 1
AvoidDiskWrites 1
NumCPUs $CORES

# Enhanced Privacy Settings
DisableDebuggerAttachment 1
SafeSocks 1
WarnUnsafeSocks 0
TestSocks 1
CircuitBuildTimeout 10
KeepalivePeriod 60
NewCircuitPeriod 30
MaxCircuitDirtiness 600
MaxClientCircuitsPending 32

# Connection Privacy (Maximum)
ConnectionPadding 1
ReducedConnectionPadding 0
CircuitPadding 1
PaddingDistribution piatkowski  # Advanced padding distribution

# Guard Node Privacy (Enhanced)
UseEntryGuards 1
NumEntryGuards 3
GuardLifetime 30 days
NumDirectoryGuards 3
EntryNodes {}  # Use any entry node (prevents selection bias)
StrictEntryNodes 0

# Exit Node Restrictions
ExitNodes {}
ExcludeNodes {}
StrictNodes 0

# Additional Privacy Settings
PublishServerDescriptor 0
ClientOnly 1  # Only act as client, not relay
FetchDirInfoEarly 0
FetchUselessDescriptors 0
LearnCircuitBuildTimeout 0  # Don't learn optimal timeouts (prevents fingerprinting)

# Logging Privacy (minimal)
Log notice file /mnt/ram_logs/tor/tor.log
SafeLogging 1
AvoidDiskWrites 1
EOF

    # Ensure permissions are correct
    chown -R debian-tor:debian-tor /var/lib/tor
    chmod 700 /var/lib/tor/hidden_service
    
    # Ensure the hidden service directory is never deleted (add protection)
    if [ -d /var/lib/tor/hidden_service ]; then
        # Set immutable flag if supported (extra protection)
        chattr +i /var/lib/tor/hidden_service/hostname 2>/dev/null || true
    fi
}

# Function to deploy WAF
deploy_waf() {
    log "Deploying Web Application Firewall..."
    
    # Download OWASP CRS if not present
    if [ ! -d "/usr/share/modsecurity-crs" ]; then
        git clone --depth 1 https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs
        mv /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
    fi
    
    # Configure ModSecurity
    mkdir -p /etc/nginx/modsec
    cat > /etc/nginx/modsec/main.conf <<EOF
Include /etc/nginx/modsec/modsecurity.conf
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
EOF

    # Download default config if not present
    if [ ! -f "/etc/nginx/modsec/modsecurity.conf" ]; then
        curl -sSL https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended \
            -o /etc/nginx/modsec/modsecurity.conf
        sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf
    fi
}

# Function to setup firewall (if nftables available)
setup_firewall() {
    if command -v nft >/dev/null 2>&1; then
        log "Setting up NFTables firewall..."
        # Firewall rules are applied at host level or via docker network policies
        # Container-level firewall is limited, but we can set it up
        if [ -f "/etc/nftables.conf" ]; then
            nft -f /etc/nftables.conf || true
        fi
    fi
}

# Function to verify hidden service hostname
verify_hostname() {
    local max_attempts=30
    local attempt=0
    
    log "Waiting for Tor to create hidden service hostname..."
    
    while [ $attempt -lt $max_attempts ]; do
        if [ -f /var/lib/tor/hidden_service/hostname ]; then
            HOSTNAME=$(cat /var/lib/tor/hidden_service/hostname)
            log "Hidden service hostname created successfully!"
            log "Onion address: ${GREEN}$HOSTNAME${NC}"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    error "Tor did not create the hidden service hostname after $max_attempts attempts"
    if [ -f /mnt/ram_logs/tor/tor.log ]; then
        error "Last 50 lines of Tor log:"
        tail -n 50 /mnt/ram_logs/tor/tor.log || true
    fi
    return 1
}

# Function to start services
start_services() {
    log "Starting services..."
    
    # Start Tor
    log "Starting Tor..."
    tor -f /etc/tor/torrc &
    TOR_PID=$!
    
    # Wait for Tor to initialize and verify hostname
    if ! verify_hostname; then
        error "Failed to create hidden service. Stopping Tor..."
        kill $TOR_PID 2>/dev/null || true
        exit 1
    fi
    
    # Start Neural Sentry
    log "Starting Neural Sentry..."
    python3 /usr/local/bin/neural_sentry.py &
    SENTRY_PID=$!
    
    # Start Nginx
    log "Starting Nginx..."
    nginx -g "daemon off;" &
    NGINX_PID=$!
    
    # Wait for all processes
    wait $TOR_PID $SENTRY_PID $NGINX_PID
}

# Main execution
case "${1:-aegis}" in
    aegis)
        log "Starting OnionSite-Aegis v5.0 (Docker)"
        
        # Setup
        setup_ram_logs
        configure_tor
        deploy_waf
        setup_firewall
    
    # Setup traffic analysis protection
    if [ -f "/usr/local/bin/traffic_analysis_protection.sh" ]; then
        log "Setting up traffic analysis protection..."
        /usr/local/bin/traffic_analysis_protection.sh || true
    fi
        
        # Apply sysctl settings (if possible in container)
        sysctl -p /etc/sysctl.d/99-aegis.conf 2>/dev/null || true
        
        # Start services
        start_services
        ;;
    shell)
        exec /bin/bash
        ;;
    *)
        exec "$@"
        ;;
esac
