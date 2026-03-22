#!/bin/bash

################################################################################
# OnionSite-Aegis: Master Architect Installer
# Version: 10.0 (Bare Metal Edition)
#
# CHANGELOG:
# v10.0: Fixed nginx -t failing due to missing unicode.mapping file.
#        ModSecurity's SecUnicodeMapFile directive uses a relative path —
#        unicode.mapping must be downloaded alongside modsecurity.conf.
#        Also added absolute path rewrite for SecUnicodeMapFile so it is
#        immune to working-directory changes.
#        Fixed tor --verify-config stderr suppression (now shows errors).
#        Fixed nginx -t stderr suppression (now shows errors + logs them).
#        Fixed neural-sentry restart guard (skips if unit was not deployed).
#        Fixed privacy-monitor restart (was restarting .timer, now correct).
#        Fixed modules-available path: Debian uses /usr/share/nginx/modules-
#        available which may not exist; added fallback to dpkg-query path.
#        Fixed: modsec minimal fallback conf did not include SecUnicodeMapFile
#        (not needed in minimal mode — harmless, but clarified in comments).
#        Added nginx -t dry-run BEFORE applying firewall rules so a bad config
#        does not leave the system locked behind nftables with no nginx.
# v10.0: Removed Docker support entirely. Added detect_tor_service().
#        Fixed INSTALL_DIR. Added set -E. Privacy monitor as systemd timer.
# v9.0: Integrated Advanced Firewall, SSH Safety Valve, Post-Install Dashboard.
################################################################################

# ==============================================================================
# 1. CONSTANTS & CONFIGURATION
# ==============================================================================
set -E
set -o pipefail

# Visuals
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# System Paths
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# ModSecurity upstream URLs
MODSEC_CONF_URL="https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended"
MODSEC_UNICODE_URL="https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping"

# Runtime
TOR_SERVICE="tor"

# State Flags (Defaults set to YES/1)
ENABLE_WAF=1
ENABLE_LUA=1
ENABLE_SENTRY=1
ENABLE_PRIVACY=1
ENABLE_TRAFFIC=1
ENABLE_SSH=0      # Default to 0 (Safe) - User must enable it for Cloud VMs

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================
log()      { echo -e "${BLUE}[INFO]${NC} $1"       | tee -a "$LOG_FILE"; }
success()  { echo -e "${GREEN}[SUCCESS]${NC} $1"   | tee -a "$LOG_FILE"; }
warn()     { echo -e "${YELLOW}[WARN]${NC} $1"     | tee -a "$LOG_FILE"; }
error()    { echo -e "${RED}[ERROR]${NC} $1"       | tee -a "$LOG_FILE"; }
critical() { echo -e "${RED}[CRITICAL] $1${NC}"    | tee -a "$LOG_FILE"; exit 1; }

detect_tor_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        TOR_SERVICE="tor@default"
        return
    fi

    # Debian 13 (Trixie) and later: tor.service is a dummy master (ExecStart=/bin/true).
    # The real instance is always tor@default.service. Detect this by checking
    # whether tor.service ExecStart is /bin/true, which is the definitive signal.
    local tor_exec
    tor_exec=$(systemctl show tor.service --property=ExecStart 2>/dev/null)
    if echo "$tor_exec" | grep -q '/bin/true'; then
        TOR_SERVICE="tor@default"
        return
    fi

    # Fallback: if tor@default is explicitly active, prefer it
    if systemctl is-active tor@default.service >/dev/null 2>&1; then
        TOR_SERVICE="tor@default"
        return
    fi

    # Traditional single-instance setup
    TOR_SERVICE="tor"
}

# ==============================================================================
# 3. ENVIRONMENT & HYGIENE
# ==============================================================================
check_environment() {
    if [[ $EUID -ne 0 ]]; then critical "This script must be run as root."; fi

    touch "$LOG_FILE" 2>/dev/null || critical "Cannot write to $LOG_FILE"
    log "Performing Pre-Flight Environment Checks..."

    # Hygiene: Remove Python bytecode
    if find "$INSTALL_DIR" -type d -name "__pycache__" | grep -q .; then
        find "$INSTALL_DIR" -type d -name "__pycache__" -exec rm -rf {} +
    fi

    detect_tor_service
    log "Detected Tor service unit: $TOR_SERVICE"
}

# ==============================================================================
# 4. INTERACTIVE FEATURE SELECTION (Default = YES)
# ==============================================================================
clear
echo -e "${GREEN}=== ONIONSITE-AEGIS ARCHITECT v10.0 ===${NC}"
check_environment
echo ""
echo "Configure your deployment (Press ENTER to accept defaults):"

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
BASE_DEPS=(curl wget tor nginx nftables python3-pip python3-stem python3-inotify apparmor-utils)
OPT_DEPS=()

