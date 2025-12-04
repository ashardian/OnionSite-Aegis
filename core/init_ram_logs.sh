#!/bin/bash
# Ensures log directories exist in the tmpfs (RAM) mount before services start
mkdir -p /mnt/ram_logs/nginx
mkdir -p /mnt/ram_logs/tor
chown -R www-data:www-data /mnt/ram_logs/nginx
chown -R debian-tor:debian-tor /mnt/ram_logs/tor
chmod 750 /mnt/ram_logs/nginx
chmod 700 /mnt/ram_logs/tor
