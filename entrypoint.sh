#!/bin/sh

set -eux

tailscaled --tun=$TSD_TUN --statedir=/config/tailscale --port=${TSD_PORT} ${TSD_EXTRA_ARGS} &
tailscale up --hostname=$TS_HOSTNAME --authkey=$TS_AUTH_KEY ${TS_EXTRA_ARGS}

caddy run \
  --config /etc/caddy/Caddyfile \
  --adapter caddyfile
