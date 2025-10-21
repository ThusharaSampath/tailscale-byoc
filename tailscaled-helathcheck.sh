#!/bin/bash

echo "Starting Tailscale health check monitor..."

while true; do
    # Check if tailscale status command works (indicates tailscaled is running)
    if ! tailscale status &> /dev/null; then
        echo "ERROR: tailscaled is not responding! Exiting..."
        exit 1
    fi
    
    # Optional: Also check if the process exists
    if ! pgrep -f tailscaled > /dev/null; then
        echo "ERROR: tailscaled process died! Exiting..."
        exit 1
    fi
    
    sleep 10
done