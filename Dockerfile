# OnionSite-Aegis Docker Container
# Privacy-Focused Tor Hidden Service with Enhanced Security
FROM debian:bookworm-slim

LABEL maintainer="OnionSite-Aegis"
LABEL description="Privacy-Focused Tor Hidden Service Orchestrator"
LABEL version="5.0"

# Security: Run as non-root user where possible
# Note: Tor and some services require root, but we'll minimize privileges

# Install dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    tor \
    nginx \
    nftables \
    python3 \
    python3-pip \
    python3-stem \
    tor-geoipdb \
    nginx-extras \
    libnginx-mod-http-modsecurity \
    libnginx-mod-http-headers-more-filter \
    python3-inotify \
    git \
    curl \
    ca-certificates \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install --no-cache-dir stem inotify

# Create necessary directories
RUN mkdir -p \
    /var/www/onion_site \
    /var/lib/tor/hidden_service \
    /mnt/ram_logs \
    /etc/nginx/modsec \
    /usr/local/bin

# Copy configuration files
COPY conf/ /tmp/conf/
COPY core/ /tmp/core/

# Setup RAM logging (will be mounted as tmpfs)
RUN mkdir -p /mnt/ram_logs/nginx /mnt/ram_logs/tor && \
    chown -R www-data:www-data /mnt/ram_logs/nginx && \
    chown -R debian-tor:debian-tor /mnt/ram_logs/tor && \
    chmod 750 /mnt/ram_logs/nginx && \
    chmod 700 /mnt/ram_logs/tor

# Copy and setup scripts
RUN cp /tmp/core/neural_sentry.py /usr/local/bin/ && \
    cp /tmp/core/privacy_log_sanitizer.py /usr/local/bin/ && \
    cp /tmp/core/privacy_monitor.sh /usr/local/bin/ && \
    cp /tmp/core/init_ram_logs.sh /usr/local/bin/ && \
    cp /tmp/core/waf_deploy.sh /usr/local/bin/ && \
    chmod +x /usr/local/bin/*.py /usr/local/bin/*.sh

# Setup Nginx configuration
RUN cp /tmp/conf/nginx_hardened.conf /etc/nginx/sites-available/onion_site && \
    ln -sf /etc/nginx/sites-available/onion_site /etc/nginx/sites-enabled/ && \
    rm -f /etc/nginx/sites-enabled/default

# Setup Tor configuration (will be customized at runtime)
RUN cp /tmp/conf/sysctl_hardened.conf /etc/sysctl.d/99-aegis.conf

# Create minimal web content
RUN echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Secure System</title></head><body><h1>Secure System</h1></body></html>' > /var/www/onion_site/index.html && \
    echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Not Found</title></head><body><h1>Not Found</h1></body></html>' > /var/www/onion_site/404.html && \
    echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Error</title></head><body><h1>Service Temporarily Unavailable</h1></body></html>' > /var/www/onion_site/50x.html && \
    chown -R www-data:www-data /var/www/onion_site && \
    chmod 755 /var/www/onion_site && \
    find /var/www/onion_site -type f -exec chmod 644 {} \;

# Setup permissions
RUN chown -R debian-tor:debian-tor /var/lib/tor && \
    chmod 700 /var/lib/tor/hidden_service

# Create entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Security: Remove unnecessary packages and clean up
RUN apt-get purge -y git curl && \
    apt-get autoremove -y && \
    rm -rf /tmp/conf /tmp/core

# Expose ports (only for documentation - actual binding via docker)
# Tor: 9050 (SOCKS), 9051 (Control)
# Nginx: 8080 (internal, not exposed)
EXPOSE 9050 9051

# Use entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command
CMD ["aegis"]

