# Private Network Configuration

This configuration enables connecting to the server via a simple Ethernet cable, without depending on the internet router. Ideal for debugging in local mode.

## Internet Sharing

This method shares the host machine's internet connection with the server. Note: this solution does not provide true isolation in an exclusive local network.

Configuration on the host machine (macOS):

1. Go to Settings > Internet Sharing
2. Select the source: internet connection to share (e.g. Wi-Fi)
3. Set the destination: Ethernet port in use

## APIPA Protocol

Without a DHCP server, the APIPA (Automatic Private IP Addressing) protocol enables automatic connection. This protocol automatically assigns an IP address when no DHCP server is available.

Configuration on the server:

1. Run `sudo nmtui`
2. Select "Edit a connection"
3. Choose the Ethernet interface
4. Set IPv4 to "Link-Local" (APIPA)

Configuration on the host machine (usually already active by default):

1. Go to Settings > Network
2. Select the Ethernet interface
3. Under Details > TCP/IP
4. Set IPv4 to "via DHCP" (to trigger APIPA when no DHCP server is present)

Once the Ethernet cable is connected, the devices automatically assign themselves an IP address in the 169.254.x.x range and establish the connection.

## DHCP Server on Host (dnsmasq)

Gives full control over the DHCP range and gateway, unlike Internet Sharing. The host becomes an isolated DHCP server.

1. **Install dnsmasq on the host machine (macOS)**

   ```bash
   brew install dnsmasq
   ```

2. **Configure dnsmasq** in `/opt/homebrew/etc/dnsmasq.conf`:

   ```ini
   # Sole DHCP server on the network
   dhcp-authoritative
   # Interface, range, netmask, lease duration (adapt to your setup)
   dhcp-range=192.168.10.50,192.168.10.150,255.255.255.0,24h
   # Default gateway = host machine's static IP
   dhcp-option=3,192.168.10.1
   # Limit DNS responses to local networks
   local-service
   ```

   > The starting IP must be higher than the host's static IP.
   > To limit to a specific interface: `dhcp-option=en11,3,192.168.10.1`

3. **Set a static IP on the host's Ethernet interface**

   Settings > Network > Ethernet > TCP/IP:
   - Configure IPv4: Manually
   - IP Address: `192.168.10.1`
   - Subnet mask: `255.255.255.0`

4. **Configure the server as a DHCP client**

   ```bash
   sudo nmtui
   # Edit connection > Ethernet > IPv4: Automatic (DHCP)
   ```

5. **Start dnsmasq**

   ```bash
   sudo brew services restart dnsmasq
   ```

6. Connect the Ethernet cable — the server will receive an IP automatically.

### DNS: resolve local subdomains on the host

To access `*.localhost` services locally (same conditions as production):

Add to `/opt/homebrew/etc/dnsmasq.conf`:

```ini
address=/.localhost/127.0.0.1
```

Then create a resolver:

```bash
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/localhost
```

### Debugging

```bash
# Real-time DNS/DHCP log
tail -f /opt/homebrew/var/log/dnsmasq.log

# Check port 53
sudo lsof -i UDP:53 -i TCP:53

# DNS queries
dig @127.0.0.1 <domain> +short

# Flush DNS cache (macOS)
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```
