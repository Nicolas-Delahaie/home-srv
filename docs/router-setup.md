# Internet Box and DNS Configuration

This configuration applies to the Freebox but can be adapted to other internet routers.

## Static IP Configuration

A static IP address is required to route the server over the internet. This ensures the stability of the public IP address, which is essential for port forwarding and DNS configuration.

1. Obtain a static IP:
   - Log in at <https://adsl.free.fr>
   - Go to "Ma Freebox"
   - Select "Demander une adresse IP fixe V4 "full-stack""

2. Retrieve the public IP:
   - Check "État de la Freebox"
   - Note the public IPv4 address

## Port Forwarding

On the router's intranet (<http://mafreebox.freebox.fr> for Free), configure port forwarding for the following ports to the server's local IP:

- A custom high external port (e.g. `2XXXX`) → **22** (SSH)
- 80 (HTTP)
- 443 (HTTPS)

This allows external access to the server via SSH or a web browser.

> **Why not forward port 22 directly**: automated bots scan port 22 across the whole internet non-stop, and this generates the vast majority of CrowdSec alerts on the server (noise, not real threats). The SSH daemon itself keeps listening on port 22 (unchanged, including for local access) — only the router's external-facing port is different. Forwarding an arbitrary external port to internal port 22 removes the server from most of that mass scanning. This does not replace SSH hardening ([Server Hardening](./remote-access.md#server-hardening)), it only cuts the noise.

> It is recommended to create a static DHCP lease for the server to ensure its local IP does not change and forwarding works correctly. The lease must be created from the router's interface. To renew the lease after setting it as static on the router side, run `sudo dhclient <network_interface>`.

## DNS Configuration

1. OVH configuration:
   - Point the domain to the router's public IP
   - Add a wildcard record to redirect subdomains: `*.<domain> A <public_ip>`

## Local Domain Name

To resolve the domain name directly to the server's local IP without going through the internet, configure the domain name on the router.

On the Freebox: Router Settings > "Domain name" > Add a domain.

## Debugging

### Bypass DNS Cache

To check DNS propagation: use <www.whatsmydns.net>. This tool shows the real-time destination of an IP, without the DNS cache latency.

To speed up propagation (bypass the router's DNS cache):

- In "Router Settings > DHCP > DNS"
- Add at the top of the list:
  1. 8.8.8.8 (Google)
  2. 1.1.1.1 (Cloudflare)

> The domain name will then be resolved directly via Google, bypassing the router's caching system which is not well suited for development.
