#!/bin/sh

/app/tailscaled --tun=userspace-networking --socks5-server=0.0.0.0:1055 --outbound-http-proxy-listen=0.0.0.0:1055 &
TAILSCALED_PID=$!

# Function to check if tailscaled is ready
check_tailscaled() {
  if pgrep -f tailscaled > /dev/null; then
    return 0
  else
    return 1
  fi
}

# Wait for tailscaled to be ready
while ! check_tailscaled; do
  echo "Waiting for tailscaled to start..."
  sleep 2
done

echo "tailscaled is running."


/app/tailscale up --authkey=$TS_AUTH_KEY --shields-up &
TAILSCALE_UP_PID=$!

# Function to check if tailscale up is ready
check_tailscale_up() {
  if /app/tailscale status | grep -q '100.'; then
    return 0
  else
    return 1
  fi
}

# Wait for tailscale up to be ready
while ! check_tailscale_up; do
  echo "Waiting for tailscale up to complete..."
  sleep 2
done

echo "tailscale up is complete."

/proxy-pass
