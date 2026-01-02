#!/bin/bash

################################################################################
# OnionSite-Aegis: Ultimate Master Installer
# Version: 5.1 (Double-Fallback Mode)
# Fixes: Handles Lua & WAF crashes automatically
################################################################################

# 1. INITIAL CONFIGURATION
# ------------------------------------------------------------------------------
set -o pipefail
# Custom Trap to print Nginx error if we fail near the end
trap 'echo -e "\n\033[0;31m[CRITICAL FAILURE] Script stopped at line $LINENO. Running diagnostics...\033[0m"; nginx -t 2>/dev/null || true; exit 1' ERR

# Note: We don't use 'set -e' because we need to handle errors gracefully
# in some sections (like optional module failures)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
INSTALL_DIR=$(pwd)
CORE_DIR="$INSTALL_DIR/core"
CONF_DIR="$INSTALL_DIR/conf"
LOG_FILE="/var/log/aegis_install.log"
TOR_DIR="/var/lib/tor"
HS_DIR="$TOR_DIR/hidden_service"
WEB_DIR="/var/www/onion_site"
NGINX_MODSEC_DIR="/etc/nginx/modsec"
LUA_DIR="/etc/nginx/lua"

# Tracking Flags
FAIL_WAF=0
FAIL_LUA=0
FAIL_FIREWALL=0

log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# 2. PRE-FLIGHT CHECKS & WIPE LOGIC
# ------------------------------------------------------------------------------
clear
echo -e "${GREEN}=== STARTING AEGIS SUITE DEPLOYMENT v5.1 ===${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] Must be run as root.${NC}"
   exit 1
fi

if [ ! -d "$CORE_DIR" ]; then
    echo -e "${RED}[ERROR] 'core/' directory not found. Please run inside the OnionSite-Aegis folder.${NC}"
    exit 1
fi

# --- WIPE LOGIC ---
if [ -d "$HS_DIR" ]; then
    echo ""
    echo -e "${YELLOW}[!] EXISTING INSTALLATION DETECTED ${NC}"
    echo "Do you want to WIPE the old keys and generate a NEW Onion Address?"
    read -p "Type 'wipe' to delete, or press ENTER to update in-place: " WIPE_CONFIRM

    if [[ "$WIPE_CONFIRM" == "wipe" ]]; then
        log "Wiping system..."
        systemctl stop tor nginx neural-sentry 2>/dev/null || true
        rm -rf "$HS_DIR" "$WEB_DIR"
        rm -f /etc/nginx/sites-enabled/onion_site
        success "System Wiped. New identity will be generated."
    fi
fi

# 3. DEPENDENCIES & KERNEL
# ------------------------------------------------------------------------------
log "Installing System Dependencies..."
apt-get update -q
DEPS="curl wget tor nginx nftables python3-pip python3-stem python3-inotify \
libnginx-mod-http-lua libmodsecurity3 libnginx-mod-http-modsecurity \
apparmor-utils"

apt-get install -y --no-install-recommends $DEPS
success "Dependencies installed."

# Python Deps
if [ -f "$CORE_DIR/neural_sentry.py" ]; then
    pip3 install requests psutil --break-system-packages 2>/dev/null || true
fi

# Kernel Hardening
if [ -f "$CONF_DIR/sysctl_hardened.conf" ]; then
    cp "$CONF_DIR/sysctl_hardened.conf" /etc/sysctl.d/99-aegis.conf
    success "Using enhanced sysctl configuration"
else
    warn "Enhanced sysctl config not found, using minimal configuration"
    cat > /etc/sysctl.d/99-aegis.conf <<EOF
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
kernel.dmesg_restrict = 1
EOF
fi
sysctl --system >/dev/null 2>&1 || warn "Kernel hardening limited."

# 4. CORE MODULE: RAM LOGS
# ------------------------------------------------------------------------------
if [ -f "$CORE_DIR/init_ram_logs.sh" ]; then
    chmod +x "$CORE_DIR/init_ram_logs.sh"
    "$CORE_DIR/init_ram_logs.sh"
