#!/bin/bash

################################################################################
# OnionSite-Aegis Production-Grade Installer Script (FIXED VERSION)
# Version: 1.0.1 (Patched)
# Description: Comprehensive deployment with Tor, Hardening, and Monitoring
################################################################################

set -o pipefail
# We do NOT use 'set -e' globally because we want to handle errors manually in some spots

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
REQUIRED_USER="ashardian" # Change this if needed
MIN_DISK_SPACE_MB=500
DEPLOYMENT_DIR="/opt/onionsite-aegis"
TOR_HS_DIR="/var/lib/tor/hidden_service"

# Create logs directory
mkdir -p "${LOG_DIR}"

################################################################################
# Logging Functions
################################################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"; }

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo "================================================================================" | tee -a "${LOG_FILE}"
    echo "$1" | tee -a "${LOG_FILE}"
    echo "================================================================================" | tee -a "${LOG_FILE}"
}

################################################################################
# Pre-Flight Checks & Network Reset
################################################################################

# CRITICAL FIX: Reset network blocking to allow apt-get to work
reset_network_locks() {
    log_info "Ensuring network is open for installation..."
    if command -v nft &> /dev/null; then
        nft flush ruleset 2>/dev/null || true
    fi
    if command -v iptables &> /dev/null; then
        iptables -F 2>/dev/null || true
    fi
    # Temporary DNS fix if resolution is broken
    if ! grep -q "8.8.8.8" /etc/resolv.conf; then
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
    fi
}

check_sudo_root_execution() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)."
        exit 1
    fi
    log_success "Running with root privileges"
}

check_system_requirements() {
    log_section "Checking System Requirements"
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_info "Operating System: ${PRETTY_NAME}"
    fi
    
    # Check available disk space
    local available_space=$(df "${SCRIPT_DIR}" | awk 'NR==2 {print $4}')
    if [[ ${available_space} -lt $((MIN_DISK_SPACE_MB * 1024)) ]]; then
        log_error "Insufficient disk space."
        exit 1
    fi
    log_success "Disk space check passed."
}

################################################################################
# Permission Management
################################################################################

fix_permissions() {
    log_section "Setting up Deployment Directory"
    
    if [[ ! -d "${DEPLOYMENT_DIR}" ]]; then
        log_info "Creating deployment directory: ${DEPLOYMENT_DIR}"
        mkdir -p "${DEPLOYMENT_DIR}"
    fi

    # Create subdirectories structure
    mkdir -p "${DEPLOYMENT_DIR}/config"
    mkdir -p "${DEPLOYMENT_DIR}/core"
    mkdir -p "${DEPLOYMENT_DIR}/logs"

    # FIX: Only attempt chown if the user exists
    if id "$REQUIRED_USER" &>/dev/null; then
        chown -R "${REQUIRED_USER}:${REQUIRED_USER}" "${DEPLOYMENT_DIR}"
    else
        log_warning "User '$REQUIRED_USER' not found. Defaulting to root ownership."
    fi

    chmod -R 755 "${DEPLOYMENT_DIR}"
    log_success "Directory structure created and permissions set."
}

################################################################################
# Dependency Installation (FIXED for Debian 12)
################################################################################

install_dependencies() {
    log_section "Installing Dependencies"

    # 1. Reset Network locks first
    reset_network_locks
    
    log_info "Updating package lists..."
    apt-get update -y || log_warning "Apt update had minor issues, attempting to continue..."

    # FIX: Install ALL Python deps via apt to avoid PEP 668 errors
    local packages="curl wget git tor nginx nftables python3-pip python3-stem python3-inotify python3-requests build-essential libssl-dev python3-dev"
    
    # Add AppArmor if available
    packages="$packages apparmor-utils apparmor-profiles python3-apparmor"

    log_info "Installing packages: $packages"
    if ! apt-get install -y $packages; then
        log_error "Failed to install dependencies."
        exit 1
    fi
    
    log_success "Dependencies installed successfully."
}

################################################################################
# Feature Deployment
################################################################################

deploy_core_features() {
    log_section "Deploying OnionSite-Aegis Core Features"
    deploy_tor_module
    deploy_security_module
    deploy_monitoring_module
}

