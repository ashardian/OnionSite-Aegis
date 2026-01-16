#!/bin/bash

################################################################################
# OnionSite-Aegis: Master Architect Installer
# Version: 9.0 (Final Production - Architect Edition)
#
# CHANGELOG:
# v9.0: Integrated Advanced Firewall, SSH Safety Valve, Post-Install Dashboard.
#       Fixed all variable initialization crashes. Full RAM-disk compliance.
################################################################################

# ==============================================================================
# 1. CONSTANTS & CONFIGURATION
# ==============================================================================
set -o pipefail

# Visuals
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# System Paths
INSTALL_DIR=$(pwd)
CORE_DIR="$INSTALL_DIR/core"
LOG_FILE="/var/log/aegis_install.log"

# Service Paths
TOR_LIB="/var/lib/tor"
TOR_HS="$TOR_LIB/hidden_service"
TOR_LOG_DIR="/var/log/tor"
WEB_ROOT="/var/www/onion_site"

# Nginx Paths
NGINX_MOD_EN="/etc/nginx/modules-enabled"
NGINX_MOD_DIS="/etc/nginx/modules-disabled-backup"
NGINX_WAF_DIR="/etc/nginx/modsec"
NGINX_LUA_DIR="/etc/nginx/lua"

# State Flags (Defaults set to YES/1)
# CRITICAL FIX: All variables must be initialized to prevent crashes
ENABLE_WAF=1
ENABLE_LUA=1
ENABLE_SENTRY=1
ENABLE_PRIVACY=1
ENABLE_TRAFFIC=1
ENABLE_SSH=0      # Default to 0 (Safe) - User must enable it for Cloud VMs

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================
log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
critical() { echo -e "${RED}[CRITICAL] $1${NC}"; exit 1; }

# Trap errors to prevent silent failures
trap 'echo -e "\n${RED}[RUNTIME ERROR] Script aborted at line $LINENO.${NC}"; exit 1' ERR

# ==============================================================================
# 3. ENVIRONMENT & HYGIENE
# ==============================================================================
check_environment() {
    log "Performing Pre-Flight Environment Checks..."
    
    # Hygiene: Remove Python bytecode
    if find . -type d -name "__pycache__" | grep -q .; then
        find . -type d -name "__pycache__" -exec rm -rf {} +
    fi
    
    # Root Check
    if [[ $EUID -ne 0 ]]; then critical "This script must be run as root."; fi
}

# ==============================================================================
# 4. INTERACTIVE FEATURE SELECTION (Default = YES)
# ==============================================================================
clear
echo -e "${GREEN}=== ONIONSITE-AEGIS ARCHITECT v9.0 ===${NC}"
check_environment
echo ""
echo "Configure your deployment (Press ENTER to accept defaults):"

# Logic: Default is YES (1). Explicit 'n' sets to 0.

read -p "1. Enable ModSecurity WAF? [Y/n]: " resp
[[ "$resp" =~ ^[Nn]$ ]] && ENABLE_WAF=0

read -p "2. Enable Lua Response Padding? [Y/n]: " resp
[[ "$resp" =~ ^[Nn]$ ]] && ENABLE_LUA=0

read -p "3. Enable Neural Sentry? [Y/n]: " resp
[[ "$resp" =~ ^[Nn]$ ]] && ENABLE_SENTRY=0

read -p "4. Enable Privacy Monitor? [Y/n]: " resp
[[ "$resp" =~ ^[Nn]$ ]] && ENABLE_PRIVACY=0

read -p "5. Enable Traffic Analysis Protection? [Y/n]: " resp
[[ "$resp" =~ ^[Nn]$ ]] && ENABLE_TRAFFIC=0

echo -e "\n${YELLOW}[!] REMOTE ACCESS WARNING${NC}"
echo "   If you are on a Cloud VPS (AWS/DigitalOcean) or using SSH, you MUST enable this."
read -p "6. Allow SSH Access? [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_SSH=1

echo ""
read -p "Press ENTER to begin deployment..."

# ==============================================================================
# 5. NUCLEAR SANITIZATION (The "Ghost Purge")
# ==============================================================================
log "Sanitizing Environment..."

# Stop everything
systemctl stop nginx tor tor@default neural-sentry 2>/dev/null || true

