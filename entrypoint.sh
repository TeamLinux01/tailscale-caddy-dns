#!/bin/sh

set -eux

if [ $OVERRIDE_DEFAULT_ROUTE = "true" ]; then
  ip route delete default
  ip route add default via $GATEWAY_IP dev $LAN_NIC
  if [ $TRUENAS_SYSTEM = "true" ]; then
    ip route add $TRUENAS_SERVICE_NETWORK via $TRUENAS_CLUSTER_GATEWAY_IP dev eth0
  fi
fi

tailscaled --tun=$TSD_TUN --statedir=/config/tailscale --port=${TSD_PORT} ${TSD_EXTRA_ARGS} &
tailscale up --hostname=$TS_HOSTNAME --authkey=$TS_AUTH_KEY ${TS_EXTRA_ARGS}

caddy run \
  --config /etc/caddy/Caddyfile \
  --adapter caddyfile \
  --watch
