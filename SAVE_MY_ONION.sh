#!/bin/bash
# SAVE_MY_ONION.sh
# Migrates keys from Orchestrator to Aegis structure

# 1. Stop Tor to release file locks
systemctl stop tor

# 2. Prepare Aegis Directory
mkdir -p /var/lib/tor/hidden_service

# 3. Copy the keys from Orchestrator location
if [ -d "/var/lib/tor/onion_service" ]; then
    echo "Found Orchestrator keys. Migrating..."
    cp -r /var/lib/tor/onion_service/* /var/lib/tor/hidden_service/
    
    # Fix permissions for Tor (Critical)
    chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
    chmod 700 /var/lib/tor/hidden_service
    echo "Migration Complete. Your Onion Address is safe."
else
    echo "No previous keys found. Aegis will generate a new address."
fi
