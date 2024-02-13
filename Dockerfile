FROM caddy:2.7-builder AS builder

RUN xcaddy build \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/caddy-dns/duckdns

FROM tailscale/tailscale:stable

RUN set -eux; \
mkdir -p \
/config/tailscale \
/config/caddy \
/data/caddy \
/etc/caddy \
/usr/share/caddy \
/lib/modules \
;

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY ./entrypoint.sh /entrypoint.sh
COPY ./Caddyfile /etc/caddy/Caddyfile

ENV XDG_CONFIG_HOME /config
ENV XDG_DATA_HOME /data
ENV OVERRIDE_DEFAULT_ROUTE "false"
ENV GATEWAY_IP ""
ENV LAN_NIC ""
ENV TSD_TUN userspace-networking
ENV TSD_PORT 0
ENV TSD_EXTRA_ARGS ""
ENV TS_HOSTNAME tailscale-caddy-dns
ENV TS_EXTRA_ARGS ""

WORKDIR /srv

CMD ["sh", "/entrypoint.sh"]
