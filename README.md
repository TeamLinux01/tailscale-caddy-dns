# This container connects to tailscale and runs a caddy web server. This is useful if you want to put a website on a LAN and a tailnet at the same time or reverse proxy web services in and out of a tailnet. When setting an IP address for a public DNS entry, use the machine's tailscale IP addresses.

### A warning when using DuckDNS, the DNS challenge requires that the server be publicly accessible, so it cannot be used on a tailnet. I will leave in the plug-in as a way of hosting directly on the Internet.

## It is highly recommended that you configure Tailscale before launching the container.

https://login.tailscale.com/admin/dns Confirm a tailnet name, enable MagicDNS and HTTPS Certificates.

https://login.tailscale.com/admin/acls/file Enable tags.

```
...
	// Declare static groups of users. Use autogroups for all users or users with a specific role.
	"groups": {
		"group:apps": [],
	},

	// Define the tags which can be applied to devices and by which users.
	"tagOwners": {
		"tag:apps": ["group:apps"],
	},
...
```

Groups aren't required, but nice if you want to apply other Access Control Lists to them.

https://login.tailscale.com/admin/settings/keys Generate an auth key. I like to make it re-usable and add a tag, so the container machines don't expire and can be added easily.

---

## DNS overrides from your LAN DNS server are require to resolve service names on your LAN. Overrides also work nicely with public DNS records, as that allows the service to be resolved locally when on the LAN and over the tailnet when away from the LAN

To set host overrides on OPNsense: https://docs.opnsense.org/manual/unbound.html#host-override-settings

## An example docker-compose file:

```
version: "3.8"

networks:
  proxy-network:
    name: proxy-network

services:
  proxy:
    image: teamlinux01/tailscale-caddy-dns:latest
    container_name: proxy
    hostname: proxy
    environment:
      # Optional: Used for Cloudflare DNS to get Let's Encrypt TLS certificate
      - CLOUDFLARE_AUTH_TOKEN=${CLOUDFLARE_AUTH_TOKEN}
      # Optional: Used for DuckDNS to get Let's Encrypt TLS certificate; for DNS challenge, server must be publicly accessible.
      - DUCKDNS_API_TOKEN=${DUCKDNS_API_TOKEN}
      # TUN device name, or "userspace-networking" as a magic value to not use kernel support and do everything in-process. You can use "tailscale0" if the container has direct access to hardware.
      - TSD_TUN=userspace-networking
      # UDP port to listen on for peer-to-peer traffic; 0 means to auto-select. Port 41641 is usually the default.
      - TSD_PORT=0
      # Optional: Extra arguments for tailscaled.
      - TSD_EXTRA_ARGS=
      # Name that will show up on Tailnet.
      - TS_HOSTNAME=proxy
      - TS_AUTH_KEY=${TS_AUTH_KEY}
      # Optional: Extra arguments for tailscale. Used for OAuth authentication.
      - TS_EXTRA_ARGS=
    networks:
      - proxy-network
    cap_add:
      - net_admin
      - sys_module
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - $PWD/Caddyfile:/etc/caddy/Caddyfile:ro
      - proxy_data:/data
      - proxy_config:/config
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

volumes:
  proxy_data:
  proxy_config:
```

`docker volume create --name=proxy_data`, `docker volume create --name=proxy_config` to create the volumes and enter the `TS_AUTH_KEY` in the compose file or in `.env` file before running `docker-compose up`.

```
CLOUDFLARE_AUTH_TOKEN=example
DUCKDNS_API_TOKEN=example
TS_AUTH_KEY=tskey-auth-exampleCNTRL-random
```

This will create a container that will join the tailnat with the name of `proxy` and have direct access to other containers that are part of the `proxy-network` docker network.

## Example Caddyfile:

```
host.lan {
        tls internal

        reverse_proxy https://other-machine-name.domain-alias.ts.net {
                header_up Host other-machine-name.domain-alias.ts.net
        }
}
dns-host.public-domain-name {
        tls {
                dns cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
        }

        reverse_proxy https://other-machine-name.domain-alias.ts.net {
                header_up Host other-machine-name.domain-alias.ts.net
        }
}
dns-host.duckdns.org {
        tls {
                dns duckdns {env.DUCKDNS_API_TOKEN}
        }

        reverse_proxy https://other-machine-name.domain-alias.ts.net {
                header_up Host other-machine-name.domain-alias.ts.net
        }
}
proxy.domain-alias.ts.net {
        tls {
                get_certificate tailscale
        }

        reverse_proxy https://host.lan_or_dns-host.public-domain-name {
                header_up Host host.lan_or_dns-host.public-domain-name
        }
}
subdomain.dns-host.public-domain-name {
        reverse_proxy http://other-container:port
}
```

