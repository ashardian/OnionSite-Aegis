#!/bin/bash
# Sets up RAM-based logging (tmpfs mount) for bare metal installation
# This ensures logs are stored in RAM and vanish on reboot

set -e

# Check if already mounted
if mountpoint -q /mnt/ram_logs 2>/dev/null; then
    echo "RAM logs already mounted"
else
    # Create mount point
    mkdir -p /mnt/ram_logs
    
    # Mount tmpfs (256MB)
    mount -t tmpfs -o size=256M,noexec,nosuid,nodev,mode=1777 tmpfs /mnt/ram_logs
    
    # Add to fstab for persistence across reboots
    if ! grep -q "/mnt/ram_logs" /etc/fstab 2>/dev/null; then
        echo "tmpfs /mnt/ram_logs tmpfs size=256M,noexec,nosuid,nodev,mode=1777 0 0" >> /etc/fstab
    fi
fi

# Create log directories
mkdir -p /mnt/ram_logs/nginx
mkdir -p /mnt/ram_logs/tor
chown -R www-data:www-data /mnt/ram_logs/nginx
chown -R debian-tor:debian-tor /mnt/ram_logs/tor
chmod 750 /mnt/ram_logs/nginx
chmod 700 /mnt/ram_logs/tor

# Create symlinks from standard log locations to RAM
if [ ! -L /var/log/nginx ]; then
    rm -rf /var/log/nginx
    ln -sf /mnt/ram_logs/nginx /var/log/nginx
fi

if [ ! -L /var/log/tor ]; then
    rm -rf /var/log/tor
    ln -sf /mnt/ram_logs/tor /var/log/tor
fi

echo "RAM logging initialized successfully"