# Purge Nginx configs
rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*
mkdir -p "$NGINX_MOD_DIS"
mv "$NGINX_MOD_EN"/* "$NGINX_MOD_DIS"/ 2>/dev/null || true

# Identity Wipe Logic
if [ -d "$TOR_HS" ]; then
    echo -e "${YELLOW}[!] EXISTING IDENTITY FOUND${NC}"
    read -p "Type 'wipe' to delete keys and get a NEW address (or ENTER to keep): " WIPE_CONF
    if [[ "$WIPE_CONF" == "wipe" ]]; then
        log "Securely wiping identity..."
        umount "$TOR_LOG_DIR" 2>/dev/null || true
        rm -rf "$TOR_HS" "$WEB_ROOT" "$TOR_LOG_DIR"/*
        rm -f "$TOR_LIB/lock" "$TOR_LIB/state"
        success "Identity Wiped."
    fi
fi

# ==============================================================================
# 6. DEPENDENCY MANAGEMENT
# ==============================================================================
log "Installing Dependencies..."
BASE_DEPS="curl wget tor nginx nftables python3-pip python3-stem python3-inotify apparmor-utils"
OPT_DEPS=""

if [ $ENABLE_WAF -eq 1 ]; then OPT_DEPS="$OPT_DEPS libmodsecurity3 libnginx-mod-http-modsecurity"; fi
if [ $ENABLE_LUA -eq 1 ]; then OPT_DEPS="$OPT_DEPS libnginx-mod-http-lua libnginx-mod-http-ndk"; fi

apt-get update -q
apt-get install -y --no-install-recommends $BASE_DEPS $OPT_DEPS
success "System Packages Installed."

if [ $ENABLE_SENTRY -eq 1 ]; then
    if [ -f "$CORE_DIR/neural_sentry.py" ]; then
        # Install Python dependencies globally for the system service
        pip3 install requests psutil --break-system-packages 2>/dev/null || true
        success "Python Dependencies Installed."
    fi
fi

# ==============================================================================
# 7. STEALTH LOGGING & HARDENING
# ==============================================================================
log "Configuring RAM Logging..."
mkdir -p "$TOR_LOG_DIR"
# Check if already mounted to avoid double-mount errors
if ! mount | grep -q "$TOR_LOG_DIR type tmpfs"; then
    mount -t tmpfs -o size=10M,mode=0700,uid=debian-tor,gid=debian-tor tmpfs "$TOR_LOG_DIR"
fi
chown -R debian-tor:debian-tor "$TOR_LOG_DIR"
chmod 700 "$TOR_LOG_DIR"

log "Hardening Tor Configuration..."
mkdir -p "$TOR_HS"
chown -R debian-tor:debian-tor "$TOR_LIB"
chmod 700 "$TOR_LIB" "$TOR_HS"

cat > /etc/tor/torrc <<EOF
DataDirectory $TOR_LIB
PidFile /run/tor/tor.pid
RunAsDaemon 1
User debian-tor
ControlPort 127.0.0.1:9051
CookieAuthentication 1
HiddenServiceDir $TOR_HS
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80
Sandbox 0
NoExec 1
HardwareAccel 1
SafeLogging 1
AvoidDiskWrites 1
Log notice file $TOR_LOG_DIR/notices.log
EOF

# ==============================================================================
# 8. NGINX ARCHITECTURE
# ==============================================================================
log "Building Nginx Architecture..."

# Link Modules based on selection
if [ $ENABLE_LUA -eq 1 ]; then
    [ -f /usr/share/nginx/modules-available/mod-http-ndk.conf ] && ln -sf /usr/share/nginx/modules-available/mod-http-ndk.conf "$NGINX_MOD_EN/10-ndk.conf"
    [ -f /usr/share/nginx/modules-available/mod-http-lua.conf ] && ln -sf /usr/share/nginx/modules-available/mod-http-lua.conf "$NGINX_MOD_EN/20-lua.conf"
fi
if [ $ENABLE_WAF -eq 1 ]; then
    [ -f /usr/share/nginx/modules-available/mod-http-modsecurity.conf ] && ln -sf /usr/share/nginx/modules-available/mod-http-modsecurity.conf "$NGINX_MOD_EN/30-modsec.conf"
fi

# Base Config
cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 768; }
http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Web Content
mkdir -p "$WEB_ROOT"
if [ ! -f "$WEB_ROOT/index.html" ]; then
    echo "<h1>Authorized Access Only</h1><p>Aegis v9.0 Protected</p>" > "$WEB_ROOT/index.html"
fi
chown -R www-data:www-data "$WEB_ROOT"

# Site Config Builder
SITE_CONF="/etc/nginx/sites-available/onion_site"
echo "server {" > "$SITE_CONF"
echo "    listen 127.0.0.1:80 default_server;" >> "$SITE_CONF"
echo "    server_name _;" >> "$SITE_CONF"
echo "    root $WEB_ROOT;" >> "$SITE_CONF"
echo "    index index.html;" >> "$SITE_CONF"
echo "    server_tokens off;" >> "$SITE_CONF"
echo "    add_header X-Frame-Options DENY;" >> "$SITE_CONF"

if [ $ENABLE_WAF -eq 1 ]; then
    mkdir -p "$NGINX_WAF_DIR"
    # Fetch OWASP recommended config if missing
    [ ! -f "$NGINX_WAF_DIR/modsecurity.conf" ] && wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -O "$NGINX_WAF_DIR/modsecurity.conf"
    # Switch DetectionOnly to On
    [ -f "$NGINX_WAF_DIR/modsecurity.conf" ] && sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$NGINX_WAF_DIR/modsecurity.conf"
    
    echo "include $NGINX_WAF_DIR/modsecurity.conf" > "$NGINX_WAF_DIR/main.conf"
    echo "    modsecurity on;" >> "$SITE_CONF"
    echo "    modsecurity_rules_file $NGINX_WAF_DIR/main.conf;" >> "$SITE_CONF"
fi

if [ $ENABLE_LUA -eq 1 ] && [ -f "$CORE_DIR/response_padding.lua" ]; then
    mkdir -p "$NGINX_LUA_DIR"
    cp "$CORE_DIR/response_padding.lua" "$NGINX_LUA_DIR/"
    chmod 644 "$NGINX_LUA_DIR/response_padding.lua"
    echo "    body_filter_by_lua_file $NGINX_LUA_DIR/response_padding.lua;" >> "$SITE_CONF"
fi

echo "    location / { try_files \$uri \$uri/ =404; }" >> "$SITE_CONF"
echo "}" >> "$SITE_CONF"

ln -sf "$SITE_CONF" "$NGINX_MOD_EN/../sites-enabled/onion_site"

# ==============================================================================
# 9. SERVICES & FIREWALL 
# ==============================================================================
if [ $ENABLE_SENTRY -eq 1 ] && [ -f "$CORE_DIR/neural_sentry.py" ]; then
    cp "$CORE_DIR/neural_sentry.py" /usr/local/bin/neural_sentry.py
    chmod +x /usr/local/bin/neural_sentry.py
    # FIX: Ensure script points to correct RAM log directory
    sed -i 's|/mnt/ram_logs/sentry.log|/var/log/tor/sentry.log|g' /usr/local/bin/neural_sentry.py
    
    cat > /etc/systemd/system/neural-sentry.service <<EOF
[Unit]
Description=Neural Sentry IPS
After=network.target tor@default.service
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/neural_sentry.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable neural-sentry
fi

log "Applying Balanced NFTables Rules..."
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Balanced NFTables Firewall (v9.1)
# Allows Tor functionality while blocking unsolicited external input.

flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # 1. Allow Loopback (Vital for Tor <-> Nginx)
        iifname "lo" accept

        # 2. Allow Established Connections (Replies from the internet)
        # This is critical for Tor to download directory info.
        ct state established,related accept

        # 3. Drop Invalid Packets
        ct state invalid drop

        # 4. ICMP (Ping) - Light rate limit
        ip protocol icmp icmp type { echo-request, echo-reply, destination-unreachable, time-exceeded } limit rate 5/second accept

        # 5. SSH Safety Valve (Will be uncommented if enabled)
        # tcp dport 22 accept

        # 6. Log and Drop everything else
        log prefix "FIREWALL-DROP: " drop
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF

# SSH Safety Logic (Simplified for the new rules)
if [ $ENABLE_SSH -eq 1 ]; then
    sed -i 's/# tcp dport 22/tcp dport 22/g' /etc/nftables.conf
    log "SSH Access Enabled in Firewall."
fi

if nft -c -f /etc/nftables.conf 2>/dev/null; then
    nft -f /etc/nftables.conf
    systemctl enable nftables 2>/dev/null || true
fi

# ==============================================================================
# 10. BOOTSTRAP
# ==============================================================================
log "Bootstrapping Network..."
systemctl daemon-reload
systemctl restart tor@default
systemctl restart nginx
[ $ENABLE_SENTRY -eq 1 ] && systemctl restart neural-sentry

trap - ERR
echo -n "Waiting for Onion Address generation"
COUNT=0
while [ ! -f "$TOR_HS/hostname" ] && [ $COUNT -lt 60 ]; do
    sleep 1; echo -n "."; COUNT=$((COUNT+1))
done
echo ""

# ==============================================================================
# 11. COMPLETION & MENU
# ==============================================================================
cat > /usr/local/bin/aegis-edit <<'EOF'
#!/bin/bash
nano /var/www/onion_site/index.html
chown -R www-data:www-data /var/www/onion_site
systemctl reload nginx
echo "Site Updated."
EOF
chmod +x /usr/local/bin/aegis-edit

ONION=$(cat "$TOR_HS/hostname" 2>/dev/null || echo "ERROR_GENERATING")
echo ""
echo "================================================================"
echo -e "${GREEN}>>> SYSTEM ONLINE: ${ONION} <<<${NC}"
echo "================================================================"

# 12. POST-INSTALL ACTIONS
echo ""
echo -e "${YELLOW}--- [ NEXT STEPS ] ---${NC}"
echo -e "To edit your website content:  ${CYAN}sudo aegis-edit${NC}"
echo -e "To monitor system health:      ${CYAN}sudo ./aegis_monitor.sh${NC}"
echo ""

read -p "Would you like to launch the System Monitor now? [Y/n]: " LAUNCH_MON
if [[ ! "$LAUNCH_MON" =~ ^[Nn]$ ]]; then
    if [ -f "$INSTALL_DIR/aegis_monitor.sh" ]; then
        chmod +x "$INSTALL_DIR/aegis_monitor.sh"
        exec "$INSTALL_DIR/aegis_monitor.sh"
    else
        warn "Monitor script not found in $INSTALL_DIR"
    fi
fi