if [ $ENABLE_WAF -eq 1 ]; then OPT_DEPS+=(libmodsecurity3 libnginx-mod-http-modsecurity); fi
if [ $ENABLE_LUA -eq 1 ]; then OPT_DEPS+=(libnginx-mod-http-lua libnginx-mod-http-ndk); fi

DEBIAN_FRONTEND=noninteractive apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${BASE_DEPS[@]}" "${OPT_DEPS[@]}"
success "System Packages Installed."

if [ $ENABLE_SENTRY -eq 1 ]; then
    if [ -f "$CORE_DIR/neural_sentry.py" ]; then
        pip3 install requests psutil --break-system-packages 2>/dev/null || true
        success "Python Dependencies Installed."
    fi
fi

# ==============================================================================
# 7. STEALTH LOGGING & HARDENING
# ==============================================================================
log "Configuring RAM Logging..."
mkdir -p "$TOR_LOG_DIR"
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
User debian-tor
ControlPort 127.0.0.1:9051
CookieAuthentication 1
HiddenServiceDir $TOR_HS
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:80
SafeLogging 1
AvoidDiskWrites 1
Log notice file $TOR_LOG_DIR/notices.log
EOF

# ==============================================================================
# 8. NGINX ARCHITECTURE
# ==============================================================================
log "Building Nginx Architecture..."

# ── Module Linking ─────────────────────────────────────────────────────────────
# Debian Trixie ships modules under /usr/share/nginx/modules-available/.
# If that path is absent (older builds), fall back to dpkg-query.
find_nginx_module() {
    local modname="$1"
    local candidate="/usr/share/nginx/modules-available/${modname}.conf"
    if [ -f "$candidate" ]; then
        echo "$candidate"
        return
    fi
    # Fallback: ask dpkg where the .conf landed
    dpkg -L "libnginx-mod-$(echo "$modname" | sed 's/mod-//')" 2>/dev/null \
        | grep "\.conf$" | head -1
}

if [ $ENABLE_LUA -eq 1 ]; then
    NDK_CONF=$(find_nginx_module "mod-http-ndk")
    LUA_CONF=$(find_nginx_module "mod-http-lua")
    [ -n "$NDK_CONF" ] && ln -sf "$NDK_CONF" "$NGINX_MOD_EN/10-ndk.conf"
    [ -n "$LUA_CONF" ] && ln -sf "$LUA_CONF"  "$NGINX_MOD_EN/20-lua.conf"
fi
if [ $ENABLE_WAF -eq 1 ]; then
    MODSEC_CONF=$(find_nginx_module "mod-http-modsecurity")
    [ -n "$MODSEC_CONF" ] && ln -sf "$MODSEC_CONF" "$NGINX_MOD_EN/30-modsec.conf"
fi

# ── Base nginx.conf ────────────────────────────────────────────────────────────
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

# ── Web Content ────────────────────────────────────────────────────────────────
mkdir -p "$WEB_ROOT"
if [ ! -f "$WEB_ROOT/index.html" ]; then
    echo "<h1>Authorized Access Only</h1><p>Aegis v10.0 Protected</p>" > "$WEB_ROOT/index.html"
fi
chown -R www-data:www-data "$WEB_ROOT"

# ── Site Config Builder ────────────────────────────────────────────────────────
SITE_CONF="/etc/nginx/sites-available/onion_site"
{
    echo "server {"
    echo "    listen 127.0.0.1:80 default_server;"
    echo "    server_name _;"
    echo "    root $WEB_ROOT;"
    echo "    index index.html;"
    echo "    server_tokens off;"
    echo "    add_header X-Frame-Options DENY;"
} > "$SITE_CONF"

