#!/bin/bash
# Host-Level Firewall Configuration for Docker Deployment
# This should be run on the Docker HOST, not inside the container
# Provides additional security layer beyond container firewall

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo -e "${CYAN}[+] Configuring Host-Level Firewall for Docker...${NC}"

# Detect Docker bridge interface
DOCKER_BRIDGE=$(docker network inspect bridge 2>/dev/null | grep -oP '"InterfaceName": "\K[^"]+' | head -1)
if [ -z "$DOCKER_BRIDGE" ]; then
    DOCKER_BRIDGE="docker0"
fi

echo -e "${GREEN}[*] Detected Docker bridge: $DOCKER_BRIDGE${NC}"

# Create enhanced nftables ruleset
cat > /etc/nftables/docker-host.conf <<EOF
#!/usr/sbin/nft -f
# Host-Level Firewall for Docker OnionSite-Aegis
# This provides an additional security layer

flush ruleset

table inet filter {
    # Rate limiting sets
    set docker_syn_flood {
        type ipv4_addr
        flags timeout
        timeout 60s
        size 65535
    }
    
    set docker_conn_limit {
        type ipv4_addr
        flags timeout
        timeout 300s
        size 65535
    }
    
    # Input chain
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow loopback
        iifname "lo" accept
        
        # Drop invalid packets
        ct state invalid drop
        
        # Allow established and related
        ct state established,related accept
        
        # Allow Docker bridge
        iifname "$DOCKER_BRIDGE" accept
        
        # SSH protection (if needed)
        tcp dport 22 {
            limit rate 3/minute
            accept
        }
        
        # ICMP (minimal)
        icmp type { echo-request, echo-reply, destination-unreachable } \
            limit rate 1/second accept
        icmpv6 type { echo-request, echo-reply, destination-unreachable } \
            limit rate 1/second accept
        
        # Drop everything else
        log prefix "HOST-FIREWALL-DROP: " drop
    }
    
    # Forward chain (Docker networking)
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Allow Docker bridge forwarding
        iifname "$DOCKER_BRIDGE" oifname "$DOCKER_BRIDGE" accept
        iifname "$DOCKER_BRIDGE" accept
        oifname "$DOCKER_BRIDGE" accept
        
        # Allow established connections
        ct state established,related accept
        
        # Drop everything else
        log prefix "HOST-FORWARD-DROP: " drop
    }
    
    # Output chain
    chain output {
        type filter hook output priority 0; policy accept;
    }
    
    # NAT for Docker (if needed)
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    }
    
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
    }
}

EOF

# Apply rules
nft -f /etc/nftables/docker-host.conf

# Make it persistent
if [ -f /etc/nftables.conf ]; then
    if ! grep -q "docker-host.conf" /etc/nftables.conf; then
        echo "include \"/etc/nftables/docker-host.conf\"" >> /etc/nftables.conf
    fi
fi

echo -e "${GREEN}[+] Host firewall configured${NC}"
echo -e "${CYAN}[*] Rules applied. To make persistent, ensure nftables service is enabled.${NC}"

# Enable nftables service
systemctl enable nftables 2>/dev/null || true
systemctl restart nftables 2>/dev/null || true

echo -e "${GREEN}[+] Host-level firewall deployment complete${NC}"

