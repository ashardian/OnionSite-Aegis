#!/bin/bash
# OnionSite-Aegis Installer
# Target: Debian/Parrot
#
# Copyright (c) 2026 OnionSite-Aegis
# See LICENSE file for terms and conditions.
# Note: Author is not responsible for illegal use of this software.
#
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as root.${NC}"; exit 1; fi

# Privacy Check: Verify we're on a dedicated system
echo -e "${CYAN}[+] Privacy & Security Pre-Flight Checks...${NC}"
if [ -f /etc/passwd ] && [ "$(wc -l < /etc/passwd)" -gt 10 ]; then
    echo -e "${RED}[!] WARNING: Multiple user accounts detected. This tool is designed for dedicated servers.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for existing Tor services
if systemctl is-active --quiet tor 2>/dev/null; then
    echo -e "${RED}[!] WARNING: Tor service is already running.${NC}"
    read -p "Stop and reconfigure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl stop tor
    else
        echo -e "${RED}Aborting installation.${NC}"
        exit 1
    fi
fi

echo -e "${CYAN}[+] Starting AEGIS Deployment (Privacy-Focused Mode)...${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print progress
print_progress() {
    echo -e "${GREEN}[*]${NC} $1"
}

# Function to print error and exit
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Check for required commands
print_progress "Checking system requirements..."
if ! command_exists apt-get; then
    print_error "apt-get not found. This installer is for Debian/Ubuntu systems."
fi

# Check disk space (at least 500MB free)
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt 524288 ]; then  # 500MB in KB
    print_error "Insufficient disk space. At least 500MB free space required."
fi

# 1. Install Dependencies
print_progress "Installing dependencies..."
if ! apt-get update -qq; then
    print_error "Failed to update package lists."
fi

if ! DEBIAN_FRONTEND=noninteractive apt-get install -y \
    tor nginx nftables python3-pip python3-stem tor-geoipdb \
    nginx-extras libnginx-mod-http-headers-more-filter unzip python3-inotify; then
    print_error "Failed to install required packages."
fi

print_progress "Installing Python dependencies..."
if ! pip3 install stem inotify --break-system-packages 2>/dev/null; then
    if ! pip3 install stem inotify; then
        print_error "Failed to install Python dependencies."
    fi
fi

# 2. Setup RAM Disk (Amnesic Logs)
print_progress "Configuring Amnesic RAM Logging..."
mkdir -p /mnt/ram_logs
if ! grep -q "ram_logs" /etc/fstab; then
    echo "tmpfs /mnt/ram_logs tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=256M 0 0" >> /etc/fstab
fi
mount -a

# Install RAM Init Script (Ensures log dirs exist on boot)
cp core/init_ram_logs.sh /usr/local/bin/
chmod +x /usr/local/bin/init_ram_logs.sh

cat > /etc/systemd/system/aegis-ram-init.service <<EOF
[Unit]
Description=Initialize RAM Log Directories
After=local-fs.target
Before=nginx.service tor.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/init_ram_logs.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aegis-ram-init.service
systemctl start aegis-ram-init.service

# Link Logs
rm -rf /var/log/nginx /var/log/tor
ln -sf /mnt/ram_logs/nginx /var/log/nginx
ln -sf /mnt/ram_logs/tor /var/log/tor

# 3. Kernel Hardening
print_progress "Applying Kernel Hardening..."
cp conf/sysctl_hardened.conf /etc/sysctl.d/99-aegis.conf
sysctl -p /etc/sysctl.d/99-aegis.conf > /dev/null

# 4. Firewall (NFTables)
print_progress "Locking Firewall (NFTables)..."
if [ ! -f conf/nftables.conf ]; then
    print_error "nftables.conf not found in conf/ directory."
fi
cp conf/nftables.conf /etc/nftables.conf

# Validate nftables configuration before applying
if ! nft -c -f /etc/nftables.conf 2>/dev/null; then
    echo -e "${RED}[WARNING]${NC} NFTables configuration validation failed, but continuing..."
fi

systemctl enable nftables
if ! systemctl restart nftables; then
    echo -e "${RED}[WARNING]${NC} Failed to restart nftables. Check configuration manually."
fi