# ── WAF (ModSecurity) ──────────────────────────────────────────────────────────
if [ $ENABLE_WAF -eq 1 ]; then
    mkdir -p "$NGINX_WAF_DIR"

    # ── FIX: Download modsecurity.conf-recommended + unicode.mapping together ──
    # The recommended conf contains:  SecUnicodeMapFile unicode.mapping 20127
    # ModSecurity resolves this path relative to the directory of the conf file
    # that contains the directive, so unicode.mapping MUST live in NGINX_WAF_DIR.
    # Without it, nginx -t fails with "Failed to locate the unicode map file".

    if [ ! -f "$NGINX_WAF_DIR/modsecurity.conf" ]; then
        log "Downloading ModSecurity recommended configuration..."
        if wget -q "$MODSEC_CONF_URL" -O "$NGINX_WAF_DIR/modsecurity.conf"; then
            success "Downloaded modsecurity.conf-recommended."
        else
            warn "Could not download modsecurity.conf-recommended; creating minimal local config."
            # Minimal config — does NOT reference unicode.mapping, so no mapping needed.
            cat > "$NGINX_WAF_DIR/modsecurity.conf" <<EOFWAF
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
EOFWAF
        fi
    fi

    # ── Always download unicode.mapping when using the full recommended conf ──
    # Check whether the conf actually references SecUnicodeMapFile before forcing
    # a download — the minimal fallback above does not need it.
    if grep -q "SecUnicodeMapFile" "$NGINX_WAF_DIR/modsecurity.conf" 2>/dev/null; then
        if [ ! -f "$NGINX_WAF_DIR/unicode.mapping" ]; then
            log "Downloading unicode.mapping (required by SecUnicodeMapFile)..."
            if ! wget -q "$MODSEC_UNICODE_URL" -O "$NGINX_WAF_DIR/unicode.mapping"; then
                warn "Could not download unicode.mapping. Rewriting SecUnicodeMapFile to be safe."
                # If we can't get the file, remove the directive so nginx -t passes.
                sed -i '/SecUnicodeMapFile/d' "$NGINX_WAF_DIR/modsecurity.conf"
            else
                success "Downloaded unicode.mapping."
                # Rewrite the directive to use an absolute path — immune to cwd changes.
                sed -i "s|SecUnicodeMapFile unicode.mapping|SecUnicodeMapFile $NGINX_WAF_DIR/unicode.mapping|g" \
                    "$NGINX_WAF_DIR/modsecurity.conf"
            fi
        else
            # File already present — still ensure the path is absolute.
            sed -i "s|SecUnicodeMapFile unicode.mapping|SecUnicodeMapFile $NGINX_WAF_DIR/unicode.mapping|g" \
                "$NGINX_WAF_DIR/modsecurity.conf" 2>/dev/null || true
        fi
    fi

    # Enable blocking mode
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' "$NGINX_WAF_DIR/modsecurity.conf"

    echo "include $NGINX_WAF_DIR/modsecurity.conf" > "$NGINX_WAF_DIR/main.conf"
    echo "    modsecurity on;"                              >> "$SITE_CONF"
    echo "    modsecurity_rules_file $NGINX_WAF_DIR/main.conf;" >> "$SITE_CONF"
fi

# ── Lua Response Padding ───────────────────────────────────────────────────────
if [ $ENABLE_LUA -eq 1 ] && [ -f "$CORE_DIR/response_padding.lua" ]; then
    mkdir -p "$NGINX_LUA_DIR"
    cp "$CORE_DIR/response_padding.lua" "$NGINX_LUA_DIR/"
    chmod 644 "$NGINX_LUA_DIR/response_padding.lua"
    echo "    body_filter_by_lua_file $NGINX_LUA_DIR/response_padding.lua;" >> "$SITE_CONF"
fi

echo "    location / { try_files \$uri \$uri/ =404; }" >> "$SITE_CONF"
echo "}"                                               >> "$SITE_CONF"

ln -sf "$SITE_CONF" "/etc/nginx/sites-enabled/onion_site"

# ── FIX: Validate nginx config HERE, before applying firewall ─────────────────
# Doing this before nftables is applied means a bad config doesn't leave the
# system locked behind a restrictive firewall with a dead nginx.
log "Validating Nginx configuration (pre-firewall)..."
NGINX_TEST_ERR=$( nginx -t 2>&1 )
if echo "$NGINX_TEST_ERR" | grep -q "test failed"; then
    error "Nginx configuration test failed:"
    echo "$NGINX_TEST_ERR" | tee -a "$LOG_FILE"
    critical "nginx -t failed. Review errors above and fix before retrying."
fi
success "Nginx configuration OK."

# ==============================================================================
# 9. SERVICES & FIREWALL
# ==============================================================================
if [ $ENABLE_SENTRY -eq 1 ] && [ -f "$CORE_DIR/neural_sentry.py" ]; then
    cp "$CORE_DIR/neural_sentry.py" /usr/local/bin/neural_sentry.py
    chmod +x /usr/local/bin/neural_sentry.py
    sed -i 's|/mnt/ram_logs/sentry.log|/var/log/tor/sentry.log|g' /usr/local/bin/neural_sentry.py

    cat > /etc/systemd/system/neural-sentry.service <<EOF
[Unit]
Description=Neural Sentry IPS
After=network.target $TOR_SERVICE.service
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

if [ $ENABLE_PRIVACY -eq 1 ] && [ -f "$CORE_DIR/privacy_monitor.sh" ]; then
    cp "$CORE_DIR/privacy_monitor.sh" /usr/local/bin/privacy_monitor.sh
    chmod +x /usr/local/bin/privacy_monitor.sh
    cat > /etc/systemd/system/privacy-monitor.service <<EOF
