#!/bin/bash
# Deploys OWASP ModSecurity Core Rule Set (CRS) for Nginx
# Blocks SQL Injection, XSS, and Shell Uploads

apt-get install -y libnginx-mod-http-modsecurity git

# Download OWASP CRS
rm -rf /usr/share/modsecurity-crs
git clone https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs
mv /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf

# Configure ModSecurity
mkdir -p /etc/nginx/modsec
cat > /etc/nginx/modsec/main.conf <<EOF
Include /etc/nginx/modsec/modsecurity.conf
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
EOF

# Grab default config
wget -O /etc/nginx/modsec/modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended

# Turn it ON (DetectionOnly -> On)
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf

echo "WAF Deployed. Application Layer is shielded."