# 5. Tor Configuration
print_progress "Configuring Tor (Sandbox + V3 + Privacy)..."

# Ensure hidden service directory exists BEFORE configuring Tor
print_progress "Creating hidden service directory..."
mkdir -p /var/lib/tor/hidden_service
chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
chmod 700 /var/lib/tor/hidden_service

# Remove duplicate HiddenServiceDir lines from existing torrc (if any)
if [ -f /etc/tor/torrc ]; then
    print_progress "Removing duplicate HiddenServiceDir entries..."
    # Create a temporary file without duplicate HiddenServiceDir lines
    grep -v "^HiddenServiceDir" /etc/tor/torrc > /tmp/torrc.clean 2>/dev/null || true
    # Also remove lines that might have HiddenServiceDir with spaces/tabs
    sed -i '/^[[:space:]]*HiddenServiceDir/d' /tmp/torrc.clean 2>/dev/null || true
fi

# Determine CPU cores for threading
CORES=$(nproc)
cat > /etc/tor/torrc <<EOF
DataDirectory /var/lib/tor
PidFile /run/tor/tor.pid
RunAsDaemon 1
User debian-tor

# Control Port for Neural Sentry
ControlPort 9051
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

# Exit Node Restrictions (if relaying)
ExitNodes {}
ExcludeNodes {}
StrictNodes 0

# Additional Privacy Settings
# Don't publish server descriptor (if not relaying)
PublishServerDescriptor 0

# Reduce directory information
DirPort auto
ORPort auto

# Prevent fingerprinting
ClientOnly 1  # Only act as client, not relay

# Prevent correlation through directory requests
FetchDirInfoEarly 0
FetchUselessDescriptors 0

# Connection timing randomization
LearnCircuitBuildTimeout 0  # Don't learn optimal timeouts (prevents fingerprinting)

# Logging Privacy (minimal - no identifying info)
Log notice file /mnt/ram_logs/tor/tor.log
SafeLogging 1
AvoidDiskWrites 1
EOF

# 6. Nginx Configuration
print_progress "Configuring Nginx..."
mkdir -p /var/www/onion_site
if [ ! -f conf/nginx_hardened.conf ]; then
    print_error "nginx_hardened.conf not found in conf/ directory."
fi
cp conf/nginx_hardened.conf /etc/nginx/sites-available/onion_site
ln -sf /etc/nginx/sites-available/onion_site /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create minimal error pages (privacy-focused)
cat > /var/www/onion_site/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Secure System</title>
</head>
<body>
<h1>Secure System</h1>
</body>
</html>
EOF

cat > /var/www/onion_site/404.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Not Found</title>
</head>
<body>
<h1>Not Found</h1>
</body>
</html>
EOF

cat > /var/www/onion_site/50x.html <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Error</title>
</head>
<body>
<h1>Service Temporarily Unavailable</h1>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/onion_site
chmod 755 /var/www/onion_site
find /var/www/onion_site -type f -exec chmod 644 {} \;

# 7. Install Neural Sentry
print_progress "Installing Neural Sentry (Active Defense)..."
if [ ! -f core/neural_sentry.py ]; then
    print_error "neural_sentry.py not found in core/ directory."
fi
cp core/neural_sentry.py /usr/local/bin/
chmod +x /usr/local/bin/neural_sentry.py

# Install Privacy Log Sanitizer
cp core/privacy_log_sanitizer.py /usr/local/bin/
chmod +x /usr/local/bin/privacy_log_sanitizer.py

# Install Privacy Monitor
cp core/privacy_monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/privacy_monitor.sh

# Install Traffic Analysis Protection
print_progress "Installing Traffic Analysis Protection..."
if [ ! -f core/traffic_analysis_protection.sh ]; then
    print_error "traffic_analysis_protection.sh not found in core/ directory."
fi
cp core/traffic_analysis_protection.sh /usr/local/bin/
chmod +x /usr/local/bin/traffic_analysis_protection.sh
/usr/local/bin/traffic_analysis_protection.sh || echo -e "${RED}[WARNING]${NC} Traffic analysis protection setup had issues, continuing..."

# Setup Privacy Monitor Timer (runs every 6 hours)
cat > /etc/systemd/system/privacy-monitor.timer <<EOF
[Unit]
Description=Privacy Monitor Timer
Requires=privacy-monitor.service

