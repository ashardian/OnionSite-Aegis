#!/usr/bin/env python3
import time
import os
import sys
import hashlib
import logging
from stem.control import Controller, Signal
from stem import CircStatus
from collections import deque
import threading

# --- CONFIG ---
TOR_CONTROL_PORT = 9051
WEB_ROOT = "/var/www/onion_site"
LOG_FILE = "/mnt/ram_logs/sentry.log"
MAX_CIRCUITS_PER_MIN = 30  # Attack Threshold

# Ensure log dir exists (in case it wasn't init yet)
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format='%(asctime)s - %(message)s')

class CircuitBreaker:
    def __init__(self):
        self.circuit_history = deque(maxlen=100)
        self.lock = threading.Lock()

    def connect_controller(self):
        try:
            controller = Controller.from_port(port=TOR_CONTROL_PORT)
            controller.authenticate() # Uses Cookie Auth
            return controller
        except Exception as e:
            logging.error(f"Tor Connection Failed: {e}")
            return None

    def kill_all_circuits(self):
        c = self.connect_controller()
        if c:
            logging.warning("DEFENSE TRIGGERED: Sending NEWNYM signal.")
            c.signal(Signal.NEWNYM) # Instantly drops all dirty circuits
            c.close()

    def monitor_circuits(self):
        c = self.connect_controller()
        if not c: return
        
        def handle_event(event):
            if event.status == CircStatus.BUILT:
                with self.lock:
                    self.circuit_history.append(time.time())
                    self.analyze_rate()

        c.add_event_listener(handle_event, 'CIRC')
        logging.info("Sentry watching circuits...")
        try:
            while True: time.sleep(1)
        except: c.close()

    def analyze_rate(self):
        now = time.time()
        recent = [t for t in self.circuit_history if now - t < 60]
        if len(recent) > MAX_CIRCUITS_PER_MIN:
            logging.critical(f"ATTACK DETECTED: {len(recent)} circuits/min.")
            self.kill_all_circuits()
            self.circuit_history.clear()

class FileIntegrity:
    def __init__(self, path):
        self.path = path
        self.hashes = {}

    def scan(self):
        current_hashes = {}
        for root, dirs, files in os.walk(self.path):
            for file in files:
                full_path = os.path.join(root, file)
                try:
                    h = hashlib.sha256(open(full_path, 'rb').read()).hexdigest()
                    current_hashes[full_path] = h
                except: pass
        return current_hashes

    def watch(self):
        self.hashes = self.scan()
        while True:
            time.sleep(10)
            new_hashes = self.scan()
            if new_hashes != self.hashes:
                logging.warning("FILE SYSTEM CHANGE DETECTED")
                self.hashes = new_hashes

if __name__ == "__main__":
    logging.info("Neural Sentry Started")
    
    breaker = CircuitBreaker()
    t1 = threading.Thread(target=breaker.monitor_circuits)
    t1.daemon = True
    t1.start()

    fim = FileIntegrity(WEB_ROOT)
    t2 = threading.Thread(target=fim.watch)
    t2.daemon = True
    t2.start()

    while True: time.sleep(1)
