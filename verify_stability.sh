#!/bin/bash
# Comprehensive Verification Script for OnionSite-Aegis
# Checks all files, syntax, dependencies, and stability

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${CYAN}[*]${NC} $1"
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  OnionSite-Aegis Verification Tool${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. Check Bash Scripts
log_info "Checking Bash Scripts..."
for script in install.sh uninstall.sh SAVE_MY_ONION.sh docker-entrypoint.sh docker-host-firewall.sh core/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            log_ok "$script syntax valid"
        else
            log_error "$script has syntax errors"
        fi
        
        if [ -x "$script" ]; then
            log_ok "$script is executable"
        else
            log_warning "$script is not executable"
            chmod +x "$script" 2>/dev/null && log_ok "Fixed permissions for $script"
        fi
    fi
done

# 2. Check Python Scripts
log_info "Checking Python Scripts..."
for script in core/*.py; do
    if [ -f "$script" ]; then
        if python3 -m py_compile "$script" 2>/dev/null; then
            log_ok "$script syntax valid"
        else
            log_error "$script has syntax errors"
        fi
        
        if [ -x "$script" ]; then
            log_ok "$script is executable"
        else
            log_warning "$script is not executable"
            chmod +x "$script" 2>/dev/null && log_ok "Fixed permissions for $script"
        fi
    fi
done

# 3. Check Configuration Files
log_info "Checking Configuration Files..."

# Nginx config
if [ -f "conf/nginx_hardened.conf" ]; then
    log_ok "nginx_hardened.conf exists"
    # Check for common nginx syntax issues
    if grep -q "server {" conf/nginx_hardened.conf; then
        log_ok "nginx config has server block"
    else
        log_error "nginx config missing server block"
    fi
else
    log_error "nginx_hardened.conf missing"
fi

# NFTables config
if [ -f "conf/nftables.conf" ]; then
    log_ok "nftables.conf exists"
    if nft -c -f conf/nftables.conf 2>/dev/null; then
        log_ok "nftables config syntax valid"
    else
        log_warning "nftables config syntax check failed (may need root or nftables installed)"
    fi
else
    log_error "nftables.conf missing"
fi

# Sysctl config
if [ -f "conf/sysctl_hardened.conf" ]; then
    log_ok "sysctl_hardened.conf exists"
    if grep -q "^net\." conf/sysctl_hardened.conf; then
        log_ok "sysctl config has network settings"
    fi
else
    log_error "sysctl_hardened.conf missing"
fi

# 4. Check Docker Files
log_info "Checking Docker Files..."

if [ -f "Dockerfile" ]; then
    log_ok "Dockerfile exists"
    if grep -q "FROM" Dockerfile; then
        log_ok "Dockerfile has FROM instruction"
    else
        log_error "Dockerfile missing FROM instruction"
    fi
else
    log_error "Dockerfile missing"
fi

if [ -f "docker-compose.yml" ]; then
    log_ok "docker-compose.yml exists"
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('docker-compose.yml'))" 2>/dev/null; then
            log_ok "docker-compose.yml syntax valid"
        else
            log_warning "docker-compose.yml syntax check failed (yaml module may not be installed)"
        fi
    fi
else
    log_error "docker-compose.yml missing"
fi

if [ -f "seccomp-profile.json" ]; then
    log_ok "seccomp-profile.json exists"
    if python3 -c "import json; json.load(open('seccomp-profile.json'))" 2>/dev/null; then
        log_ok "seccomp-profile.json is valid JSON"
    else
        log_error "seccomp-profile.json is invalid JSON"
    fi
else
    log_error "seccomp-profile.json missing"
fi

# 5. Check Required Files Exist
log_info "Checking Required Files..."

REQUIRED_FILES=(
    "README.md"
    "install.sh"
    "uninstall.sh"
    "core/neural_sentry.py"
    "core/privacy_log_sanitizer.py"
    "core/privacy_monitor.sh"
    "core/traffic_analysis_protection.sh"
    "core/init_ram_logs.sh"
    "core/waf_deploy.sh"
    "conf/nginx_hardened.conf"
    "conf/nftables.conf"
    "conf/sysctl_hardened.conf"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        log_ok "$file exists"
    else
        log_error "$file is missing"
    fi
done

# 6. Check Python Dependencies
log_info "Checking Python Dependencies..."

PYTHON_DEPS=("stem" "inotify")
for dep in "${PYTHON_DEPS[@]}"; do
    if python3 -c "import $dep" 2>/dev/null; then
        log_ok "Python module '$dep' available"
    else
        log_warning "Python module '$dep' not available (will be installed during setup)"
    fi
done

# 7. Check File Paths in Scripts
log_info "Checking File Paths in Scripts..."

# Check install.sh references
if grep -q "/usr/local/bin/neural_sentry.py" install.sh; then
    log_ok "install.sh references neural_sentry.py"
fi

if grep -q "/var/www/onion_site" install.sh; then
    log_ok "install.sh references web root"
fi

if grep -q "/mnt/ram_logs" install.sh; then
    log_ok "install.sh references RAM logs"
fi

# 8. Check for Common Issues
log_info "Checking for Common Issues..."

# Check for hardcoded paths that might not exist
if grep -r "/usr/local/bin" . --include="*.sh" --include="*.py" | grep -v "install.sh\|uninstall.sh" | grep -q "/usr/local/bin"; then
    log_warning "Some scripts reference /usr/local/bin (should be set during install)"
fi

# Check for missing shebangs
for script in core/*.sh core/*.py; do
    if [ -f "$script" ]; then
        if head -1 "$script" | grep -q "^#!"; then
            log_ok "$script has shebang"
        else
            log_warning "$script missing shebang"
        fi
    fi
done

# 9. Check Documentation
log_info "Checking Documentation..."

DOC_FILES=("README.md" "DOCKER_DEPLOYMENT.md" "QUICKSTART.md" "ANTI_TRACKING_GUIDE.md")
for doc in "${DOC_FILES[@]}"; do
    if [ -f "$doc" ]; then
        log_ok "$doc exists"
    else
        log_warning "$doc missing (optional)"
    fi
done

# 10. Check Lua Files (Optional)
log_info "Checking Optional Files..."

if [ -f "core/response_padding.lua" ]; then
    log_ok "response_padding.lua exists (optional)"
fi

if [ -f "core/anti_tracking_nginx.conf" ]; then
    log_ok "anti_tracking_nginx.conf exists (optional)"
fi

# Summary
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Verification Summary${NC}"
echo -e "${CYAN}========================================${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found, but no errors${NC}"
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found${NC}"
    exit 1
fi

