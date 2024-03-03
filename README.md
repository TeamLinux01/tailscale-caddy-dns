# This container connects to tailscale and runs a caddy web server. This is useful if you want to put a website on a LAN and a tailnet at the same time or reverse proxy web services in and out of a tailnet. When setting an IP address for a public DNS entry, use the machine's tailscale IP addresses.

> ⚠️ Warning
>
> When using DuckDNS, the DNS challenge requires that the server be publicly accessible, so it cannot be used on a tailnet. I will leave in the plug-in as a way of hosting directly on the Internet.

## Configure Tailscale

> ⚠️ Warning
>
> It is require to do this before you start the containers.

https://login.tailscale.com/admin/dns Confirm a tailnet name, enable MagicDNS and HTTPS Certificates.

https://login.tailscale.com/admin/acls/file Enable tags.

This text is towards the top of the entry for ACLs normally, although it shouldn't matter exactly where it is; just make sure it isn't in the middle of another code block and that it is located in only the first `{`.

```
	// Declare static groups of users. Use autogroups for all users or users with a specific role.
	"groups": {
		"group:apps": [],
	},

	// Define the tags which can be applied to devices and by which users.
	"tagOwners": {
		"tag:apps": ["group:apps"],
	},
```

Groups aren't required, but nice if you want to apply other Access Control Lists to them.

https://login.tailscale.com/admin/settings/keys Generate an Auth key. I like to make it re-usable and add a tag, so the container machines don't expire and can be added easily.

---

### DNS overrides

> ⚠️ Warning
>
> These are require to resolve service names on your LAN. Overrides also work nicely with public DNS records, as that allows the service to be resolved locally when on the LAN and over the tailnet when away from the LAN.

To set host overrides on OPNsense: https://docs.opnsense.org/manual/unbound.html#host-override-settings

## Configuration files

> ⚠️ Warning
>
> Before executing the docker run command, create these two files and run the docker network create command.
>
> Before executing the docker compose command, only create these two files:

`.env`:

```
CLOUDFLARE_AUTH_TOKEN=example
DUCKDNS_API_TOKEN=example
TS_AUTH_KEY=tskey-auth-exampleCNTRL-random
```

`Caddyfile`:

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

Run `docker network create proxy-network` to create the proxy network.

### An example docker run command (internal docker network):

Docker command in Bash:

```
set -a && \
. .env && \
set +a && \
docker run --detach --rm \
  --name=proxy \
  --network=proxy-network \
  --cap-add=net_admin \
  --cap-add=sys_module \
  --publish=80:80 \
  --publish=443:443 \
  --publish=443:443/udp \
  -e=CLOUDFLARE_AUTH_TOKEN=${CLOUDFLARE_AUTH_TOKEN} \
  -e=TS_AUTH_KEY=${TS_AUTH_KEY} \
  -e=TS_HOSTNAME=proxy \
  -device=/dev/net/tun:/dev/net/tun \
  --mount=type=bind,source=$PWD/Caddyfile,target=/etc/caddy/Caddyfile \
  --volume=proxy_data:/data \
  --volume=proxy_config:/config \
  teamlinux01/tailscale-caddy-dns
```

The `set -a` command block will load the environmental variables onto the host and pass them into the container. If you don't want to set them via a file, just replace the `${}` text with the keys.

This will create a container that will join the tailnat with the name of `proxy` and have direct access to other containers that are part of the `proxy-network` docker network. The container will run in the background and be removed when `docker stop proxy` is run. The volumes will stay intact, so a new container can be started and it will keep the same tailscale Auth/caddy TLS data.

### An example docker compose file (internal docker network):

`compose.yml`:

```
version: "3.8"

networks:
  proxy-network:
    name: proxy-network

services:
  proxy:
    image: teamlinux01/tailscale-caddy-dns:latest
    container_name: caddy
    environment:
      # Optional: Used for Cloudflare DNS to get Let's Encrypt TLS certificate.
      - CLOUDFLARE_AUTH_TOKEN=${CLOUDFLARE_AUTH_TOKEN}
      # Optional: Used for DuckDNS to get Let's Encrypt TLS certificate; for DNS challenge, server must be publicly accessible.
      - DUCKDNS_API_TOKEN=${DUCKDNS_API_TOKEN}

      # Optional: Use if you need to change the default route in the container, usually defaults to the docker network, but needs to change if you expose a physical NIC with dedicated IP to the container. Set to "true" if override is needed. "false" value is included in the image.
      - OVERRIDE_DEFAULT_ROUTE="false"
      # Optional: Set to the Gateway IP for the override default route. An example would be setting to "192.168.0.1" for a exposed NIC with dedicated IP on a 192.168.0.0/24 network and the router address is 192.168.0.1.
      - GATEWAY_IP=
      # Optional: Set to the name of the network interface that the exposed physical NIC is named in the container. TrueNAS SCALE uses "net0", "net1", etc... for each network card in the machine.
      - LAN_NIC=

      # Optional: Use if you are using on a TrueNAS SCALE system for it to access the Service Network on the docker/kubernetes network, which includes the cluster DNS server address. If this is not added, the container will not be able to resolve other containers names. "false" value is included in the image.
      - TRUENAS_SYSTEM="false"
      # Optional: Use if you are using on a TrueNAS SCALE system, the default Service Network is "172.17.0.0/16".
      - TRUENAS_SERVICE_NETWORK=
      # Optional: Use if you are using on a TrueNAS SCALE system, the default Cluster gateway is "172.16.0.1".
      - TRUENAS_CLUSTER_GATEWAY_IP=

      # TUN device name, or "userspace-networking" as a magic value to not use kernel support and do everything in-process. You can use "tailscale0" if the container has direct access to hardware. "userspace-networking" value is included in the image.
      - TSD_TUN=userspace-networking
      # UDP port to listen on for peer-to-peer traffic; 0 means to auto-select. Port 41641 is the default that tailscaled will try to use. "0" value is included in the image.
      - TSD_PORT=0
      # Optional: Extra arguments for tailscaled.
      - TSD_EXTRA_ARGS=
      # Name that will show up on Tailnet.

      # Optional: Enable tailscaled and tailscale service. "true" value is included in the image.
      - TS_ENABLE=true
      # Optional: Host name used on the tailnet. It will automatically be pulled from system if not provided.
      - TS_HOSTNAME=proxy
      # Optional only if TS_ENABLE is not set to "true". The Tailscale Auth key that is generated at https://login.tailscale.com/admin/settings/keys
      - TS_AUTH_KEY=${TS_AUTH_KEY}
      # Optional: Extra arguments for tailscale. Used for OAuth authentication.
      - TS_EXTRA_ARGS=
    networks:
      - proxy-network
    cap_add:
      - net_admin
      - sys_module
    # ports are only required if you want to host the server on the LAN. No ports are required to be opened to access over the tailnet.
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - proxy_data:/data
      - proxy_config:/config
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

volumes:
  proxy_data:
  proxy_config:
```

