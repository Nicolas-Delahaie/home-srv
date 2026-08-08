# SSH Configuration

SSH (Secure Shell) is a protocol for secure remote control of the server. Two access modes are available:

- Local network: direct connection via the local IP address
- External access: requires port forwarding on the internet router

While using a VPN is possible, SSH is preferred for its simplicity of setup. Exposing the service to the internet requires appropriate hardening.

## SSH Key Configuration

Two approaches are available for interactive (dev) access — choose one. Both register a public key on the server; the difference is where the private key lives. The automated Ollama tunnel does **not** use these keys: it relies on a local on-disk key locked down server-side (see [Securing the Tunnel Key](#securing-the-tunnel-key)).

### Bitwarden SSH Agent (recommended, cross-platform)

The key is generated and stored inside Bitwarden Desktop, which acts as the SSH agent. The private key never exists as a file on disk; access is protected by the master password / biometrics.

1. In Bitwarden Desktop, enable the SSH agent (Settings → Security → SSH Agent) and create a new SSH key. Follow the [official Bitwarden SSH Agent documentation](https://bitwarden.com/help/ssh-agent/) for the per-OS setup and the exact `IdentityAgent` path to add to `~/.ssh/config`.

   On macOS / Linux, `IdentityAgent` can be scoped to a single `Host` in `~/.ssh/config` so Bitwarden is only used for this server (not possible on Windows, where it applies globally). **Scope it per-host:** otherwise an unlocked Bitwarden session exposes _every_ key it holds to any `ssh` command run from that machine — including access to all your other registered SSH hosts.

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

2. **Optional (macOS only):** to avoid re-entering the passphrase on every connection, register it in the macOS Keychain.

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

To avoid specifying the user (and, for external access, the custom port) on every connection, add to `~/.ssh/config`:

```conf
Host <hostname> <hostname>.local
      User user_name

# External access: port forwarded on the router (see router-setup.md#port-forwarding)
Host <public-domain>
      User user_name
      Port <external_ssh_port>
```

The connection then becomes possible via:

```bash
ssh server.local
```

## SSH Port Forwarding

Once SSH is configured, forward a custom external port on the router to the server's internal port 22 (**not** 22 directly). Follow the procedure and see the reasoning [here](./router-setup.md#port-forwarding), and ensure firewall rules allow access to that port.

## Ollama Tunnel (Mac)

Exposes the Ollama instance running on a Mac (Apple Silicon) to the server's Open WebUI via a reverse SSH tunnel. The Mac's models appear in Open WebUI alongside the server's local models.

### Prerequisites

- A **local on-disk SSH key** must exist on the Mac (e.g. `~/.ssh/id_ed25519`). The tunnel must **not** use the Bitwarden agent key — see [Securing the Tunnel Key](#securing-the-tunnel-key) for why and how it is locked down
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

```conf
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
        <string>-o</string>
        <string>IdentityAgent=none</string> <!-- bypass Bitwarden agent, use the local key — see "Securing the Tunnel Key" -->
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

### Securing the Tunnel Key

The tunnel runs unattended via launchd, so its key can't go through Bitwarden — the agent would prompt for confirmation on every boot / reconnection. Rather than guarding _access_ to the key, we use the machine's local on-disk key and strip it, server-side, of every capability except the one port forward. `IdentityAgent=none` (set in the [plist above](#auto-start-at-login)) tells `ssh` to bypass the Bitwarden agent and fall back to that local key.

On the server, prefix this key in `~/.ssh/authorized_keys` so it can do nothing but open the forward it needs:

```text
command="echo 'tunnel only'",restrict,permitlisten="DOCKER_GATEWAY_IP:11434" ssh-ed25519 AAAA...key... user@mac
```

- `restrict`: disables everything by default (PTY, agent/X11 forwarding, all port forwarding).
- `command="echo 'tunnel only'"`: forces this fixed command, so the key can never run a shell or any other command. Without it, `restrict` still allows non-interactive execution (`ssh server 'any command'`) — i.e. the key could do almost anything. With `-N` the tunnel opens no command channel, so this never runs in normal use; it only fires if the key is misused.
- `permitlisten="DOCKER_GATEWAY_IP:11434"`: re-enables only the single remote forward (`-R`) the tunnel uses (replace with the real gateway IP, e.g. `172.50.0.1:11434`).

Even if the key leaks or the Mac session is left unlocked, it grants nothing but this one forward.

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

## Git Repository Access (GitHub PAT)

The server keeps this repository in sync with GitHub through a **fine-grained personal access token** (PAT).

### Scope: this repository only

The credential is a _fine-grained_ PAT (prefix `github_pat_`), **not** a classic token (`ghp_`). A classic token would grant access to every repository the account can reach; a fine-grained one is restricted to a single repo. Create it on GitHub — [Settings → Developer settings → Fine-grained tokens](https://github.com/settings/personal-access-tokens/new) — with:

- **Repository access** → _Only select repositories_ → `home-srv`
- **Permissions** → _Contents_ (read/write) — enough to pull and push
- **Permissions** → _Workflows_ (read/write) — required to push changes under `.github/workflows/`; without it GitHub rejects the push

Blast radius: if the server is compromised, an intruder who recovers the credential can touch **this repository and nothing else** — no other repo, no account-wide action, no organization access.
