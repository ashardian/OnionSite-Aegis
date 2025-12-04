#!/bin/bash
# OnionSite-Aegis Installer
# Target: Debian/Parrot
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as root.${NC}"; exit 1; fi

echo -e "${CYAN}[+] Starting AEGIS Deployment (Insane Mode)...${NC}"

# 1. Install Dependencies
echo -e "${GREEN}[*] Installing dependencies...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y tor nginx nftables python3-pip python3-stem tor-geoipdb nginx-extras unzip
pip3 install stem --break-system-packages 2>/dev/null || pip3 install stem

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
echo -e "${GREEN}[*] Configuring Tor (Sandbox + V3)...${NC}"
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

# Hardening
Sandbox 1
NoExec 1
HardwareAccel 1
SafeLogging 1
AvoidDiskWrites 1
NumCPUs $CORES
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
echo "<h1>AEGIS SECURE SYSTEM</h1>" > /var/www/onion_site/index.html
chown -R www-data:www-data /var/www/onion_site

# 7. Install Neural Sentry
echo -e "${GREEN}[*] Installing Neural Sentry (Active Defense)...${NC}"
cp core/neural_sentry.py /usr/local/bin/
chmod +x /usr/local/bin/neural_sentry.py

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