Run `docker-compose up`. This will create a container that will join the tailnat with the name of `proxy` and have direct access to other containers that are part of the `proxy-network` docker network.

## Host networking of the container

> ⚠️ Warning
>
> Do not forget to open the firewall for ports 80 and 443 on the host.

To open the ports on Fedora server, run:

```bash
sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --permanent --add-service=https
```

To close the ports again on Fedora server, run:

```bash
sudo firewall-cmd --permanent --remove-service=http && sudo firewall-cmd --permanent --remove-service=https
```

### An example docker compose file (host network):

`compose.yml`:

```
version: "3.8"

services:
  proxy:
    image: teamlinux01/tailscale-caddy-dns:latest
    container_name: caddy
    environment:
      - CLOUDFLARE_AUTH_TOKEN=${CLOUDFLARE_AUTH_TOKEN}
      - TSD_TUN=tailscale0
      - TS_HOSTNAME=proxy
      - TS_AUTH_KEY=${TS_AUTH_KEY}
    network_mode: "host"
    cap_add:
      - net_admin
      - sys_module
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - proxy_data:/data
      - proxy_config:/config
      - /dev/net/tun:/dev/net/tun
      - /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket
    restart: unless-stopped

volumes:
  proxy_data:
  proxy_config:
```

> ⚠️ Warning
>
> The tailscale-caddy-dns container will not be able to access other docker containers via the internal network, all containers will have to publish the ports they use.
>
> I recommend using `127.0.0.1:`port or `:::`port to publish only to the loop-back address.
>
> Use `reverse_proxy localhost:`port to establish the connection.

## TrueNAS SCALE settings

### TrueNAS SCALE Caddyfile Example

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

        @nextcloud {
                remote_ip private_ranges
                host nextcloud.PUBLIC_DNS_NAME
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

        handle @nextcloud {
                rewrite /.well-known/carddav /remote.php/dav
                rewrite /.well-known/caldav /remote.php/dav

                reverse_proxy http://nextcloud.ix-nextcloud.svc.cluster.local
                header {
                        Strict-Transport-Security max-age=31536000;
                }
        }

        handle {
                abort
        }
}
```

Add extra IP addresses using spaces to allow `remote_ip` to access from tailnet devices or remove `private_ranges` to deny access to LAN devices. Example: `remote_ip private_ranges 100.X.X.X 100.X.X.Y` to add 2 tailnet devices. Remove the entry completely to allow access from any device that can resolve the DNS and has access to the servers IP addresses and HTTP/HTTPS ports.

### TrueNAS SCALE docker settings

```
# Container Images
Image repository: teamlinux01/tailscale-caddy-dns
Image Tag: latest

# Container Environment Variables 
Environment Variable Name: CLOUDFLARE_AUTH_TOKEN
Environment Variable Value: *example*

Environment Variable Name: OVERRIDE_DEFAULT_ROUTE
Environment Variable Value: true

Environment Variable Name: GATEWAY_IP
Environment Variable Value: 10.0.0.1 # Use the router's IP on the LAN.

Environment Variable Name: LAN_NIC
Environment Variable Value: net1 # I am using my 2nd NIC on my server, it might be called net0 if you only have one NIC

Environment Variable Name: TRUENAS_SYSTEM
Environment Variable Value: true

Environment Variable Name: TRUENAS_SERVICE_NETWORK
Environment Variable Value: 172.17.0.0/16 # TrueNAS default service network setting

Environment Variable Name: TRUENAS_CLUSTER_GATEWAY_IP
Environment Variable Value: 172.16.0.1 # TrueNAS default cluster gateway setting

Environment Variable Name: TSD_TUN
Environment Variable Value: tailscale0

Environment Variable Name: TS_AUTH_KEY
Environment Variable Value: *tskey-auth-exampleCNTRL-random*

Environment Variable Name: TS_HOSTNAME
Environment Variable Value: jf # Use the name you would like the machine be called on the tailnet

# Networking
## Add external interface

Host Interface: enp5s0f1 # Use the interface for your server.
IPAM Type: Use Static IP
Static IP: 10.0.0.4/8 # Use whatever unused IP address/subnet on your network

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

> ⚠️ Warning
>
> Unbound DNS setting `Rebind protection networks` in OPNsense can cause issues if you are using public DNS entries for your tailnet machines.
>
> To remove the `100.64.0.0/10` network from the Unbound DNS `Rebind protection networks` settings go here: https://docs.opnsense.org/manual/unbound.html#advanced
