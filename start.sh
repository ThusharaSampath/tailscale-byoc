#!/bin/sh

# check if the TS_AUTH_KEY has set
if [ -z "${TS_AUTH_KEY}" ]; then
  echo "Error: TS_AUTH_KEY env variable could not be found. Exiting... Please refer to the documentation: https://wso2.com/choreo/docs/devops-and-ci-cd/configure-vpns-on-the-choreo-cloud-data-plane/#step-2-configure-and-deploy-the-tailscale-proxy"
  exit 1
fi

# check if the volume mounts are added
dirs="/.local /var/run/tailscale"

for dir in $dirs; do
  if [ -w "$dir" ]; then
    echo "$dir is properly mounted."
  else
    echo "Error: $dir does not exist or is not writable. Exiting... Please refer to the documentation: https://wso2.com/choreo/docs/devops-and-ci-cd/configure-vpns-on-the-choreo-cloud-data-plane/#step-2-configure-and-deploy-the-tailscale-proxy"
    exit 1
  fi
done

/tailscaled --tun=userspace-networking --socks5-server=0.0.0.0:1055 --outbound-http-proxy-listen=0.0.0.0:1055 &
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


/tailscale up --authkey=$TS_AUTH_KEY --shields-up &
TAILSCALE_UP_PID=$!

# Function to check if tailscale up is ready
check_tailscale_up() {
  if /tailscale status | grep -q '100.'; then
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

echo "starting tcp-forwarder..."

# check if config file exists
CONFIG_PATH='/config.yaml'

if [ -f "config.yaml" ]; then
  echo "config.yaml exists."
elif [ -f "Config.yaml" ]; then
  echo "Config.yaml exists."
  CONFIG_PATH='/Config.yaml'
else
  echo "Error: config.yaml could not be found. Exiting... Please refer to the documentation: https://wso2.com/choreo/docs/devops-and-ci-cd/configure-vpns-on-the-choreo-cloud-data-plane/#step-2-configure-and-deploy-the-tailscale-proxy"
  exit 1
fi

./proxy-pass -config=$CONFIG_PATH