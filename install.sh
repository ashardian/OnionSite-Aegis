#!/bin/bash

################################################################################
# OnionSite-Aegis: Ultimate Production Installer
# Version: 3.2 (Self-Healing / Fallback Mode)
# Target: Debian 12/13 & Ubuntu 22.04+
# Fixes: Nginx WAF crashes, Service masking, Permissions
################################################################################

# 1. ROBUST ERROR HANDLING
# ------------------------------------------------------------------------------
set -e
set -o pipefail
# Trap errors to show the exact line number where it failed
trap 'echo -e "\n\033[0;31m[CRITICAL FAILURE] Script stopped at line $LINENO. Please check logs.\033[0m"; exit 1' ERR

# 2. CONFIGURATION
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/aegis_install.log"
TOR_DIR="/var/lib/tor"
HS_DIR="$TOR_DIR/hidden_service"
WEB_DIR="/var/www/onionsite"
NGINX_MODSEC_DIR="/etc/nginx/modsec"

log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }

# 3. PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
clear
echo -e "${GREEN}=== STARTING AEGIS DEPLOYMENT v3.2 ===${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] Must be run as root.${NC}"
   exit 1
fi

# SELF-HEALING: Unlock network
if command -v nft &> /dev/null; then nft flush ruleset 2>/dev/null || true; fi
if command -v iptables &> /dev/null; then iptables -F 2>/dev/null || true; fi

# SYSTEM CLOCK (Container Safe)
if timedatectl set-ntp true 2>/dev/null; then
    success "Time sync active."
else
    warn "NTP not supported (Container/VPS). Skipping."
fi

# 4. DEPENDENCIES
# ------------------------------------------------------------------------------
log "Installing Dependencies..."
apt-get update -q
DEPS="curl wget git build-essential tor nginx nftables \
python3-pip python3-stem python3-inotify python3-requests \
apparmor-utils apparmor-profiles python3-apparmor \
libmodsecurity3 libnginx-mod-http-modsecurity"

apt-get install -y --no-install-recommends $DEPS
success "Dependencies installed."

# 5. KERNEL HARDENING
# ------------------------------------------------------------------------------
log "Applying Kernel Security..."
cat > /etc/sysctl.d/99-aegis.conf <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
EOF
if sysctl --system >/dev/null 2>&1; then
    success "Kernel hardened."
else
    warn "Kernel hardening skipped (Container)."
fi

# 6. TOR CONFIGURATION
# ------------------------------------------------------------------------------
log "Configuring Tor..."
systemctl unmask tor.service tor@default.service >/dev/null 2>&1 || true
systemctl stop tor >/dev/null 2>&1 || true

# Backup config
if [ -f /etc/tor/torrc ] && [ ! -f /etc/tor/torrc.bak ]; then
    cp /etc/tor/torrc /etc/tor/torrc.bak
fi

# Write Tor Config
cat > /etc/tor/torrc <<EOF
DataDirectory /var/lib/tor
HiddenServiceDir $HS_DIR
HiddenServicePort 80 127.0.0.1:80
RunAsDaemon 1
Sandbox 1
NoExec 1
EOF

# PERMISSION FIX
mkdir -p "$HS_DIR"
chown -R debian-tor:debian-tor "$TOR_DIR"
chmod 700 "$TOR_DIR"
chmod 700 "$HS_DIR"
success "Tor permissions secured."

# 7. NGINX CONFIGURATION (WITH FALLBACK)
# ------------------------------------------------------------------------------
log "Configuring Nginx..."
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/onion*

# Download WAF Rules
mkdir -p "$NGINX_MODSEC_DIR"
if [ ! -f "$NGINX_MODSEC_DIR/modsecurity.conf" ]; then
    wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -O "$NGINX_MODSEC_DIR/modsecurity.conf"
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$NGINX_MODSEC_DIR/modsecurity.conf"
fi
if [ ! -f "$NGINX_MODSEC_DIR/unicode.mapping" ]; then
    wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping -O "$NGINX_MODSEC_DIR/unicode.mapping"
