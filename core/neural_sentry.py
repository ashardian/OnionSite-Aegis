#!/usr/bin/env python3
"""
Neural Sentry - Privacy-Focused Active Defense System
Monitors Tor circuits, file integrity, and privacy threats

Copyright (c) 2026 OnionSite-Aegis
See LICENSE file for terms and conditions.
Note: Author is not responsible for illegal use of this software.
"""
import time
import os
import sys
import hashlib
import logging
import signal
import json
import re
from stem.control import Controller, Signal, EventType  # FIX: Added EventType
from stem import CircStatus
from collections import deque
import threading
from pathlib import Path

# Try to use inotify for real-time file monitoring (fallback to polling)
try:
    import inotify.adapters
    INOTIFY_AVAILABLE = True
except ImportError:
    INOTIFY_AVAILABLE = False

# --- CONFIG ---
TOR_CONTROL_PORT = 9051
WEB_ROOT = "/var/www/onion_site"
LOG_FILE = "/var/log/tor/sentry.log"
MAX_CIRCUITS_PER_MIN = 30  # Attack Threshold
MAX_CIRCUITS_PER_10SEC = 15  # Burst detection
FILE_CHECK_INTERVAL = 5  # Seconds between file checks (if no inotify)
CONNECTION_RETRY_DELAY = 5  # Seconds to wait before retrying Tor connection
PRIVACY_LOG_SANITIZE = True  # Remove sensitive data from logs

# Ensure log dir exists (in case it wasn't init yet)
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

# Configure logging with privacy-focused sanitization
class PrivacyFilter(logging.Filter):
    """Removes potentially sensitive information from logs"""
    def filter(self, record):
        if PRIVACY_LOG_SANITIZE:
            # Remove IP addresses, hostnames, and other identifiers
            msg = str(record.getMessage())
            msg = re.sub(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_REDACTED]', msg)
            msg = re.sub(r'[a-zA-Z0-9-]+\.onion\b', '[ONION_REDACTED]', msg)
            record.msg = msg
        return True

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger()
logger.addFilter(PrivacyFilter())

class CircuitBreaker:
    """Monitors Tor circuits for deanonymization attacks and DDoS"""
    def __init__(self):
        self.circuit_history = deque(maxlen=200)
        self.lock = threading.Lock()
        self.controller = None
        self.running = True
        self.attack_count = 0
        self.last_newym = 0

    def connect_controller(self, retry=True):
        """Connect to Tor control port with retry logic"""
        max_retries = 3
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                controller = Controller.from_port(port=TOR_CONTROL_PORT)
                controller.authenticate()  # Uses Cookie Auth
                logging.info("Connected to Tor control port")
                return controller
            except Exception as e:
                retry_count += 1
                if retry and retry_count < max_retries:
                    logging.warning(f"Tor connection failed (attempt {retry_count}/{max_retries}), retrying...")
                    time.sleep(CONNECTION_RETRY_DELAY)
                else:
                    logging.error(f"Tor Connection Failed after {max_retries} attempts: {e}")
                    return None
        return None

    def kill_all_circuits(self):
        """Force new identity to break deanonymization attempts"""
        # Prevent rapid-fire NEWNYM signals (rate limit)
        now = time.time()
        if now - self.last_newym < 10:
            logging.warning("NEWNYM rate limited (cooldown active)")
            return
            
        c = self.connect_controller(retry=False)
        if c:
            try:
                logging.warning("DEFENSE TRIGGERED: Sending NEWNYM signal to break circuits")
                c.signal(Signal.NEWNYM)  # Instantly drops all dirty circuits
                self.attack_count += 1
                self.last_newym = now
                logging.info(f"NEWNYM executed (total defenses: {self.attack_count})")
            except Exception as e:
                logging.error(f"Failed to send NEWNYM: {e}")
            finally:
                c.close()

    def monitor_circuits(self):
        """Continuously monitor circuit events"""
        while self.running:
            self.controller = self.connect_controller()
            if not self.controller:
                logging.error("Cannot connect to Tor, retrying in 10 seconds...")
                time.sleep(10)
                continue
            
            def handle_event(event):
                if event.status == CircStatus.BUILT:
                    with self.lock:
                        self.circuit_history.append(time.time())
                        self.analyze_rate()

            try:
                # FIX: Use EventType.CIRC instead of string 'CIRC'
                self.controller.add_event_listener(handle_event, EventType.CIRC)
                logging.info("Circuit monitoring active")
                
                # Keep connection alive and handle events
                while self.running:
                    time.sleep(1)
                    # Verify controller is still connected
                    try:
                        self.controller.get_info("version")
                    except:
                        logging.warning("Controller connection lost, reconnecting...")
                        break
            except Exception as e:
                logging.error(f"Circuit monitoring error: {e}")
                if self.controller:
                    try:
                        self.controller.close()
                    except:
                        pass
                time.sleep(5)

    def analyze_rate(self):
        """Analyze circuit creation rate for attack patterns"""
        now = time.time()
        
        # Check 1-minute window
        recent_1min = [t for t in self.circuit_history if now - t < 60]
        if len(recent_1min) > MAX_CIRCUITS_PER_MIN:
            logging.critical(f"ATTACK DETECTED (1min): {len(recent_1min)} circuits/min (threshold: {MAX_CIRCUITS_PER_MIN})")
            self.kill_all_circuits()
            self.circuit_history.clear()
            return
        
        # Check 10-second burst window (more sensitive)
        recent_10sec = [t for t in self.circuit_history if now - t < 10]
        if len(recent_10sec) > MAX_CIRCUITS_PER_10SEC:
            logging.critical(f"BURST ATTACK DETECTED (10sec): {len(recent_10sec)} circuits (threshold: {MAX_CIRCUITS_PER_10SEC})")
            self.kill_all_circuits()
            # Don't clear history for burst detection, keep monitoring

