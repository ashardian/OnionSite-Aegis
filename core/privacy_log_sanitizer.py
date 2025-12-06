#!/usr/bin/env python3
"""
Privacy Log Sanitizer
Removes potentially identifying information from logs
"""
import re
import sys
import os
from pathlib import Path

# Patterns to sanitize
SANITIZATION_PATTERNS = [
    (r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP_REDACTED]'),
    (r'[a-zA-Z0-9-]{16,}\.onion\b', '[ONION_REDACTED]'),
    (r'[a-zA-Z0-9-]+\.onion\b', '[ONION_REDACTED]'),
    (r'/[a-zA-Z0-9/_-]+\.(php|sh|py|pl|rb|exe|bin)', '[SCRIPT_PATH_REDACTED]'),
    (r'User-Agent: [^\n]+', 'User-Agent: [REDACTED]'),
    (r'Referer: [^\n]+', 'Referer: [REDACTED]'),
    (r'Cookie: [^\n]+', 'Cookie: [REDACTED]'),
    (r'Authorization: [^\n]+', 'Authorization: [REDACTED]'),
]

def sanitize_line(line):
    """Sanitize a single log line"""
    sanitized = line
    for pattern, replacement in SANITIZATION_PATTERNS:
        sanitized = re.sub(pattern, replacement, sanitized, flags=re.IGNORECASE)
    return sanitized

def sanitize_file(filepath):
    """Sanitize an entire log file"""
    if not os.path.exists(filepath):
        return
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        sanitized_lines = [sanitize_line(line) for line in lines]
        
        # Write to temporary file first
        temp_file = f"{filepath}.tmp"
        with open(temp_file, 'w', encoding='utf-8') as f:
            f.writelines(sanitized_lines)
        
        # Atomic replace
        os.replace(temp_file, filepath)
    except Exception as e:
        print(f"Error sanitizing {filepath}: {e}", file=sys.stderr)

def sanitize_directory(directory):
    """Sanitize all log files in a directory"""
    log_dir = Path(directory)
    if not log_dir.exists():
        return
    
    for log_file in log_dir.rglob('*.log'):
        sanitize_file(str(log_file))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[1]
        if os.path.isdir(target):
            sanitize_directory(target)
        elif os.path.isfile(target):
            sanitize_file(target)
        else:
            print(f"Error: {target} does not exist", file=sys.stderr)
            sys.exit(1)
    else:
        # Default: sanitize RAM logs
        sanitize_directory("/mnt/ram_logs")