fi

# 5. TOR CONFIGURATION
# ------------------------------------------------------------------------------
log "Configuring Tor..."
systemctl stop tor 2>/dev/null || true
cat > /etc/tor/torrc <<EOF
DataDirectory /var/lib/tor
PidFile /run/tor/tor.pid
RunAsDaemon 1
User debian-tor

# Control Port for Neural Sentry
ControlPort 127.0.0.1:9051
CookieAuthentication 1

# Hidden Service
HiddenServiceDir $HS_DIR
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80

# Privacy & Security Hardening
Sandbox 1
NoExec 1
HardwareAccel 1
SafeLogging 1
AvoidDiskWrites 1

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
PaddingDistribution piatkowski

# Guard Node Privacy (Enhanced)
UseEntryGuards 1
NumEntryGuards 3
GuardLifetime 30 days
NumDirectoryGuards 3
EntryNodes {}
StrictEntryNodes 0

# Exit Node Restrictions
ExitNodes {}
ExcludeNodes {}
StrictNodes 0

# Additional Privacy Settings
PublishServerDescriptor 0
ClientOnly 1
FetchDirInfoEarly 0
FetchUselessDescriptors 0
LearnCircuitBuildTimeout 0

# Logging Privacy (minimal)
Log notice file /mnt/ram_logs/tor/tor.log
SafeLogging 1
AvoidDiskWrites 1
EOF
mkdir -p "$HS_DIR"
chown -R debian-tor:debian-tor "$TOR_DIR"
chmod 700 "$TOR_DIR"
chmod 700 "$HS_DIR"

# 6. NGINX, LUA & WAF
# ------------------------------------------------------------------------------
log "Configuring Nginx Suite..."

# A. Lua
mkdir -p "$LUA_DIR"
if [ -f "$CORE_DIR/response_padding.lua" ]; then
    cp "$CORE_DIR/response_padding.lua" "$LUA_DIR/response_padding.lua"
    chmod 644 "$LUA_DIR/response_padding.lua"
    # Use body_filter for response padding (runs after content is generated)
    LUA_CONFIG="body_filter_by_lua_file $LUA_DIR/response_padding.lua;"
else
    LUA_CONFIG="# Lua script missing"
fi

# B. WAF
mkdir -p "$NGINX_MODSEC_DIR"
if [ ! -f "$NGINX_MODSEC_DIR/modsecurity.conf" ]; then
    wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -O "$NGINX_MODSEC_DIR/modsecurity.conf"
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$NGINX_MODSEC_DIR/modsecurity.conf"
fi
echo "include $NGINX_MODSEC_DIR/modsecurity.conf" > "$NGINX_MODSEC_DIR/main.conf"

