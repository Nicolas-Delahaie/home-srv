# WireGuard VPN — AdGuard DNS

The home LAN uses AdGuard as DNS via DHCP. **The VPN does NOT** — the Freebox WireGuard
server hardcodes Free's public DNS (`212.27.38.253`) in every generated `.conf`, with no
per-peer DNS option in the admin UI.

Without manual editing, a VPN client has **no ad blocking** and `*.${DOMAIN}` is **not**
resolved locally.

## Setup per client

1. Download the `.conf` from Freebox OS → VPN Server → WireGuard
2. In the `[Interface]` section, replace the DNS line:
   ```ini
   DNS = SERVER_IP
   ```
   (default was `212.27.38.253`)
3. Import the modified `.conf` in the WireGuard app
4. In the WireGuard app tunnel settings, enable **"On-Demand"** so the tunnel auto-activates
   on mobile data / external Wi-Fi
5. **⚠ Critical** — make sure **"Exclude Private IPs"** is **DISABLED** (see debug below)

Strict mode: only `SERVER_IP`, no secondary like `1.1.1.1`. Windows queries secondary DNS in
parallel, which would leak local-domain queries. If AdGuard is down, edit the `DNS` line
manually to a public resolver.

## Debug: "the certificate is invalid" via VPN

If services accessed via VPN show a wrong cert (often an Orange/Bouygues/whatever Livebox
admin cert), it means the connection to `192.168.1.1` is hitting the **local network's
gateway** instead of going through the tunnel to the home Shuttle.

**Root cause** : WireGuard mobile apps (iOS, Android, macOS) have an **"Exclude Private IPs"**
toggle which, when ON, removes `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` from
`AllowedIPs`. Result: traffic to home subnet `192.168.1.0/24` goes **locally** (where
`192.168.1.1` is some other device, usually an ISP box) instead of through the tunnel.

**Fix per device** :

- **iOS** : WireGuard app → tunnel → Edit → toggle **Exclude Private IPs** OFF
- **macOS** : WireGuard app → Edit Tunnel → ensure `AllowedIPs = 0.0.0.0/0, ::/0` (no exclusion)
- **Android** : WireGuard app → Edit → toggle **Exclude Private IPs** OFF

After change, **reconnect the tunnel**.

**Verification** — from the client with VPN active :

```bash
# Where does traffic to 192.168.1.1 go ?
# macOS / Linux:
route get 192.168.1.1     # interface should be utun*/wg* (tunnel), NOT en0/wlan0

ping -c 3 192.168.1.1
# Latency ~30ms+ via tunnel = correct
# Latency ~1ms = still going through local network, fix not applied

# DNS resolves via tunnel ?
dig adguard.${DOMAIN}       # should return 192.168.1.1 (the AdGuard rewrite)
```

## Testing the full path

```bash
dig ha.${DOMAIN}              # → SERVER_IP (rewrite)
dig doubleclick.net           # → 0.0.0.0 (AdGuard blocking)
dig google.com                # → real IP
curl -I https://adguard.${DOMAIN}    # valid cert from Let's Encrypt
```

## Failure modes

| Scenario | Symptom | Fix |
|---|---|---|
| `Exclude Private IPs` on | Wrong cert (local box's cert), `ERR_CERT_INVALID` | Disable the toggle, reconnect |
| AdGuard down | No DNS resolution on VPN | Edit `.conf` to a public DNS temporarily |
| Freebox WireGuard down | Tunnel won't connect | Reboot Freebox, check WireGuard status in Freebox OS |
| Subnet collision (rare) | Local 192.168.1.0/24 conflicts with home even with full tunnel | Migrate home to less common subnet (10.50.0.0/24, 172.20.0.0/24) |

## Future-proofing

If the VPN ever migrates from Freebox to a self-hosted container (e.g. `linuxserver/wireguard`),
the DNS can be configured server-side and these manual per-client steps disappear.