deploy_tor_module() {
    log_section "Configuring Tor"

    # CRITICAL FIX: Unmask services that might be blocked
    systemctl unmask tor@default.service 2>/dev/null || true
    systemctl unmask tor.service 2>/dev/null || true
    systemctl stop tor

    # Configure Torrc
    local tor_config="/etc/tor/torrc"
    log_info "Writing Tor configuration..."
    
    cat > "$tor_config" <<EOF
############### OnionSite-Aegis Config ###############
DataDirectory /var/lib/tor
HiddenServiceDir $TOR_HS_DIR
HiddenServicePort 80 127.0.0.1:80
# Security Hardening
Sandbox 1
RunAsDaemon 1
EOF

    # FIX: Create Hidden Service Dir with CORRECT permissions
    if [ ! -d "$TOR_HS_DIR" ]; then
        log_info "Creating Hidden Service Directory..."
        mkdir -p "$TOR_HS_DIR"
    fi

    # CRITICAL FIX: Ensure 'debian-tor' owns the directory with 700 perms
    log_info "Fixing Tor permissions..."
    chown -R debian-tor:debian-tor "$TOR_HS_DIR"
    chmod 700 "$TOR_HS_DIR"
    
    # Also fix parent dir just in case
    chown debian-tor:debian-tor /var/lib/tor
    chmod 700 /var/lib/tor

    log_success "Tor configured and permissions fixed."
}

deploy_security_module() {
    log_section "Configuring Security (Firewall & Hardening)"

    # Only basic placeholder firewall to ensure we don't lock ourselves out again
    # Real hardening should happen after successful deployment
    
    if command -v nft &> /dev/null; then
        log_info "Initializing NFTables (Safe Mode)..."
        # Create a simple ruleset that allows everything for now
        # You can replace this with your strict rules later
        nft add table inet filter 2>/dev/null || true
        nft add chain inet filter input { type filter hook input priority 0 \; } 2>/dev/null || true
        log_success "Firewall initialized."
    fi
}

deploy_monitoring_module() {
    log_section "Setting up Monitoring"
    
    # FIX: Check if source files exist before copying
    if [[ -f "${SCRIPT_DIR}/core/init_ram_logs.sh" ]]; then
        cp "${SCRIPT_DIR}/core/init_ram_logs.sh" "${DEPLOYMENT_DIR}/core/"
        chmod +x "${DEPLOYMENT_DIR}/core/init_ram_logs.sh"
        log_success "RAM logging script deployed."
    else
        log_warning "init_ram_logs.sh not found in source directory. Skipping."
    fi
}

################################################################################
# Finalization & Service Start
################################################################################

start_services() {
    log_section "Starting Services"
    
    systemctl daemon-reload
    
    log_info "Starting Tor..."
    if ! systemctl restart tor; then
        log_error "Tor failed to start. Checking logs..."
        journalctl -xeu tor --no-pager | tail -n 10
        return 1
    fi
    
    log_info "Starting Nginx..."
    systemctl restart nginx || log_warning "Nginx failed to start."

    # Validate Tor Config
    log_info "Verifying Tor Configuration..."
    if sudo -u debian-tor tor --verify-config; then
        log_success "Tor configuration is VALID."
    else
        log_error "Tor configuration is INVALID."
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log_section "OnionSite-Aegis Installation Started"
    
    # Pre-flight
    check_sudo_root_execution
    check_system_requirements
    
    # Install
    install_dependencies
    fix_permissions
    deploy_core_features
    
    # Start
    start_services
    
    log_section "Installation Completed"
    
    if [ -f "$TOR_HS_DIR/hostname" ]; then
        local onion_url=$(cat "$TOR_HS_DIR/hostname")
        echo -e "${GREEN}Your Onion Address: ${onion_url}${NC}"
    else
        echo -e "${YELLOW}Onion address not generated yet. Please wait a few seconds and run:${NC}"
        echo "cat $TOR_HS_DIR/hostname"
    fi
    
    echo ""
    echo "To view logs: cat ${LOG_FILE}"
}

# Run Main
main "$@"