# C. Content
if [ ! -f "$WEB_DIR/index.html" ]; then
    echo ""
    echo -e "${CYAN}--- CUSTOMIZE SITE ---${NC}"
    read -p "1. Page Title [Default: Secure Onion]: " USER_TITLE
    USER_TITLE=${USER_TITLE:-"Secure Onion"}
    read -p "2. Headline [Default: Welcome]: " USER_H1
    USER_H1=${USER_H1:-"Welcome"}
    read -p "3. Message [Default: Connection Secure]: " USER_MSG
    USER_MSG=${USER_MSG:-"Connection Secure."}

    mkdir -p "$WEB_DIR"
    cat > "$WEB_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>${USER_TITLE}</title>
    <style>
        body { font-family: 'Courier New', monospace; background-color: #0d1117; color: #00ff00; text-align: center; margin-top: 100px; }
        h1 { border-bottom: 1px solid #333; display: inline-block; padding-bottom: 10px; }
        .footer { margin-top: 50px; font-size: 0.8em; color: #555; }
    </style>
</head>
<body>
    <h1>${USER_H1}</h1>
    <p>${USER_MSG}</p>
    <div class="footer">Protected by Aegis v5.1</div>
</body>
</html>
EOF
fi
chown -R www-data:www-data "$WEB_DIR"
chmod 755 "$WEB_DIR"

# D. Server Block
cat > /etc/nginx/sites-available/onion_site <<EOF
server {
    listen 127.0.0.1:80;
    server_name localhost;
    root $WEB_DIR;
    index index.html;
    server_tokens off;
    add_header X-Frame-Options DENY;

    modsecurity on;
    modsecurity_rules_file $NGINX_MODSEC_DIR/main.conf;

    $LUA_CONFIG

    location / { try_files \$uri \$uri/ =404; }
}
EOF

# Test nginx configuration before enabling
log "Testing Nginx configuration..."
if ! nginx -t 2>/dev/null; then
    warn "Nginx configuration test failed, attempting to fix..."
    # Remove problematic directives and retest
    sed -i 's/modsecurity on;/#modsecurity on;/g' /etc/nginx/sites-available/onion_site
    sed -i 's/modsecurity_rules_file/#modsecurity_rules_file/g' /etc/nginx/sites-available/onion_site
    sed -i 's/body_filter_by_lua_file/#body_filter_by_lua_file/g' /etc/nginx/sites-available/onion_site
    if ! nginx -t 2>/dev/null; then
        error "Nginx configuration is invalid even after removing optional modules"
        nginx -t
        exit 1
    fi
    FAIL_WAF=1
    FAIL_LUA=1
fi

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/onion_site /etc/nginx/sites-enabled/
success "Nginx configuration validated"

# 7. SERVICES
# ------------------------------------------------------------------------------
# Neural Sentry (install but don't start yet - wait for Tor)
if [ -f "$CORE_DIR/neural_sentry.py" ]; then
    cp "$CORE_DIR/neural_sentry.py" /usr/local/bin/neural_sentry.py
    chmod +x /usr/local/bin/neural_sentry.py
    cat > /etc/systemd/system/neural-sentry.service <<EOF
[Unit]
Description=Neural Sentry - Privacy-Focused Active Defense
After=network.target tor.service
Requires=tor.service
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/neural_sentry.py
Restart=always
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable neural-sentry
    # Don't start yet - will start after Tor is confirmed running
    success "Neural Sentry service installed (will start after Tor)"
fi

# Privacy Monitor
if [ -f "$CORE_DIR/privacy_monitor.sh" ]; then
    cp "$CORE_DIR/privacy_monitor.sh" /usr/local/bin/privacy_monitor.sh
    chmod +x /usr/local/bin/privacy_monitor.sh
    cat > /etc/systemd/system/privacy-monitor.service <<EOF
[Unit]
Description=Privacy Monitor - Privacy Compliance Checker
[Service]
Type=oneshot
ExecStart=/usr/local/bin/privacy_monitor.sh
User=root
EOF
    cat > /etc/systemd/system/privacy-monitor.timer <<EOF
[Unit]
Description=Privacy Monitor Timer (runs every 6 hours)
[Timer]
OnBootSec=1h
OnUnitActiveSec=6h
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable privacy-monitor.timer
    systemctl start privacy-monitor.timer
    success "Privacy Monitor timer installed"
fi

# Traffic Analysis Protection
if [ -f "$CORE_DIR/traffic_analysis_protection.sh" ]; then
    cp "$CORE_DIR/traffic_analysis_protection.sh" /usr/local/bin/traffic_analysis_protection.sh
    chmod +x /usr/local/bin/traffic_analysis_protection.sh
    /usr/local/bin/traffic_analysis_protection.sh || warn "Traffic analysis protection setup had issues"
fi

# 8. FIREWALL
# ------------------------------------------------------------------------------
log "Configuring NFTables firewall..."
if [ -f "$CONF_DIR/nftables.conf" ]; then
    cp "$CONF_DIR/nftables.conf" /etc/nftables.conf
    success "Using enhanced NFTables configuration"
else
    warn "Enhanced firewall config not found, using minimal configuration"
    cat > /etc/nftables.conf <<EOF
flush ruleset
table inet filter {
    chain input { type filter hook input priority 0; policy drop; iif "lo" accept; ct state established,related accept; tcp dport 22 accept; }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF
fi
nft -f /etc/nftables.conf 2>/dev/null || FAIL_FIREWALL=1
if [ $FAIL_FIREWALL -eq 0 ]; then
    systemctl enable nftables 2>/dev/null || true
    success "Firewall configured"
fi

# 9. BOOTSTRAP (ROBUST MODE)
# ------------------------------------------------------------------------------
log "Bootstrapping..."
systemctl restart tor
COUNT=0
while [ ! -f "$HS_DIR/hostname" ]; do
    sleep 2
    COUNT=$((COUNT+1))
    if [ $COUNT -gt 25 ]; then 
        log "Tor taking longer than expected, restarting..."
        systemctl restart tor
        sleep 5
    fi
    if [ $COUNT -gt 50 ]; then
        error "Tor failed to create hidden service after 100 seconds"
        exit 1
    fi
done
success "Hidden service created successfully"

# Now start Neural Sentry (Tor is confirmed running)
if systemctl is-enabled neural-sentry >/dev/null 2>&1; then
    log "Starting Neural Sentry..."
    systemctl start neural-sentry || warn "Neural Sentry failed to start (may retry)"
    sleep 2
    if systemctl is-active --quiet neural-sentry; then
        success "Neural Sentry started successfully"
    else
        warn "Neural Sentry is not running (check logs if needed)"
    fi
fi

log "Starting Nginx..."
# ATTEMPT 1: Normal Start
if ! systemctl restart nginx; then
    warn "Start failed. Trying WAF-Safe Mode..."
    FAIL_WAF=1
    sed -i 's/modsecurity on;/#modsecurity on;/g' /etc/nginx/sites-available/onion_site
    sed -i 's/modsecurity_rules_file/#modsecurity_rules_file/g' /etc/nginx/sites-available/onion_site
    
    # ATTEMPT 2: WAF Disabled
    if ! systemctl restart nginx; then
        warn "Start failed again. Trying Lua-Safe Mode..."
        FAIL_LUA=1
        sed -i 's/body_filter_by_lua_file/#body_filter_by_lua_file/g' /etc/nginx/sites-available/onion_site
        
        # ATTEMPT 3: All Modules Disabled
        if ! systemctl restart nginx; then
            echo -e "${RED}[CRITICAL] Nginx failed in ALL modes.${NC}"
            nginx -t
            exit 1
        fi
    fi
fi

# 10. COMPLETION
# ------------------------------------------------------------------------------
# Create edit shortcut
cat > /usr/local/bin/aegis-edit <<'EDITEOF'
#!/bin/bash
nano /var/www/onion_site/index.html
chown -R www-data:www-data /var/www/onion_site
systemctl reload nginx
EDITEOF
chmod +x /usr/local/bin/aegis-edit

ONION=$(cat "$HS_DIR/hostname")
echo ""
echo "================================================================"
echo -e "${GREEN}>>> LIVE: ${ONION} <<<${NC}"
echo "----------------------------------------------------------------"
[ $FAIL_WAF -eq 0 ] && echo -e " [OK] WAF" || echo -e " [OFF] WAF (Failed)"
[ $FAIL_LUA -eq 0 ] && echo -e " [OK] Lua" || echo -e " [OFF] Lua (Failed)"
[ $FAIL_FIREWALL -eq 0 ] && echo -e " [OK] Firewall" || echo -e " [OFF] Firewall (Restricted)"
echo "----------------------------------------------------------------"
echo -e "${CYAN}Edit site with:${NC} aegis-edit"
echo "================================================================"