class FileIntegrity:
    """Monitors file system for unauthorized changes"""
    def __init__(self, path):
        self.path = Path(path)
        self.hashes = {}
        self.running = True
        self.change_count = 0
        self.suspicious_files = {'.php', '.sh', '.py', '.pl', '.rb', '.exe', '.bin'}
        
    def scan(self):
        """Generate SHA256 hashes for all files"""
        current_hashes = {}
        if not self.path.exists():
            logging.error(f"Web root does not exist: {self.path}")
            return current_hashes
            
        for root, dirs, files in os.walk(self.path):
            # Skip hidden directories
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            
            for file in files:
                full_path = Path(root) / file
                try:
                    if full_path.is_file() and full_path.stat().st_size > 0:
                        with open(full_path, 'rb') as f:
                            h = hashlib.sha256(f.read()).hexdigest()
                            current_hashes[str(full_path)] = h
                except (OSError, IOError, PermissionError) as e:
                    logging.debug(f"Cannot hash {full_path}: {e}")
        return current_hashes

    def analyze_changes(self, old_hashes, new_hashes):
        """Analyze what changed and alert on suspicious activity"""
        added = set(new_hashes.keys()) - set(old_hashes.keys())
        removed = set(old_hashes.keys()) - set(new_hashes.keys())
        modified = {k for k in set(old_hashes.keys()) & set(new_hashes.keys()) 
                   if old_hashes[k] != new_hashes[k]}
        
        if added:
            for f in added:
                ext = Path(f).suffix.lower()
                severity = "CRITICAL" if ext in self.suspicious_files else "WARNING"
                logging.warning(f"FILE ADDED [{severity}]: {Path(f).name} (ext: {ext})")
                self.change_count += 1
                
        if removed:
            for f in removed:
                logging.warning(f"FILE REMOVED: {Path(f).name}")
                self.change_count += 1
                
        if modified:
            for f in modified:
                ext = Path(f).suffix.lower()
                severity = "CRITICAL" if ext in self.suspicious_files else "INFO"
                logging.warning(f"FILE MODIFIED [{severity}]: {Path(f).name}")
                self.change_count += 1

    def watch_inotify(self):
        """Real-time file monitoring using inotify (Linux)"""
        if not INOTIFY_AVAILABLE:
            logging.warning("inotify not available, falling back to polling")
            return False
            
        try:
            i = inotify.adapters.InotifyTree(str(self.path))
            logging.info(f"Real-time file monitoring active (inotify) on {self.path}")
            
            # Initial scan
            self.hashes = self.scan()
            logging.info(f"Initial integrity scan: {len(self.hashes)} files")
            
            for event in i.event_gen():
                if not self.running:
                    break
                    
                if event is not None:
                    (header, type_names, watch_path, filename) = event
                    
                    # Only react to meaningful changes
                    if any(t in type_names for t in ['IN_MODIFY', 'IN_CREATE', 'IN_DELETE', 'IN_MOVED_TO', 'IN_MOVED_FROM']):
                        full_path = Path(watch_path) / filename
                        if full_path.is_file() and not filename.startswith('.'):
                            # Re-scan to get accurate state
                            time.sleep(0.5)  # Brief delay for file write completion
                            new_hashes = self.scan()
                            self.analyze_changes(self.hashes, new_hashes)
                            self.hashes = new_hashes
                            
            return True
        except Exception as e:
            logging.error(f"Inotify monitoring failed: {e}")
            return False

    def watch_polling(self):
        """Fallback polling-based file monitoring"""
        logging.info(f"Polling-based file monitoring active on {self.path} (interval: {FILE_CHECK_INTERVAL}s)")
        self.hashes = self.scan()
        logging.info(f"Initial integrity scan: {len(self.hashes)} files")
        
        while self.running:
            time.sleep(FILE_CHECK_INTERVAL)
            new_hashes = self.scan()
            if new_hashes != self.hashes:
                self.analyze_changes(self.hashes, new_hashes)
                self.hashes = new_hashes

    def watch(self):
        """Main watch loop - tries inotify first, falls back to polling"""
        if not self.watch_inotify():
            self.watch_polling()

