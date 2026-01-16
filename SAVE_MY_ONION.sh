#!/bin/bash
# SAVE_MY_ONION.sh (v3.0 - Architect Edition)
# Comprehensive Backup & Recovery Tool for Tor Hidden Services.
#
# FEATURES:
# 1. BACKUP: Creates secure .tar.gz archives of current keys.
# 2. RESTORE: Scans system for lost keys or migrates from backups.
# 3. VERIFY: Checks permission integrity and key validity.
#
# Copyright (c) 2026 OnionSite-Aegis
# See LICENSE file for terms and conditions.

set -e

# ==============================================================================
# 1. CONFIGURATION & CONSTANTS
# ==============================================================================

# Visuals
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
AEGIS_DIR="/var/lib/tor/hidden_service"
BACKUP_ROOT="/root/onion_backups"
LOG_FILE="/var/log/aegis_onion_tool.log"

# ==============================================================================
# 2. HELPER FUNCTIONS
# ==============================================================================

log() { echo -e "${CYAN}[ONION-TOOL]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✖${NC} $1"; }

# Root Check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This tool requires root permissions.${NC}"
    exit 1
fi

# Docker Detection
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -n "$DOCKER_CONTAINER" ]; then
    IN_DOCKER=true
fi

# Service Management
stop_tor() {
    if [ "$IN_DOCKER" = true ]; then return; fi
    if systemctl is-active --quiet tor; then
        log "Stopping Tor to release file locks..."
        systemctl stop tor
        sleep 1
    fi
}

start_tor() {
    if [ "$IN_DOCKER" = true ]; then
        log "Running in Docker: Please restart container manually."
    else
        log "Restarting Tor..."
        systemctl start tor
        success "Tor Service Started."
    fi
}

# ==============================================================================
# 3. BACKUP MODULE (EXPORT)
# ==============================================================================
do_backup() {
    echo -e "\n${BLUE}=== BACKUP CURRENT IDENTITY ===${NC}"
    
    # 1. Verify we actually have keys
    if [ ! -f "$AEGIS_DIR/hostname" ] || [ ! -f "$AEGIS_DIR/hs_ed25519_secret_key" ]; then
        error "No complete identity found in $AEGIS_DIR."
        warn "Tor may not have generated keys yet, or they are missing."
        return
    fi

    # 2. Prepare Backup Directory
    mkdir -p "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="onion_keys_backup_${TIMESTAMP}.tar.gz"
    ARCHIVE_PATH="$BACKUP_ROOT/$ARCHIVE_NAME"

    # 3. Create Archive (Preserving permissions is not crucial inside tar, but good practice)
    log "Archiving keys..."
    tar -czf "$ARCHIVE_PATH" -C "$(dirname $AEGIS_DIR)" "$(basename $AEGIS_DIR)"
    
    # 4. Verify
    if [ -f "$ARCHIVE_PATH" ]; then
        success "Backup Created Successfully!"
        echo -e "Location: ${YELLOW}$ARCHIVE_PATH${NC}"
        echo -e "Hostname: ${GREEN}$(cat $AEGIS_DIR/hostname)${NC}"
        echo ""
        warn "ACTION REQUIRED: Copy this file to a secure, offline USB drive."
    else
        error "Backup failed."
    fi
}

# ==============================================================================
# 4. RESTORE MODULE (IMPORT/MIGRATE)
# ==============================================================================
do_restore() {
    echo -e "\n${BLUE}=== RESTORE & MIGRATE ===${NC}"
    warn "This will OVERWRITE any keys currently in $AEGIS_DIR"
    read -p "Are you sure? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then echo "Aborted."; return; fi

    stop_tor

    # Option A: Restore from a specific backup file
    echo -e "\nSelect Restore Method:"
    echo "1. Automatic Scan (Find lost keys on disk)"
    echo "2. Restore from .tar.gz Backup File"
    read -p "Choice [1-2]: " METHOD

    if [ "$METHOD" == "2" ]; then
        read -e -p "Enter path to .tar.gz file: " ARCHIVE_INPUT
        if [ -f "$ARCHIVE_INPUT" ]; then
            log "Extracting..."
            # Clear current dir
            rm -rf "$AEGIS_DIR"/*
            # Extract
            tar -xzf "$ARCHIVE_INPUT" -C /var/lib/tor/
            # Permissions fix (Critical)
            chown -R debian-tor:debian-tor "$AEGIS_DIR"
            chmod 700 "$AEGIS_DIR"
            success "Keys Restored."
        else
            error "File not found."
        fi

    elif [ "$METHOD" == "1" ]; then
        log "Scanning common locations for lost keys..."
        FOUND=false
        # List of places keys might hide
        SEARCH_PATHS=(
            "/var/lib/tor/onion_service"
            "/var/lib/tor/hidden_service_old"
            "/root/tor_backup"
            "/home/debian-tor/hidden_service"
        )

        for src in "${SEARCH_PATHS[@]}"; do
            if [ -d "$src" ] && [ -f "$src/hostname" ]; then
                log "Found keys at: $src"
                cp -r "$src"/* "$AEGIS_DIR/"
                chown -R debian-tor:debian-tor "$AEGIS_DIR"
                chmod 700 "$AEGIS_DIR"
                success "Restored from $src"
                FOUND=true
                break
            fi
        done

        if [ "$FOUND" = false ]; then
            warn "No lost keys found in common locations."
        fi
    fi

    start_tor
    
    # Show result
    if [ -f "$AEGIS_DIR/hostname" ]; then
        echo -e "Active Identity: ${GREEN}$(cat $AEGIS_DIR/hostname)${NC}"
    fi
}

# ==============================================================================
# 5. MAIN MENU
# ==============================================================================
clear
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}   🛡️  ONIONSITE-AEGIS KEY MANAGER  🛡️${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Current Identity:"
if [ -f "$AEGIS_DIR/hostname" ]; then
    echo -e "  ${CYAN}$(cat $AEGIS_DIR/hostname)${NC}"
else
    echo -e "  ${RED}(No active identity found)${NC}"
fi
echo "-------------------------------------------"
echo "1. 📤 BACKUP Current Keys (Create Archive)"
echo "2. 📥 RESTORE Keys (From File or Scan)"
echo "3. 🚪 Exit"
echo "-------------------------------------------"
read -p "Select Option [1-3]: " CHOICE

case "$CHOICE" in
    1)
        do_backup
        ;;
    2)
        do_restore
        ;;
    3)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid option."
        ;;
esac
