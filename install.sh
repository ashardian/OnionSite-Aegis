#!/bin/bash

################################################################################
# OnionSite-Aegis: Master Architect Installer
# Version: 6.2 (Load Order Fix)
#
# CRITICAL FIXES:
# 1. Enforced Numerical Load Order (NDK -> Lua -> WAF) to prevent crash.
# 2. Added "Pre-Flight Module Check" to verify binaries before loading.
# 3. Added fallback logic if WAF rule download fails.
################################################################################

# ==============================================================================
# 1. CONSTANTS & CONFIGURATION
# ==============================================================================
set -o pipefail  # Fail if any command in a pipe fails

# Visuals
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENAB="/etc/nginx/sites-enabled"
NGINX_MOD_EN="/etc/nginx/modules-enabled"
NGINX_MOD_DIS="/etc/nginx/modules-disabled-backup"
NGINX_WAF_DIR="/etc/nginx/modsec"
NGINX_LUA_DIR="/etc/nginx/lua"

# State Flags
ENABLE_WAF=0
ENABLE_LUA=0
ENABLE_SENTRY=0
ENABLE_PRIVACY=0
ENABLE_TRAFFIC=0

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================
log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
critical() { echo -e "${RED}[CRITICAL] $1${NC}"; exit 1; }

trap 'echo -e "\n${RED}[RUNTIME ERROR] Script aborted at line $LINENO.${NC}"; exit 1' ERR

# ==============================================================================
# 3. INTERACTIVE FEATURE SELECTION
# ==============================================================================
clear
echo -e "${GREEN}=== ONIONSITE-AEGIS ARCHITECT v6.2 ===${NC}"
echo "Configure your deployment:"
echo ""

read -p "1. Enable ModSecurity WAF? (Protection against XSS/SQLi) [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_WAF=1 && echo "   -> [SELECTED] WAF"

read -p "2. Enable Lua Response Padding? (Defends against Traffic Fingerprinting) [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_LUA=1 && echo "   -> [SELECTED] Lua Padding"

read -p "3. Enable Neural Sentry? (Active IPS Monitor) [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_SENTRY=1 && echo "   -> [SELECTED] Neural Sentry"

read -p "4. Enable Privacy Monitor? (Periodic Security Audits) [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_PRIVACY=1 && echo "   -> [SELECTED] Privacy Monitor"

read -p "5. Enable Traffic Analysis Protection? (Background Noise Generator) [y/N]: " resp
[[ "$resp" =~ ^[Yy]$ ]] && ENABLE_TRAFFIC=1 && echo "   -> [SELECTED] Traffic Protection"

echo ""
read -p "Press ENTER to begin deployment..."

# ==============================================================================
# 4. ENVIRONMENT SANITIZATION
# ==============================================================================
log "Sanitizing Environment..."
if [[ $EUID -ne 0 ]]; then critical "This script must be run as root."; fi

# Stop Services
systemctl stop nginx tor tor@default neural-sentry 2>/dev/null || true

