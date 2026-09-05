#!/usr/bin/env python3
import os
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import requests

# Configuration
API_EMAIL = {{ cfdyndns_api_email | to_json }}
API_TOKEN = {{ cfdyndns_api_token | to_json }}
UPDATE_URL = {{ cfdyndns_update_url | to_json }}
LAST_IP_FILE = Path({{ cfdyndns_last_ip_file | to_json }})
CLOUDFLARE_TRACE_URL = {{ cfdyndns_cloudflare_trace_url | to_json }}
UPDATE_HOSTNAMES = {{ cfdyndns_update_hostnames | default([]) | to_json }}

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

def update_ip(ip):
    """Send update request with basic auth"""
    update_url = UPDATE_URL.replace("%i", ip)
    if UPDATE_HOSTNAMES:
        update_url = update_url.replace("%h", ",".join(UPDATE_HOSTNAMES))
        parsed_url = urlsplit(update_url)
        query = dict(parse_qsl(parsed_url.query, keep_blank_values=True))
        query["ip"] = ip
        query["hostname"] = ",".join(UPDATE_HOSTNAMES)
        update_url = urlunsplit(parsed_url._replace(query=urlencode(query)))

    try:
        response = requests.get(
            update_url,
            auth=(API_EMAIL, API_TOKEN),
            timeout=10
        )
        if not response.ok:
            detail = response.text.strip()
            print(f"Error updating IP: HTTP {response.status_code}: {detail}")
            return False
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
        if update_ip(current_ip):
            save_ip(current_ip)
    else:
        print(f"IP unchanged: {current_ip}")

if __name__ == "__main__":
    main()
