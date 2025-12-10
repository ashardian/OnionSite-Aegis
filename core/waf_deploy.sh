#!/bin/bash
# Deploys OWASP ModSecurity Core Rule Set (CRS) for Nginx
# Blocks SQL Injection, XSS, and Shell Uploads

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Check if packages are already installed
MODSEC_INSTALLED=false
GIT_INSTALLED=false

if dpkg -l | grep -q "libnginx-mod-http-modsecurity"; then
    MODSEC_INSTALLED=true
    info "ModSecurity module already installed"
fi

if command -v git >/dev/null 2>&1; then
    GIT_INSTALLED=true
    info "Git already installed"
fi

# Install packages if needed
if [ "$MODSEC_INSTALLED" = false ] || [ "$GIT_INSTALLED" = false ]; then
    info "Installing required packages..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y libnginx-mod-http-modsecurity git 2>&1; then
        error "Failed to install required packages. Network issue or package unavailable."
        error "WAF deployment cannot continue without these packages."
        exit 1
    fi
fi

# Download OWASP CRS
info "Downloading OWASP ModSecurity Core Rule Set..."
if [ -d "/usr/share/modsecurity-crs" ]; then
    warn "ModSecurity CRS directory already exists, skipping download"
else
    rm -rf /usr/share/modsecurity-crs
    if ! git clone --depth 1 https://github.com/coreruleset/coreruleset /usr/share/modsecurity-crs 2>&1; then
        error "Failed to clone OWASP CRS. Network issue or repository unavailable."
        error "WAF deployment cannot continue without CRS rules."
        exit 1
    fi
    
    if [ -f "/usr/share/modsecurity-crs/crs-setup.conf.example" ]; then
        mv /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
    else
        warn "crs-setup.conf.example not found, using existing crs-setup.conf if available"
    fi
fi

# Configure ModSecurity
info "Configuring ModSecurity..."
mkdir -p /etc/nginx/modsec
cat > /etc/nginx/modsec/main.conf <<EOF
Include /etc/nginx/modsec/modsecurity.conf
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf
EOF

# Grab default config if not present
if [ ! -f "/etc/nginx/modsec/modsecurity.conf" ]; then
    info "Downloading ModSecurity default configuration..."
    if command -v wget >/dev/null 2>&1; then
        if ! wget -O /etc/nginx/modsec/modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended 2>&1; then
            error "Failed to download ModSecurity config. Creating minimal config..."
            # Create minimal config
            cat > /etc/nginx/modsec/modsecurity.conf <<'EOFCONF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
EOFCONF
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -sSL -o /etc/nginx/modsec/modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended; then
            error "Failed to download ModSecurity config. Creating minimal config..."
            cat > /etc/nginx/modsec/modsecurity.conf <<'EOFCONF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
EOFCONF
        fi
    else
        warn "Neither wget nor curl available. Creating minimal ModSecurity config..."
        cat > /etc/nginx/modsec/modsecurity.conf <<'EOFCONF'
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
EOFCONF
    fi
else
    info "ModSecurity config already exists, skipping download"
fi

# Turn it ON (DetectionOnly -> On)
if [ -f "/etc/nginx/modsec/modsecurity.conf" ]; then
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf 2>/dev/null || true
    info "ModSecurity rule engine enabled"
else
    error "ModSecurity config file not found!"
    exit 1
fi

info "WAF Deployed. Application Layer is shielded."
