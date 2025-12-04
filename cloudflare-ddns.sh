#!/usr/bin/env bash
#
# Cloudflare Dynamic DNS Update Script
# Author: YourName
# GitHub: https://github.com/yourname/cloudflare-ddns
# License: MIT
#
# This script updates a Cloudflare DNS record to the current public IP.
# It supports A（IPv4）records.
#
# Requirements:
#   - curl
#

set -e

echo "=============================="
echo "  Cloudflare DDNS Updater"
echo "=============================="
echo

# -----------------------
# Get user input
# -----------------------
read -rp "Enter your Cloudflare Zone Name (example.com): " CF_ZONE
read -rp "Enter the Full Hostname to update (home.example.com): " CF_HOST

echo
echo "You must create a Cloudflare API Token:"
echo "- Permissions: Zone:DNS:Edit + Zone:Read"
echo "- Scope: Your Zone"
echo "Link: https://dash.cloudflare.com/profile/api-tokens"
echo

read -rsp "Enter your Cloudflare API Token: " CF_TOKEN
echo
read -rp "Check interval seconds (default 300): " INTERVAL
INTERVAL=${INTERVAL:-300}

echo
echo "----------------------------------------"
echo "Confirm your settings:"
echo " Zone:        $CF_ZONE"
echo " Hostname:    $CF_HOST"
echo " Interval:    $INTERVAL seconds"
echo "----------------------------------------"
read -rp "Proceed? (y/N): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1

echo
echo "Starting Cloudflare DDNS updater..."
echo

# -----------------------
# Cache File
# -----------------------
CACHE_FILE="/tmp/cf-ddns-ip.cache"

# -----------------------
# Function: get public IP
# -----------------------
get_public_ip() {
    curl -s https://checkip.amazonaws.com || curl -s https://ipv4.icanhazip.com
}

# -----------------------
# Function: get Zone ID
# -----------------------
get_zone_id() {
    curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" |
      grep -oP '"id":"\K[^"]+' | head -1
}

# -----------------------
# Function: get DNS Record ID
# -----------------------
get_record_id() {
    curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${CF_HOST}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" |
      grep -oP '"id":"\K[^"]+' | head -1
}

# -----------------------
# Function: update DNS record
# -----------------------
update_record() {
    curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${CF_HOST}\",\"content\":\"${1}\",\"ttl\":1,\"proxied\":false}"
}

# -----------------------
# Main Loop
# -----------------------
ZONE_ID=$(get_zone_id)
if [[ -z "$ZONE_ID" ]]; then
    echo "ERROR: Unable to fetch Zone ID"
    exit 1
fi

RECORD_ID=$(get_record_id)
if [[ -z "$RECORD_ID" ]]; then
    echo "ERROR: Unable to fetch DNS Record ID"
    exit 1
fi

echo "Zone ID:   $ZONE_ID"
echo "Record ID: $RECORD_ID"
echo

echo "DDNS is running. Press CTRL+C to stop."
echo

while true; do
    NEW_IP=$(get_public_ip)
    OLD_IP=""

    [[ -f "$CACHE_FILE" ]] && OLD_IP=$(cat "$CACHE_FILE")

    if [[ "$NEW_IP" != "$OLD_IP" ]]; then
        echo "$(date '+%F %T') Updating IP: $OLD_IP -> $NEW_IP"
        RESULT=$(update_record "$NEW_IP")

        if echo "$RESULT" | grep -q '"success":true'; then
            echo "$NEW_IP" > "$CACHE_FILE"
            echo "Update successful!"
        else
            echo "ERROR updating DNS:"
            echo "$RESULT"
        fi
    else
        echo "$(date '+%F %T') IP unchanged: $NEW_IP"
    fi

    sleep "$INTERVAL"
done