# TrueNAS SCALE settings

## TrueNAS SCALE Caddyfile Example

```
{
        admin off
}

jf.DOMAIN-ALIAS.ts.net {
        tls {
                get_certificate tailscale
        }

        reverse_proxy http://jellyfin.ix-jellyfin.svc.cluster.local:8096
}

*.PUBLIC_DNS_NAME {
        tls {
                dns cloudflare {env.CLOUDFLARE_AUTH_TOKEN}
        }

        @audiobookshelf {
                remote_ip private_ranges
                host audiobookshelf.PUBLIC_DNS_NAME
        }

        @handbrake {
                remote_ip private_ranges
                host handbrake.PUBLIC_DNS_NAME
        }

        @jellyfin {
                remote_ip private_ranges
                host jellyfin.PUBLIC_DNS_NAME
        }

        @librespeed {
                remote_ip private_ranges
                host librespeed.PUBLIC_DNS_NAME
        }

        @makemkv {
                remote_ip private_ranges
                host makemkv.PUBLIC_DNS_NAME
        }

        handle @audiobookshelf {
                reverse_proxy http://audiobookshelf.ix-audiobookshelf.svc.cluster.local:10223
        }

        handle @handbrake {
                reverse_proxy http://handbrake.ix-handbrake.svc.cluster.local:10053
        }

        handle @jellyfin {
                reverse_proxy http://jellyfin.ix-jellyfin.svc.cluster.local:8096
        }

        handle @librespeed {
                reverse_proxy http://librespeed.ix-librespeed.svc.cluster.local:10016
        }

        handle @makemkv {
                reverse_proxy http://makemkv.ix-makemkv.svc.cluster.local:10180
        }

        handle {
                abort
        }
}
```

Add extra IP addresses using spaces to allow `remote_ip` to access from tailnet devices or remove `private_ranges` to deny access to LAN devices. Example: `remote_ip private_ranges 100.X.X.X 100.X.X.Y` to add 2 tailnet devices. Remove the entry completely to allow access from any device that can resolve the DNS and has access to the servers IP addresses and HTTP/HTTPS ports.

## TrueNAS SCALE docker settings

```
# Container Images
Image repository: teamlinux01/tailscale-caddy-dns
Image Tag: latest

# Container Environment Variables 
Environment Variable Name: CLOUDFLARE_AUTH_TOKEN
Environment Variable Value: example

Environment Variable Name: TS_AUTH_KEY
Environment Variable Name:  tskey-auth-exampleCNTRL-random

Environment Variable Name: TS_HOSTNAME
Environment Variable Name: jf

Environment Variable Name: TSD_TUN
Environment Variable Name: tailscale0

# Networking
## Add external interface

Host Interface: enp5s0f1 # Use the interface for your server
IPAM Type: Use Static IP
Static IP: 10.0.0.4/8 # Use whatever unused IP address on your network

DNS Policy: For Pods running with hostNetwork and wanting to prioritise internal kubernetes DNS should make use of this policy.

#Storage
## Add Host Path Volumes

Host Path: /mnt/data/Apps/proxy/Caddyfile # Use where you want the Caddyfile
Mount Path: /etc/caddy/Caddyfile
Read Only: true

## Add Volumes

Mount Path: /data
Dataset Name: proxy-data

Mount Path:/config
Dataset Name: proxy-config

#  Workload Details 
##  Security Context 

 Privileged Mode: true

## Add Capabilities

Add Capability: net_admin
Add Capability: sys_module
```
# Extra things to consider

## OPNsense router settings that can cause issues

If you are using public DNS entries for your tailnet machines, remove the `100.64.0.0/10` network from the Unbound DNS `Rebind protection networks` settings: https://docs.opnsense.org/manual/unbound.html#advanced