class PrivacyMonitor:
    """Additional privacy-focused monitoring"""
    def __init__(self):
        self.running = True
        
    def check_tor_status(self):
        """Verify Tor is running and properly configured"""
        try:
            controller = Controller.from_port(port=TOR_CONTROL_PORT)
            controller.authenticate()
            version = controller.get_version()
            logging.info(f"Tor version: {version}")
            
            # Check if SafeLogging is enabled
            safe_logging = controller.get_conf("SafeLogging")
            if safe_logging != "1":
                logging.warning("SafeLogging is not enabled - privacy risk!")
            
            controller.close()
            return True
        except Exception as e:
            logging.error(f"Tor status check failed: {e}")
            return False
    
    def monitor(self):
        """Periodic privacy checks"""
        while self.running:
            time.sleep(300)  # Check every 5 minutes
            self.check_tor_status()

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    logging.info(f"Received signal {signum}, shutting down gracefully...")
    
    # FIX: Safely check if objects exist before stopping them
    if globals().get('breaker'):
        breaker.running = False
    if globals().get('fim'):
        fim.running = False
    if globals().get('privacy_mon'):
        privacy_mon.running = False
        
    sys.exit(0)

if __name__ == "__main__":
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logging.info("=" * 50)
    logging.info("Neural Sentry v5.0 - Privacy-Focused Active Defense")
    logging.info("=" * 50)
    
    # Verify web root exists
    if not os.path.exists(WEB_ROOT):
        logging.warning(f"Web root {WEB_ROOT} does not exist, creating...")
        os.makedirs(WEB_ROOT, exist_ok=True)
    
    # Initialize components
    breaker = CircuitBreaker()
    fim = FileIntegrity(WEB_ROOT)
    privacy_mon = PrivacyMonitor()
    
    # Start monitoring threads
    t1 = threading.Thread(target=breaker.monitor_circuits, name="CircuitMonitor")
    t1.daemon = True
    t1.start()

    t2 = threading.Thread(target=fim.watch, name="FileIntegrity")
    t2.daemon = True
    t2.start()
    
    t3 = threading.Thread(target=privacy_mon.monitor, name="PrivacyMonitor")
    t3.daemon = True
    t3.start()
    
    logging.info("All monitoring systems active")
    logging.info(f"Circuit threshold: {MAX_CIRCUITS_PER_MIN}/min, {MAX_CIRCUITS_PER_10SEC}/10sec")
    logging.info(f"File monitoring: {'inotify' if INOTIFY_AVAILABLE else 'polling'} mode")
    
    # Main loop - keep process alive
    try:
        while True:
            time.sleep(1)
            # Health check - verify threads are alive
            if not t1.is_alive():
                logging.error("Circuit monitor thread died, restarting...")
                t1 = threading.Thread(target=breaker.monitor_circuits, name="CircuitMonitor")
                t1.daemon = True
                t1.start()
    except KeyboardInterrupt:
        signal_handler(signal.SIGINT, None)
