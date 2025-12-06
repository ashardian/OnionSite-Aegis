# Quick Start Guide

## Docker Deployment (5 minutes)

### Prerequisites
- Docker and Docker Compose installed
- Linux host (recommended)

### Steps

1. **Clone/Download the project:**
```bash
cd OnionSite-Aegis
```

2. **Create directories:**
```bash
mkdir -p data/tor-keys webroot
chmod 700 data/tor-keys
```

3. **Add your website:**
```bash
# Example: Create a simple index page
cat > webroot/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>My Onion Site</title>
</head>
<body>
    <h1>Welcome to My Onion Site</h1>
    <p>This site is privacy-focused and secure.</p>
</body>
</html>
EOF
```

4. **Build and start:**
```bash
docker-compose build
docker-compose up -d
```

5. **Get your Onion address:**
```bash
docker-compose exec aegis cat /var/lib/tor/hidden_service/hostname
```

6. **View logs:**
```bash
docker-compose logs -f
```

7. **Stop:**
```bash
docker-compose down
```

## Bare Metal Installation (10 minutes)

### Prerequisites
- Debian 11+ or Parrot OS
- Root access
- Fresh VM or dedicated server (recommended)

### Steps

1. **Download and extract:**
```bash
unzip OnionSite-Aegis.zip
cd OnionSite-Aegis
```

2. **Run installer:**
```bash
sudo chmod +x install.sh
sudo ./install.sh
```

3. **Add your website:**
```bash
sudo cp -r your-website/* /var/www/onion_site/
sudo chown -R www-data:www-data /var/www/onion_site
```

4. **Get your Onion address:**
```bash
sudo cat /var/lib/tor/hidden_service/hostname
```

5. **Check status:**
```bash
sudo systemctl status neural-sentry
sudo systemctl status tor
sudo systemctl status nginx
```

## Next Steps

- **Backup your Tor keys** (critical!):
  - Docker: `tar -czf backup.tar.gz data/tor-keys/`
  - Bare metal: `sudo tar -czf backup.tar.gz /var/lib/tor/hidden_service/`

- **Configure host firewall** (Docker):
  ```bash
  sudo ./docker-host-firewall.sh
  ```

- **Monitor privacy:**
  - Docker: `docker-compose exec aegis /usr/local/bin/privacy_monitor.sh`
  - Bare metal: `sudo /usr/local/bin/privacy_monitor.sh`

- **View logs:**
  - Docker: `docker-compose logs -f`
  - Bare metal: `sudo tail -f /mnt/ram_logs/sentry.log`

## Troubleshooting

**Container won't start:**
- Check logs: `docker-compose logs`
- Verify permissions: `ls -la data/tor-keys`
- Check disk space: `df -h`

**Can't access Onion site:**
- Verify Tor is running: `docker-compose exec aegis ps aux | grep tor`
- Check Tor logs: `docker-compose exec aegis cat /mnt/ram_logs/tor/tor.log`
- Test locally: `docker-compose exec aegis curl http://127.0.0.1:8080`

**Bare metal issues:**
- Check services: `sudo systemctl status tor nginx neural-sentry`
- View logs: `sudo journalctl -u neural-sentry -f`
- Verify firewall: `sudo nft list ruleset`

## Security Notes

- **Always backup Tor keys** - losing them means losing your Onion address
- **Use Docker for better isolation** - recommended for production
- **Configure host firewall** - additional security layer
- **Monitor regularly** - use privacy monitor script
- **Keep updated** - pull latest images/configs regularly

