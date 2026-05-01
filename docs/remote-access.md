# SSH Configuration

SSH (Secure Shell) is a protocol for secure remote control of the server. Two access modes are available:

- Local network: direct connection via the local IP address
- External access: requires port forwarding on the internet router

While using a VPN is possible, SSH is preferred for its simplicity of setup. Exposing the service to the internet requires appropriate hardening.

## SSH Key Configuration

Two approaches are available — choose one.

### Bitwarden SSH Agent (recommended, cross-platform)

The key is generated and stored inside Bitwarden Desktop, which acts as the SSH agent. The private key never exists as a file on disk; access is protected by the master password / biometrics.

1. In Bitwarden Desktop, enable the SSH agent (Settings → Security → SSH Agent) and create a new SSH key. Follow the [official Bitwarden SSH Agent documentation](https://bitwarden.com/help/ssh-agent/) for the per-OS setup and the exact `IdentityAgent` path to add to `~/.ssh/config`.

   On macOS / Linux, `IdentityAgent` can be scoped to a single `Host` in `~/.ssh/config` so Bitwarden is only used for this server (not possible on Windows, where it applies globally).

2. Once the agent is configured and unlocked, copy the key to the server:

   ```bash
   ssh-copy-id user_name@server
   ```

### Local key

The key lives on disk. Always protect it with a passphrase — without one, the private key is stored in plaintext, and a stolen machine means direct server access.

1. Generate the key:

   ```bash
   ssh-keygen
   ```

2. Copy it to the server:

   ```bash
   ssh-copy-id user_name@server
   ```

3. **Optional (macOS only):** to avoid re-entering the passphrase on every connection, register it in the macOS Keychain.

   Add to `~/.ssh/config`:

   ```conf
   Host *
         AddKeysToAgent yes
         UseKeychain yes
   ```

   Then:

   ```bash
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

   The passphrase is automatically unlocked with the macOS session (TouchID / session password). Locked session = key inaccessible.

## Server Hardening

1. Edit the SSH configuration:

   ```bash
   sudo nano /etc/ssh/sshd_config.d/custom-config.conf
   ```

2. Add security parameters:

   ```conf
   LoginGraceTime 1m
   PermitRootLogin no
   MaxAuthTries 3
   PubkeyAuthentication yes
   X11Forwarding no
   AllowUsers your_user

   # Once SSH key is tested, add:
   PasswordAuthentication no
   ChallengeResponseAuthentication no
   ```

3. Restart the SSH service:

   ```bash
   sudo systemctl restart sshd
   ```

4. Test the key-based connection with `ssh user_name@server.local`.
5. After validating the connection, uncomment the last two lines and restart SSH.

## Simplified Connection

To avoid specifying the user on every connection, add to `~/.ssh/config`:

```conf
Host <hostname> <hostname>.local <public-domain> 64.64.31.31
      User user_name
```

The connection then becomes possible via:

```bash
ssh server.local
```

## Port 22 Forwarding

Once SSH is configured, port 22 must be forwarded on the router. Follow the procedure [here](./router-setup.md#port-forwarding) and ensure firewall rules allow access to port 22.

## Ollama Tunnel (Mac)

Exposes the Ollama instance running on a Mac (Apple Silicon) to the server's Open WebUI via a reverse SSH tunnel. The Mac's models appear in Open WebUI alongside the server's local models.

### Prerequisites

- The Mac must have SSH access to the server
- Ollama must be running on the Mac (port 11434)
- The **"Expose Ollama to the network"** option must be enabled in Ollama's settings. Without this option, Ollama rejects requests coming through the tunnel with a 403 error.

> **⚠️ Security warning**: enabling network access makes Ollama listen on **all network interfaces** of the Mac, including public Wi-Fi networks. Anyone on the same network can then access the Ollama API and:
>
> - use the Mac's CPU/GPU for their own prompts (compute theft)
> - list, delete, or inject models
>
> However, **Open WebUI conversations are not exposed**: Ollama is stateless, history is stored on the Open WebUI side on the Shuttle.
>
> **Why not better?** Ollama hardcodes accepted hosts (`localhost`, `127.0.0.1`) in its anti-DNS-rebinding check on the HTTP `Host` header, and does not provide an environment variable to extend this list. `OLLAMA_ORIGINS` only controls CORS (browser `Origin` header), not this check. Clean alternatives (pf firewall, local mini proxy rewriting the `Host`) were ruled out due to their implementation and maintenance complexity.

### SSH Server Configuration

Add to the sshd config (e.g. `/etc/ssh/sshd_config`):

```
GatewayPorts clientspecified
ClientAliveInterval 30
ClientAliveCountMax 3
```

- `GatewayPorts clientspecified`: allows the tunnel to bind on the Docker gateway IP (`DOCKER_GATEWAY_IP`), required for containers to access the tunnel
- `ClientAliveInterval/CountMax`: detects dead SSH clients in ~90s and releases the tunnel port. Without this, a sudden Mac disconnection (Wi-Fi drop, sleep) leaves a zombie session that blocks the port

Then restart sshd: `sudo systemctl restart sshd`

### Auto-start at Login

Create `~/Library/LaunchAgents/com.ollama-tunnel.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-o</string>
        <string>ServerAliveInterval=30</string>
        <string>-o</string>
        <string>ServerAliveCountMax=3</string>
        <string>-R</string>
        <string>DOCKER_GATEWAY_IP:11434:localhost:11434</string>
        <string>DOMAIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ollama-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama-tunnel.log</string>
</dict>
</plist>
```

- `-N`: no remote shell, tunnel only
- `ServerAliveInterval/CountMax`: detects a dead connection in ~90s on the client side
- The tunnel binds on the Docker gateway IP to be accessible from containers
- `RunAtLoad` / `KeepAlive`: starts the tunnel at login and automatically restarts it if it dies — the native `ssh` binary is sufficient, no need for `autossh`

Replace `DOCKER_GATEWAY_IP` and `DOMAIN` with values from `.env`, then load the plist:

```bash
launchctl load ~/Library/LaunchAgents/com.ollama-tunnel.plist
```

`RunAtLoad: true` starts the tunnel immediately and `KeepAlive: true` restarts it automatically if it dies. The native `ssh` binary is sufficient: resilience is handled by launchd, no need for `autossh`.

### Updating or Disabling the Tunnel

`KeepAlive: true` makes `launchctl stop` ineffective: the process is immediately restarted. To modify the plist or disable the tunnel, use `unload`/`load`:

```bash
# Disable
launchctl unload ~/Library/LaunchAgents/com.ollama-tunnel.plist

# Reload after modification
launchctl load ~/Library/LaunchAgents/com.ollama-tunnel.plist
```

### Verification

On the Mac: `launchctl list | grep ollama` should show a PID (1st column).

On the server: `ss -tlnp | grep 11434` should show the port listening.

From the Open WebUI interface, go to **Admin Panel → Settings → Connections**: both endpoints (`localhost:11434` and `${DOCKER_GATEWAY_IP}:11434`) should appear with a green status.
