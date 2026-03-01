#!/usr/bin/env python3
import os
from pathlib import Path

import requests

# Configuration
API_TOKEN = "{{ cfdyndns_api_token }}"
UPDATE_URL = "{{ cfdyndns_update_url }}"
LAST_IP_FILE = Path("{{ cfdyndns_last_ip_file }}")
CLOUDFLARE_TRACE_URL = "{{ cfdyndns_cloudflare_trace_url }}"

def get_public_ip():
    """Fetch public IP from Cloudflare trace endpoint"""
    try:
        response = requests.get(CLOUDFLARE_TRACE_URL, timeout=10)
        response.raise_for_status()
        for line in response.text.strip().split('\n'):
            if line.startswith('ip='):
                return line.split('=', 1)[1]
    except Exception as e:
        print(f"Error fetching IP: {e}")
        return None

def get_last_ip():
    """Read last known IP from file"""
    try:
        if LAST_IP_FILE.exists():
            return LAST_IP_FILE.read_text().strip()
    except Exception as e:
        print(f"Error reading last IP: {e}")
    return None

def save_ip(ip):
    """Save current IP to file"""
    try:
        LAST_IP_FILE.parent.mkdir(parents=True, exist_ok=True)
        LAST_IP_FILE.write_text(ip)
    except Exception as e:
        print(f"Error saving IP: {e}")

def update_ip():
    """Send update request with basic auth"""
    try:
        response = requests.get(
            UPDATE_URL,
            auth=("", API_TOKEN),
            timeout=10
        )
        response.raise_for_status()
        print(f"Update successful: {response.status_code}")
        return True
    except Exception as e:
        print(f"Error updating IP: {e}")
        return False

def main():
    current_ip = get_public_ip()
    if not current_ip:
        print("Could not determine current IP")
        return

    last_ip = get_last_ip()

    if current_ip != last_ip:
        print(f"IP changed: {last_ip} -> {current_ip}")
        if update_ip():
            save_ip(current_ip)
    else:
        print(f"IP unchanged: {current_ip}")

if __name__ == "__main__":
    main()