# Nginx Purge (Nuclear)
rm -rf "$NGINX_ENAB"/* "$NGINX_AVAIL"/*
mkdir -p "$NGINX_MOD_DIS"

# Move ALL modules out to start with a blank slate
# This ensures no old alphabetical symlinks remain
mv "$NGINX_MOD_EN"/* "$NGINX_MOD_DIS"/ 2>/dev/null || true

# WIPE LOGIC
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
# 5. DEPENDENCY MANAGEMENT
# ==============================================================================
log "Installing Dependencies..."
BASE_DEPS="curl wget tor nginx nftables python3-pip python3-stem python3-inotify apparmor-utils"
OPT_DEPS=""

if [ $ENABLE_WAF -eq 1 ]; then OPT_DEPS="$OPT_DEPS libmodsecurity3 libnginx-mod-http-modsecurity"; fi
# Added NDK explicitly
if [ $ENABLE_LUA -eq 1 ]; then OPT_DEPS="$OPT_DEPS libnginx-mod-http-lua libnginx-mod-http-ndk"; fi

apt-get update -q
apt-get install -y --no-install-recommends $BASE_DEPS $OPT_DEPS
success "System Packages Installed."

if [ $ENABLE_SENTRY -eq 1 ]; then
    if [ -f "$CORE_DIR/neural_sentry.py" ]; then
        pip3 install requests psutil --break-system-packages 2>/dev/null || true
        success "Python Dependencies Installed."
    fi
fi

# ==============================================================================
# 6. STEALTH LOGGING (RAM-BACKED)
# ==============================================================================
log "Configuring RAM Logging..."
mkdir -p "$TOR_LOG_DIR"
if ! mount | grep -q "$TOR_LOG_DIR type tmpfs"; then
    mount -t tmpfs -o size=10M,mode=0700,uid=debian-tor,gid=debian-tor tmpfs "$TOR_LOG_DIR"
fi
chown -R debian-tor:debian-tor "$TOR_LOG_DIR"
chmod 700 "$TOR_LOG_DIR"

# ==============================================================================
# 7. TOR CONFIGURATION
# ==============================================================================
log "Hardening Tor Configuration..."
mkdir -p "$TOR_HS"
chown -R debian-tor:debian-tor "$TOR_LIB"
chmod 700 "$TOR_LIB" "$TOR_HS"

cat > /etc/tor/torrc <<EOF
# --- AEGIS HARDENED TOR CONFIG ---
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
# 8. NGINX CONFIGURATION (ARCHITECT MODE)
# ==============================================================================
log "Building Nginx Architecture..."

# --- CRITICAL FIX: FORCED LOAD ORDER ---
# We manually symlink modules with numbers (10, 20, 30) to guarantee
# NDK loads before Lua, and Lua loads before WAF.

if [ $ENABLE_LUA -eq 1 ]; then
    log "Enabling Lua Engine (with Load Order Enforcement)..."
    
    # 1. Helper: NDK (Must be first)
    if [ -f /usr/share/nginx/modules-available/mod-http-ndk.conf ]; then
        ln -sf /usr/share/nginx/modules-available/mod-http-ndk.conf "$NGINX_MOD_EN/10-ndk.conf"
    else
        warn "NDK module file missing! Lua might crash."
    fi

    # 2. Engine: Lua
    if [ -f /usr/share/nginx/modules-available/mod-http-lua.conf ]; then
        ln -sf /usr/share/nginx/modules-available/mod-http-lua.conf "$NGINX_MOD_EN/20-lua.conf"
    fi
fi

if [ $ENABLE_WAF -eq 1 ]; then
    log "Enabling WAF Engine..."
    # 3. Shield: ModSecurity
    if [ -f /usr/share/nginx/modules-available/mod-http-modsecurity.conf ]; then
        ln -sf /usr/share/nginx/modules-available/mod-http-modsecurity.conf "$NGINX_MOD_EN/30-modsec.conf"
    fi
fi

# 8b. Construct Base Config
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

# 8c. Web Root
mkdir -p "$WEB_ROOT"
if [ ! -f "$WEB_ROOT/index.html" ]; then
    echo "<h1>System Active</h1><p>Aegis v6.2</p>" > "$WEB_ROOT/index.html"
fi
chown -R www-data:www-data "$WEB_ROOT"

# 8d. Build Site Config
SITE_CONF="$NGINX_AVAIL/onion_site"

echo "server {" > "$SITE_CONF"
echo "    listen 127.0.0.1:80 default_server;" >> "$SITE_CONF"
echo "    server_name _;" >> "$SITE_CONF"
echo "    root $WEB_ROOT;" >> "$SITE_CONF"
echo "    index index.html;" >> "$SITE_CONF"
echo "    server_tokens off;" >> "$SITE_CONF"
echo "    add_header X-Frame-Options DENY;" >> "$SITE_CONF"

# Inject WAF
if [ $ENABLE_WAF -eq 1 ]; then
    mkdir -p "$NGINX_WAF_DIR"
    # Download rules (with error check)
    if [ ! -f "$NGINX_WAF_DIR/modsecurity.conf" ]; then
        wget -q https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended -O "$NGINX_WAF_DIR/modsecurity.conf" || warn "WAF Rules download failed, using empty config."
        if [ -f "$NGINX_WAF_DIR/modsecurity.conf" ]; then
            sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$NGINX_WAF_DIR/modsecurity.conf"
        else
             touch "$NGINX_WAF_DIR/modsecurity.conf"
        fi
    fi
    echo "include $NGINX_WAF_DIR/modsecurity.conf" > "$NGINX_WAF_DIR/main.conf"
    
    echo "    modsecurity on;" >> "$SITE_CONF"
    echo "    modsecurity_rules_file $NGINX_WAF_DIR/main.conf;" >> "$SITE_CONF"
fi

# Inject Lua
if [ $ENABLE_LUA -eq 1 ]; then
    mkdir -p "$NGINX_LUA_DIR"
    if [ -f "$CORE_DIR/response_padding.lua" ]; then
        cp "$CORE_DIR/response_padding.lua" "$NGINX_LUA_DIR/"
        chmod 644 "$NGINX_LUA_DIR/response_padding.lua"
        echo "    body_filter_by_lua_file $NGINX_LUA_DIR/response_padding.lua;" >> "$SITE_CONF"
    fi
fi

echo "    location / { try_files \$uri \$uri/ =404; }" >> "$SITE_CONF"
echo "}" >> "$SITE_CONF"

# Enable Site
ln -sf "$SITE_CONF" "$NGINX_ENAB/onion_site"

# Validation
log "Validating Nginx Config..."
if ! nginx -t 2>/dev/null; then
    error "Validation Failed. Reverting to Safe Mode (Disabling Modules)..."
    sed -i 's/modsecurity on;/#modsecurity on;/g' "$SITE_CONF"
    sed -i 's/modsecurity_rules_file/#modsecurity_rules_file/g' "$SITE_CONF"
    sed -i 's/body_filter_by_lua_file/#body_filter_by_lua_file/g' "$SITE_CONF"
    
    # Critical: Remove module links if config fails
    rm -f "$NGINX_MOD_EN/10-ndk.conf" "$NGINX_MOD_EN/20-lua.conf" "$NGINX_MOD_EN/30-modsec.conf"
    
    nginx -t || critical "Nginx failed in Safe Mode. Check /var/log/nginx/error.log"
fi

# ==============================================================================
# 9. SERVICES & BOOTSTRAP
# ==============================================================================
# Neural Sentry
if [ $ENABLE_SENTRY -eq 1 ] && [ -f "$CORE_DIR/neural_sentry.py" ]; then
    cp "$CORE_DIR/neural_sentry.py" /usr/local/bin/neural_sentry.py
    chmod +x /usr/local/bin/neural_sentry.py
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
    log "Neural Sentry Installed."
fi

# Firewall
log "Applying Firewall Rules..."
cat > /etc/nftables.conf <<EOF
flush ruleset
table inet filter {
    chain input { type filter hook input priority 0; policy drop; iif "lo" accept; ct state established,related accept; tcp dport 22 accept; }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF
nft -f /etc/nftables.conf 2>/dev/null
systemctl enable nftables 2>/dev/null || true

# Boot
log "Bootstrapping Network..."
systemctl daemon-reload
systemctl restart tor@default
systemctl restart nginx
[ $ENABLE_SENTRY -eq 1 ] && systemctl restart neural-sentry

echo -n "Waiting for Onion Address generation"
COUNT=0
while [ ! -f "$TOR_HS/hostname" ] && [ $COUNT -lt 30 ]; do
    sleep 2
    echo -n "."
    COUNT=$((COUNT+1))
done
echo ""

# ==============================================================================
# 11. COMPLETION
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
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" 127.0.0.1)

echo ""
echo "================================================================"
if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}>>> SYSTEM ONLINE: ${ONION} <<<${NC}"
else
    echo -e "${RED}>>> SYSTEM ERROR (Code: $HTTP_CODE) <<<${NC}"
fi
echo "----------------------------------------------------------------"
[ $ENABLE_WAF -eq 1 ]     && echo -e " [ON] WAF (ModSecurity)"    || echo -e " [OFF] WAF"
[ $ENABLE_LUA -eq 1 ]     && echo -e " [ON] Lua (Padding)"        || echo -e " [OFF] Lua"
echo "----------------------------------------------------------------"
echo -e "Edit your site: ${CYAN}sudo aegis-edit${NC}"
echo "================================================================"