[Unit]
Description=OnionSite-Aegis Privacy Monitor
After=network.target $TOR_SERVICE.service nginx.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/privacy_monitor.sh
User=root
EOF
    cat > /etc/systemd/system/privacy-monitor.timer <<EOF
[Unit]
Description=Run OnionSite-Aegis Privacy Monitor every 10 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Unit=privacy-monitor.service
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now privacy-monitor.timer
    systemctl start privacy-monitor.service || true
    success "Privacy Monitor deployed and scheduled."
else
    systemctl disable --now privacy-monitor.timer 2>/dev/null || true
    rm -f /etc/systemd/system/privacy-monitor.service /etc/systemd/system/privacy-monitor.timer
    rm -f /usr/local/bin/privacy_monitor.sh
    systemctl daemon-reload
    log "Privacy Monitor disabled."
fi

if [ $ENABLE_TRAFFIC -eq 1 ] && [ -f "$CORE_DIR/traffic_analysis_protection.sh" ]; then
    cp "$CORE_DIR/traffic_analysis_protection.sh" /usr/local/bin/traffic_analysis_protection.sh
    chmod +x /usr/local/bin/traffic_analysis_protection.sh
    cat > /etc/systemd/system/traffic-protection.service <<EOF
[Unit]
Description=OnionSite-Aegis Traffic Analysis Protection
After=network.target nftables.service $TOR_SERVICE.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/traffic_analysis_protection.sh
RemainAfterExit=yes
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now traffic-protection.service
    success "Traffic Analysis Protection deployed."
else
    systemctl disable --now traffic-protection.service 2>/dev/null || true
    rm -f /etc/systemd/system/traffic-protection.service
    rm -f /usr/local/bin/traffic_analysis_protection.sh
    systemctl daemon-reload
    log "Traffic Analysis Protection disabled."
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
    chain output  { type filter hook output  priority 0; policy accept; }
}
EOF

if [ $ENABLE_SSH -eq 1 ]; then
    sed -i 's/# tcp dport 22/tcp dport 22/g' /etc/nftables.conf
    log "SSH Access Enabled in Firewall."
fi

if nft -c -f /etc/nftables.conf 2>/dev/null; then
    nft -f /etc/nftables.conf
    systemctl enable nftables 2>/dev/null || true
else
    critical "Generated /etc/nftables.conf failed syntax check."
fi

# ==============================================================================
# 10. BOOTSTRAP
# ==============================================================================
log "Bootstrapping Network..."
systemctl daemon-reload

# ── FIX: Verify Tor config with visible error output ──────────────────────────
TOR_VERIFY_ERR=$( tor --verify-config -f /etc/tor/torrc 2>&1 )
if echo "$TOR_VERIFY_ERR" | grep -qi "\[err\]\|\[warn\].*fatal\|Cannot\|failed"; then
    error "Tor configuration verification reported issues:"
    echo "$TOR_VERIFY_ERR" | tee -a "$LOG_FILE"
    critical "Tor config invalid. Fix /etc/tor/torrc and retry."
fi

# ── FIX: Final nginx -t with full stderr capture and logging ──────────────────
# (Config was pre-validated above; this catches any edge-case regression.)
NGINX_TEST_ERR=$( nginx -t 2>&1 )
if echo "$NGINX_TEST_ERR" | grep -q "test failed"; then
    error "Nginx configuration test failed:"
    echo "$NGINX_TEST_ERR" | tee -a "$LOG_FILE"
    critical "nginx -t failed. Check config above and fix before retrying."
fi

systemctl restart "$TOR_SERVICE"
systemctl restart nginx

# ── FIX: Guard optional service restarts — only restart if unit was deployed ──
if [ $ENABLE_SENTRY -eq 1 ] && [ -f /etc/systemd/system/neural-sentry.service ]; then
    systemctl restart neural-sentry
fi
# FIX: privacy-monitor runs as a timer — restart the timer unit, not the service
if [ $ENABLE_PRIVACY -eq 1 ] && [ -f /etc/systemd/system/privacy-monitor.timer ]; then
    systemctl restart privacy-monitor.timer
fi
if [ $ENABLE_TRAFFIC -eq 1 ] && [ -f /etc/systemd/system/traffic-protection.service ]; then
    systemctl restart traffic-protection.service
fi

trap - ERR
echo -n "Waiting for Onion Address generation"
COUNT=0
while [ ! -f "$TOR_HS/hostname" ] && [ $COUNT -lt 60 ]; do
    sleep 1; echo -n "."; COUNT=$((COUNT+1))
done
echo ""

if [ ! -f "$TOR_HS/hostname" ]; then
    error "Hidden service hostname was not generated within 60 seconds."
    error "Check: systemctl status $TOR_SERVICE nginx"
    critical "Installation incomplete: onion site was not created."
fi

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
