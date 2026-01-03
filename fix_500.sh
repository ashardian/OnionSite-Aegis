#!/bin/bash
# AEGIS FINAL PURGE
# Purpose: Deletes all conflicting config files (including 'aegis_onion')
# and forces a clean start.

echo "=== EXECUTING FINAL PURGE ==="

# 1. STOP NGINX
systemctl stop nginx

# 2. DELETE ALL SITE CONFIGS (The Fix)
# This deletes 'aegis_onion', 'onion_site', 'default', and anything else.
echo "[1] Deleting all existing site configurations..."
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*

# 3. CREATE ONE CLEAN CONFIG
echo "[2] Creating single clean configuration..."
cat > /etc/nginx/sites-available/onion_site << 'EOF'
server {
    listen 127.0.0.1:80 default_server;
    server_name _;
    root /var/www/onion_site;
    index index.html;
    server_tokens off;

    # Basic headers only
    add_header X-Frame-Options DENY;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# 4. ENABLE THE NEW CONFIG
ln -s /etc/nginx/sites-available/onion_site /etc/nginx/sites-enabled/

# 5. START NGINX
echo "[3] Starting Nginx..."
systemctl start nginx

# 6. VERIFY
echo "--------------------------------"
if systemctl is-active --quiet nginx; then
    echo -e "\033[0;32m[SUCCESS] Nginx is RUNNING.\033[0m"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" 127.0.0.1)
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "\033[0;32m[SUCCESS] SITE IS LIVE (HTTP 200 OK)\033[0m"
        echo "The ghost file 'aegis_onion' has been removed."
        echo "Your site is accessible at: http://$(cat /var/lib/tor/hidden_service/hostname)"
    else
        echo -e "\033[0;31m[WARN] Nginx is running, but returned Code: $HTTP_CODE\033[0m"
    fi
else
    echo -e "\033[0;31m[FAIL] Nginx failed to start.\033[0m"
    echo "Error Logs:"
    journalctl -n 10 -u nginx --no-pager
fi