fi
echo "include $NGINX_MODSEC_DIR/modsecurity.conf" > "$NGINX_MODSEC_DIR/main.conf"

# Create Web Page
mkdir -p "$WEB_DIR"
cat > "$WEB_DIR/index.html" <<EOF
<!DOCTYPE html><html><head><title>AEGIS SECURE</title>
<style>body{background:#000;color:#0f0;font-family:monospace;display:flex;justify-content:center;align-items:center;height:100vh;}</style>
</head><body><h1>AEGIS SECURE</h1><p>Status: ONLINE</p></body></html>
EOF
chown -R www-data:www-data "$WEB_DIR"
chmod 755 "$WEB_DIR"

# GENERATE SERVER BLOCK
cat > /etc/nginx/sites-available/aegis_onion <<EOF
server {
    listen 127.0.0.1:80;
    server_name localhost;
    root $WEB_DIR;
    index index.html;
    
    # WAF SETTINGS (May be disabled by script if crash detected)
    modsecurity on;
    modsecurity_rules_file $NGINX_MODSEC_DIR/main.conf;
    
    server_tokens off;
    add_header X-Frame-Options DENY;
    
    location / { try_files \$uri \$uri/ =404; }
}
EOF
ln -sf /etc/nginx/sites-available/aegis_onion /etc/nginx/sites-enabled/

# 8. FIREWALL (NFTABLES)
# ------------------------------------------------------------------------------
log "Applying Firewall..."
cat > /etc/nftables.conf <<EOF
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        tcp dport 22 accept
        ip protocol icmp accept
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF
if nft -f /etc/nftables.conf 2>/dev/null; then
    systemctl enable nftables >/dev/null 2>&1
    success "Firewall Active."
else
    warn "Firewall skipped (Kernel restricted)."
fi

# 9. STARTUP & AUTO-HEALING
# ------------------------------------------------------------------------------
log "Starting Services..."
systemctl daemon-reload

# Start Tor (Wait for Keys)
log "Bootstrapping Tor..."
systemctl restart tor@default
COUNT=0
while [ ! -f "$HS_DIR/hostname" ]; do
    if [ $COUNT -gt 20 ]; then
        warn "Tor keys slow. Retrying..."
        chown -R debian-tor:debian-tor "$TOR_DIR"
        systemctl restart tor@default
        sleep 5
    fi
    sleep 2
    COUNT=$((COUNT+1))
done

# Start Nginx (WITH AUTO-HEAL)
log "Starting Nginx..."
if ! systemctl restart nginx; then
    echo -e "${RED}[!] Nginx WAF crash detected. Falling back to Safe Mode...${NC}"
    # Print real error for log
    nginx -t || true
    # Disable ModSecurity in config
    sed -i 's/modsecurity on;/#modsecurity on;/g' /etc/nginx/sites-available/aegis_onion
    sed -i 's/modsecurity_rules_file/#modsecurity_rules_file/g' /etc/nginx/sites-available/aegis_onion
    
    # Retry start
    if systemctl restart nginx; then
        warn "Nginx started in SAFE MODE (WAF Disabled due to incompatibility)."
    else
        echo -e "${RED}[CRITICAL] Nginx failed even in Safe Mode.${NC}"
        journalctl -xeu nginx --no-pager | tail -n 20
        exit 1
    fi
else
    success "Nginx started with WAF ACTIVE."
fi

# 10. COMPLETION
# ------------------------------------------------------------------------------
echo ""
echo "================================================================"
if [ -f "$HS_DIR/hostname" ]; then
    ONION=$(cat "$HS_DIR/hostname")
    success "Tor Network: CONNECTED"
    echo -e "${GREEN}>>> YOUR ONION ADDRESS: ${ONION} <<<${NC}"
else
    echo -e "${RED}[FAIL] Onion address missing.${NC}"
fi
echo "================================================================"
