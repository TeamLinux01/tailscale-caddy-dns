# This container connects to tailscale and runs a caddy web server. This is useful if you want to put a website on a LAN and a tailnet at the same time or reverse proxy web services in and out of a tailnet. When setting an IP address for a public DNS entry, use the machine's tailscale IP addresses.

> ⚠️ Warning
>
> When using DuckDNS, the DNS challenge requires that the server be publicly accessible, so it cannot be used on a tailnet. I will leave in the plug-in as a way of hosting di

This container is built with extra dns plugins. These included:

* Azure
* Cloudflare
* DuckDNS
* Namecheap

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

https://login.tailscale.com/admin/settings/keys Generate an auth key. I like to make it re-usable and add a tag, so the container machines don't expire and can be added easily.

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
  -e=CADDY_INGRESS_NETWORKS=proxy_network \
  -device=/dev/net/tun:/dev/net/tun \
  -volume=/var/run/docker.sock:/var/run/docker.sock \
  --volume=proxy_data:/data \
  --volume=proxy_config:/config \
  teamlinux01/tailscale-caddy-dns
```

The `set -a` command block will load the environmental variables onto the host and pass them into the container. If you don't want to set them via a file, just replace the `${}` text with the keys.

This will create a container that will join the tailnat with the name of `proxy` and have direct access to other containers that are part of the `proxy-network` docker network. The container will run in the background and be removed when `docker stop proxy` is run. The volumes will stay intact, so a new container can be started and it will keep the same tailscale auth/caddy TLS data.

### An example docker compose file (internal docker network):

`compose.yml`:

```
networks:
  proxy-network:
    name: proxy-network

services:
  proxy:
    image: teamlinux01/tailscale-caddy-dns:auto-proxy
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

      # Optional: TUN device name, or "userspace-networking" as a magic value to not use kernel support and do everything in-process. You can use "tailscale0" if the container has direct access to hardware. "userspace-networking" value is included in the image.
      - TSD_TUN=userspace-networking
      # Optional: UDP port to listen on for peer-to-peer traffic; 0 means to auto-select. Port 41641 is the default that tailscaled will try to use. "0" value is included in the image.
      - TSD_PORT=0
      # Optional: Extra arguments for tailscaled.
      - TSD_EXTRA_ARGS=

      # Optional: Enable tailscaled and tailscale service. "true" value is included in the image.
      - TS_ENABLE=true
      # Optional: Host name used on the tailnet. It will automatically be pulled from system if not provided.
      - TS_HOSTNAME=proxy
      # Only is needed if TS_ENABLE is set to "true". The Tailscale Auth key that is generated at https://login.tailscale.com/admin/settings/keys
      - TS_AUTH_KEY=${TS_AUTH_KEY}
      # Optional: Extra arguments for tailscale. Used for OAuth authentication.
      - TS_EXTRA_ARGS=

      # Watches the docker network "proxy_network" for labels.
      - CADDY_INGRESS_NETWORKS=proxy_network
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
      - proxy_data:/data
      - proxy_config:/config
      - /dev/net/tun:/dev/net/tun
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

volumes:
  proxy_data:
  proxy_config:
```

Run `docker-compose up`. This will create a container that will join the tailnat with the name of `proxy` and have direct access to other containers that are part of the `proxy-network` docker network.

# Extra things to consider

> ⚠️ Warning
>
> Unbound DNS setting `Rebind protection networks` in OPNsense can cause issues if you are using public DNS entries for your tailnet machines.
>
> To remove the `100.64.0.0/10` network from the Unbound DNS `Rebind protection networks` settings go here: https://docs.opnsense.org/manual/unbound.html#advanced
