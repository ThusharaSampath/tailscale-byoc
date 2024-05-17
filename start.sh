#!/bin/sh

/app/tailscaled --tun=userspace-networking --socks5-server=0.0.0.0:1055 --outbound-http-proxy-listen=0.0.0.0:1055 & 
/app/tailscale up --authkey=$TS_AUTH_KEY --shields-up &
/proxy-pass