[Timer]
OnBootSec=1h
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/privacy-monitor.service <<EOF
[Unit]
Description=Privacy Monitor Check
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/privacy_monitor.sh
User=root
EOF

systemctl daemon-reload
systemctl enable privacy-monitor.timer
systemctl start privacy-monitor.timer

cat > /etc/systemd/system/neural-sentry.service <<EOF
[Unit]
Description=OnionSite Neural Sentry (Active Defense)
After=tor.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/neural_sentry.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable neural-sentry

# ... (Previous steps 1-7) ...

# 7.5 Install WAF (The missing layer)
print_progress "Deploying Web Application Firewall (ModSecurity)..."
if [ ! -f core/waf_deploy.sh ]; then
    echo -e "${RED}[WARNING]${NC} waf_deploy.sh not found. Skipping WAF deployment."
else
    bash core/waf_deploy.sh || echo -e "${RED}[WARNING]${NC} WAF deployment had issues, continuing..."
fi

# 7.6 Apply AppArmor Profile
print_progress "Locking Nginx with AppArmor..."
if command_exists aa-enforce; then
    if [ -f conf/usr.sbin.nginx ]; then
        cp conf/usr.sbin.nginx /etc/apparmor.d/usr.sbin.nginx
        aa-enforce /etc/apparmor.d/usr.sbin.nginx || echo -e "${RED}[WARNING]${NC} Failed to enforce AppArmor profile."
        systemctl reload apparmor || true
    else
        echo -e "${RED}[WARNING]${NC} AppArmor profile not found. Skipping."
    fi
else
    echo -e "${RED}[WARNING]${NC} AppArmor not available. Skipping."
fi

# ... (Proceed to Step 8: Start Services) ...

# 8. Start Services
print_progress "Starting all services..."

# Reload systemd and restart Tor
print_progress "Reloading systemd and starting Tor..."
systemctl daemon-reload
if ! systemctl restart tor; then
    print_error "Failed to restart Tor service."
fi

# Wait for Tor to initialize the hidden service (with retries)
print_progress "Waiting for Tor to create hidden service..."
MAX_ATTEMPTS=30
ATTEMPT=0
HOSTNAME=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if [ -f /var/lib/tor/hidden_service/hostname ]; then
        HOSTNAME=$(cat /var/lib/tor/hidden_service/hostname)
        break
    fi
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
done

# Verify that Tor created the hostname file
if [ -z "$HOSTNAME" ] || [ ! -f /var/lib/tor/hidden_service/hostname ]; then
    echo -e "${RED}[ERROR] Tor did not create the hidden service hostname after $MAX_ATTEMPTS attempts.${NC}"
    echo -e "${RED}[ERROR] Checking Tor service status...${NC}"
    systemctl status tor --no-pager || true
    echo -e "${RED}[ERROR] Checking Tor logs...${NC}"
    journalctl -xeu tor --no-pager | tail -n 50
    print_error "Hidden service creation failed. Please check Tor configuration and logs."
fi

# Output the onion address
print_progress "Hidden service hostname created successfully!"
echo -e "${GREEN}[*] Onion address: ${CYAN}$HOSTNAME${NC}"

# Ensure the hidden service directory is never deleted (add protection comment)
# This directory contains the private key - DO NOT DELETE
if [ -d /var/lib/tor/hidden_service ]; then
    # Set immutable flag if supported (extra protection)
    chattr +i /var/lib/tor/hidden_service/hostname 2>/dev/null || true
fi

systemctl restart nginx
systemctl restart neural-sentry

# Final Output
echo -e "\n${CYAN}=============================================${NC}"
echo -e "${CYAN}   AEGIS DEPLOYMENT COMPLETE (INSANE MODE) ${NC}"
echo -e "${CYAN}=============================================${NC}"
echo -e "YOUR ONION URL: ${GREEN}$HOSTNAME${NC}"
echo -e "LOGS LOCATION:  ${RED}/mnt/ram_logs (RAM - Volatile)${NC}"
echo -e "SENTRY STATUS:  ${GREEN}Active${NC}"
echo -e "${CYAN}=============================================${NC}"
