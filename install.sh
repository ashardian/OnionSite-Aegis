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

# 1. Install Dependencies
echo -e "${GREEN}[*] Installing dependencies...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y tor nginx nftables python3-pip python3-stem tor-geoipdb nginx-extras libnginx-mod-http-headers-more-filter unzip python3-inotify
pip3 install stem inotify --break-system-packages 2>/dev/null || pip3 install stem inotify

# 2. Setup RAM Disk (Amnesic Logs)
echo -e "${GREEN}[*] Configuring Amnesic RAM Logging...${NC}"
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
echo -e "${GREEN}[*] Applying Kernel Hardening...${NC}"
cp conf/sysctl_hardened.conf /etc/sysctl.d/99-aegis.conf
sysctl -p /etc/sysctl.d/99-aegis.conf > /dev/null

# 4. Firewall (NFTables)
echo -e "${GREEN}[*] Locking Firewall (NFTables)...${NC}"
cp conf/nftables.conf /etc/nftables.conf
systemctl enable nftables
systemctl restart nftables

# 5. Tor Configuration
echo -e "${GREEN}[*] Configuring Tor (Sandbox + V3 + Privacy)...${NC}"
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

# Hidden Service
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

mkdir -p /var/lib/tor/hidden_service
chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
chmod 700 /var/lib/tor/hidden_service

# 6. Nginx Configuration
echo -e "${GREEN}[*] Configuring Nginx...${NC}"
mkdir -p /var/www/onion_site
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
echo -e "${GREEN}[*] Installing Neural Sentry (Active Defense)...${NC}"
cp core/neural_sentry.py /usr/local/bin/
chmod +x /usr/local/bin/neural_sentry.py

# Install Privacy Log Sanitizer
cp core/privacy_log_sanitizer.py /usr/local/bin/
chmod +x /usr/local/bin/privacy_log_sanitizer.py

# Install Privacy Monitor
cp core/privacy_monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/privacy_monitor.sh

# Install Traffic Analysis Protection
echo -e "${GREEN}[*] Installing Traffic Analysis Protection...${NC}"
cp core/traffic_analysis_protection.sh /usr/local/bin/
chmod +x /usr/local/bin/traffic_analysis_protection.sh
/usr/local/bin/traffic_analysis_protection.sh

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
echo -e "${GREEN}[*] Deploying Web Application Firewall (ModSecurity)...${NC}"
bash core/waf_deploy.sh

# 7.6 Apply AppArmor Profile
echo -e "${GREEN}[*] Locking Nginx with AppArmor...${NC}"
apt-get install -y apparmor-utils apparmor-profiles
cp conf/usr.sbin.nginx /etc/apparmor.d/usr.sbin.nginx
aa-enforce /etc/apparmor.d/usr.sbin.nginx
systemctl reload apparmor

# ... (Proceed to Step 8: Start Services) ...

# 8. Start Services
echo -e "${GREEN}[*] Starting all services...${NC}"
systemctl restart tor
systemctl restart nginx
systemctl restart neural-sentry

# Final Output
HOSTNAME=$(cat /var/lib/tor/hidden_service/hostname 2>/dev/null || echo "Pending...")
echo -e "\n${CYAN}=============================================${NC}"
echo -e "${CYAN}   AEGIS DEPLOYMENT COMPLETE (INSANE MODE) ${NC}"
echo -e "${CYAN}=============================================${NC}"
echo -e "YOUR ONION URL: ${GREEN}$HOSTNAME${NC}"
echo -e "LOGS LOCATION:  ${RED}/mnt/ram_logs (RAM - Volatile)${NC}"
echo -e "SENTRY STATUS:  ${GREEN}Active${NC}"
echo -e "${CYAN}=============================================${NC}"
