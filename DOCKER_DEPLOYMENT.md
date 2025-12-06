# Docker Deployment Guide

## Overview

Docker deployment provides enhanced security through container isolation, making it safer than bare-metal installation. The container runs with minimal privileges and is isolated from the host system.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Linux host (recommended)
- At least 512MB RAM available
- 1GB disk space

## Quick Start

### 1. Prepare Directories

```bash
mkdir -p data/tor-keys webroot
chmod 700 data/tor-keys
```

### 2. Create Web Content

Place your website files in the `webroot/` directory:

```bash
echo "<h1>My Onion Site</h1>" > webroot/index.html
```

### 3. Build and Run

```bash
# Build the image
docker-compose build

# Start the container
docker-compose up -d

# View logs
docker-compose logs -f

# Get your Onion address
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```

## Security Features

### Container Isolation
- **Network Isolation**: Internal bridge network with no external access
- **Read-only Web Content**: Webroot mounted as read-only
- **Minimal Capabilities**: Only required Linux capabilities
- **Seccomp Profile**: Restricted system calls
- **AppArmor**: Additional access control
- **No New Privileges**: Prevents privilege escalation

### Resource Limits
- CPU: 2 cores max, 0.5 cores reserved
- Memory: 512MB max, 256MB reserved
- Prevents resource exhaustion attacks

### Persistent Storage
- **Tor Keys**: Stored in `data/tor-keys/` (critical - backup this!)
- **RAM Logs**: Temporary, in-memory only (privacy)
- **Web Content**: Read-only mount from `webroot/`

## Configuration

### Custom Tor Configuration

Create a custom `torrc` file and mount it:

```yaml
volumes:
  - ./custom-torrc:/etc/tor/torrc:ro
```

### Custom Nginx Configuration

Mount custom nginx config:

```yaml
volumes:
  - ./custom-nginx.conf:/etc/nginx/sites-available/onion_site:ro
```

### Environment Variables

Edit `docker-compose.yml` to add environment variables:

```yaml
environment:
  - TZ=UTC
  - TOR_CONTROL_PORT=9051
  - MAX_CIRCUITS_PER_MIN=30
```

## Firewall Configuration

The container includes enhanced NFTables rules, but for maximum security, configure firewall at the **host level**:

### Host-Level Firewall (Recommended)

On the Docker host, configure iptables/nftables to:
- Block all incoming connections except SSH (if needed)
- Allow Docker bridge network communication
- Rate limit connections
- Log suspicious activity

Example host firewall script:

```bash
#!/bin/bash
# Host-level firewall for Docker
nft flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow loopback
        iifname "lo" accept
        
        # Allow established connections
        ct state established,related accept
        
        # Allow SSH (optional)
        tcp dport 22 limit rate 3/minute accept
        
        # Allow Docker
        iifname "docker0" accept
        
        # Drop everything else
        drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
        # Allow Docker bridge forwarding
        iifname "docker0" oifname "docker0" accept
    }
}
```

## Backup and Recovery

### Backup Tor Keys

**CRITICAL**: Backup your Tor keys to preserve your Onion address:

```bash
# Backup
tar -czf onion-keys-backup-$(date +%Y%m%d).tar.gz data/tor-keys/

# Restore
tar -xzf onion-keys-backup-YYYYMMDD.tar.gz -C data/
```

### Backup Web Content

```bash
tar -czf webroot-backup-$(date +%Y%m%d).tar.gz webroot/
```

## Monitoring

### View Logs

```bash
# All logs
docker-compose logs

# Follow logs
docker-compose logs -f

# Specific service
docker-compose logs neural-sentry
```

### Health Check

```bash
# Check container health
docker-compose ps

# Execute commands in container
docker-compose exec aegis /bin/bash

# Check Tor status
docker-compose exec aegis systemctl status tor

# Check Neural Sentry
docker-compose exec aegis ps aux | grep neural_sentry
```

### Privacy Monitor

```bash
# Run privacy check
docker-compose exec aegis /usr/local/bin/privacy_monitor.sh
```

## Troubleshooting

### Container Won't Start

1. Check logs: `docker-compose logs`
2. Verify permissions: `ls -la data/tor-keys`
3. Check disk space: `df -h`
4. Verify Docker resources: `docker system df`

### Tor Not Starting

1. Check Tor logs: `docker-compose exec aegis cat /mnt/ram_logs/tor/tor.log`
2. Verify key permissions: `chmod 700 data/tor-keys`
3. Check for port conflicts: `netstat -tulpn | grep 9051`

### Can't Access Onion Site

1. Verify Tor is running: `docker-compose exec aegis ps aux | grep tor`
2. Get Onion address: `docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname`
3. Test locally: `docker-compose exec aegis curl http://127.0.0.1:8080`

### High Resource Usage

1. Check resource limits in `docker-compose.yml`
2. Monitor: `docker stats onionsite-aegis`
3. Adjust limits if needed

## Advanced Configuration

### Custom Network

Create isolated network:

```yaml
networks:
  aegis-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.29.0.0/16
```

### Multiple Instances

Run multiple instances on different ports:

```yaml
services:
  aegis-1:
    # ... config ...
    ports:
      - "9051:9051"
  
  aegis-2:
    # ... config ...
    ports:
      - "9052:9051"
```

### Integration with Host Firewall

Use Docker's iptables integration or configure host firewall separately.

## Production Deployment

### Security Checklist

- [ ] Host firewall configured
- [ ] Docker daemon secured (TLS, user namespace)
- [ ] Secrets management (use Docker secrets or external vault)
- [ ] Regular backups of Tor keys
- [ ] Monitoring and alerting configured
- [ ] Log aggregation (if needed, with privacy in mind)
- [ ] Resource limits set appropriately
- [ ] Network isolation verified
- [ ] Regular security updates

### Performance Tuning

1. **CPU Pinning**: Pin container to specific CPUs
2. **Memory Limits**: Adjust based on traffic
3. **Network**: Use host network mode only if necessary (reduces isolation)
4. **Storage**: Use SSD for persistent volumes

### Maintenance

```bash
# Update container
docker-compose pull
docker-compose up -d

# Clean up
docker-compose down
docker system prune -a

# Update base image
docker-compose build --no-cache
```

## Comparison: Docker vs Bare Metal

| Feature | Docker | Bare Metal |
|---------|--------|------------|
| Isolation | High | Low |
| Security | Enhanced (seccomp, capabilities) | Depends on host |
| Portability | High | Low |
| Resource Usage | Slightly higher | Lower |
| Setup Complexity | Medium | High |
| Maintenance | Easier | More complex |

## Support

For issues or questions:
1. Check logs: `docker-compose logs`
2. Review configuration files
3. Verify system requirements
4. Check Docker and host firewall settings

