#!/bin/bash
# SAVE_MY_ONION.sh
# Enhanced Tor Hidden Service Key Migration Tool
# Migrates keys from various sources to Aegis structure
#
# Copyright (c) 2026 OnionSite-Aegis
# See LICENSE file for terms and conditions.
# Note: Author is not responsible for illegal use of this software.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AEGIS_DIR="/var/lib/tor/hidden_service"
BACKUP_DIR="/var/lib/tor/hidden_service_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/save_my_onion.log"

# Logging function
log() {
    echo -e "${CYAN}[SAVE_MY_ONION]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "This script must be run as root"
    exit 1
fi

log "Starting Onion Key Migration Tool..."

# Check if we're in Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -n "$DOCKER_CONTAINER" ]; then
    IN_DOCKER=true
    log "Detected Docker environment"
fi

# Function to check if Tor is running
check_tor_running() {
    if systemctl is-active --quiet tor 2>/dev/null || pgrep -x tor >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to stop Tor safely
stop_tor() {
    if check_tor_running; then
        log "Stopping Tor service to release file locks..."
        if systemctl stop tor 2>/dev/null; then
            log_success "Tor service stopped"
            sleep 2  # Wait for file locks to release
        else
            log_warning "Could not stop Tor via systemctl, trying pkill..."
            pkill -9 tor 2>/dev/null || true
            sleep 2
        fi
    else
        log "Tor is not running, proceeding..."
    fi
}

# Function to backup existing keys
backup_existing() {
    if [ -d "$AEGIS_DIR" ] && [ "$(ls -A $AEGIS_DIR 2>/dev/null)" ]; then
        log "Backing up existing keys to $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r "$AEGIS_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
        chown -R debian-tor:debian-tor "$BACKUP_DIR" 2>/dev/null || true
        chmod 700 "$BACKUP_DIR" 2>/dev/null || true
        log_success "Backup created at $BACKUP_DIR"
    fi
}

# Function to verify keys
verify_keys() {
    local key_dir="$1"
    local has_hostname=false
    local has_private_key=false
    
    if [ -f "$key_dir/hostname" ]; then
        has_hostname=true
        log_success "Found hostname file"
    fi
    
    if [ -f "$key_dir/hs_ed25519_secret_key" ] || [ -f "$key_dir/private_key" ]; then
        has_private_key=true
        log_success "Found private key file"
    fi
    
    if [ "$has_hostname" = true ] && [ "$has_private_key" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to migrate from source
migrate_from_source() {
    local source_dir="$1"
    local source_name="$2"
    
    if [ ! -d "$source_dir" ]; then
        return 1
    fi
    
    if [ -z "$(ls -A $source_dir 2>/dev/null)" ]; then
        log_warning "$source_name directory is empty"
        return 1
    fi
    
    log "Found $source_name keys at $source_dir"
    
    # Verify source keys
    if ! verify_keys "$source_dir"; then
        log_error "$source_name keys appear incomplete"
        return 1
    fi
    
    # Backup existing
    backup_existing
    
    # Prepare Aegis directory
    mkdir -p "$AEGIS_DIR"
    
    # Copy keys
    log "Copying keys from $source_name..."
    if cp -r "$source_dir"/* "$AEGIS_DIR/" 2>/dev/null; then
        log_success "Keys copied successfully"
    else
        log_error "Failed to copy keys"
        return 1
    fi
    
    # Fix permissions (Critical for Tor)
    log "Setting proper permissions..."
    chown -R debian-tor:debian-tor "$AEGIS_DIR" 2>/dev/null || true
    chmod 700 "$AEGIS_DIR" 2>/dev/null || true
    find "$AEGIS_DIR" -type f -exec chmod 600 {} \; 2>/dev/null || true
    find "$AEGIS_DIR" -type d -exec chmod 700 {} \; 2>/dev/null || true
    
    # Verify migrated keys
    if verify_keys "$AEGIS_DIR"; then
        log_success "Migration verified successfully"
        
        # Display Onion address
        if [ -f "$AEGIS_DIR/hostname" ]; then
            ONION_ADDR=$(cat "$AEGIS_DIR/hostname" 2>/dev/null)
            log_success "Your Onion address: $ONION_ADDR"
        fi
        
        return 0
    else
        log_error "Migration verification failed"
        return 1
    fi
}

# Main migration process
main() {
    log "=========================================="
    log "  Onion Key Migration Tool"
    log "=========================================="
    echo ""
    
    # Stop Tor if needed
    if [ "$IN_DOCKER" = false ]; then
        stop_tor
    else
        log "In Docker - skipping Tor stop (handled by container)"
    fi
    
    # Try multiple migration sources
    MIGRATED=false
    
    # 1. Try Orchestrator location
    if migrate_from_source "/var/lib/tor/onion_service" "Orchestrator"; then
        MIGRATED=true
    fi
    
    # 2. Try other common locations
    if [ "$MIGRATED" = false ]; then
        for dir in "/var/lib/tor/hidden_service_old" "/var/lib/tor/onion" "/root/.tor/hidden_service"; do
            if migrate_from_source "$dir" "$(basename $dir)"; then
                MIGRATED=true
                break
            fi
        done
    fi
    
    # 3. Check for backup files
    if [ "$MIGRATED" = false ]; then
        log "Searching for backup files..."
        for backup in /var/lib/tor/hidden_service_backup_* /root/tor_keys_backup*; do
            if [ -d "$backup" ] && [ -n "$(ls -A $backup 2>/dev/null)" ]; then
                log "Found backup directory: $backup"
                read -p "Restore from this backup? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    if migrate_from_source "$backup" "Backup"; then
                        MIGRATED=true
                        break
                    fi
                fi
            fi
        done
    fi
    
    # Final status
    echo ""
    if [ "$MIGRATED" = true ]; then
        log_success "Migration Complete! Your Onion Address is safe."
        log "Backup location: $BACKUP_DIR"
        log "New keys location: $AEGIS_DIR"
        
        if [ "$IN_DOCKER" = false ]; then
            log "You can now start Tor with: systemctl start tor"
        fi
    else
        log_warning "No previous keys found. Aegis will generate a new address."
        log "If you have keys elsewhere, place them in $AEGIS_DIR manually"
    fi
    
    log "Migration log saved to: $LOG_FILE"
}

# Run main function
main "$@"
