# Services and configurations for the home server

Setup guide for a home server and various configurations. Although based on a Shuttle (compact computer) running Debian, this setup can be adapted to any type of server.

## Installation

1. Configure environment variables
   1. Generate the blank file:

      ```bash
      cp .env.template .env
      ```

   2. Fill in the generated file with the required environment variables.

2. Run the following command:

   ```bash
   docker compose up -d --build
   ```

   > This command starts the minimum set of containers required for the project to run.

3. CrowdSec:
   1. IP blocking at host level (CrowdSec Firewall Bouncer):
      1. Installation:

         ```bash
         sudo apt install --no-install-recommends crowdsec-firewall-bouncer ipset
         sudo systemctl enable --now crowdsec-firewall-bouncer # As a precaution
         ```

      2. Initialize the CrowdSec service API key:

         ```bash
         docker compose exec cs cscli bouncers add firewall
         ```

         This command generates an API key. Then create (or update) the firewall bouncer `.local` config file `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local` with the following content:

         ```yaml
         mode: iptables
         api_key: <key generated above>
         iptables_chains:
           - INPUT
           - DOCKER-USER
         prometheus:
           enabled: false
         ```

         > The `iptables` mode is required for Docker environments: this is the [official CrowdSec recommendation](https://docs.crowdsec.net/u/bouncers/firewall). It allows adding the `DOCKER-USER` chain, without which incoming traffic to containers (port forwarding) is not blocked despite ban decisions. The `nftables` mode (default) does not support `DOCKER-USER`.

      3. (Optional) Prevent the service from crashing when the CrowdSec API is not yet available:

         ```bash
         sudo systemctl edit crowdsec-firewall-bouncer.service
         ```

         Add the following lines:

         ```ini
         [Service]
         Restart=always
         RestartSec=60
         ```

         > At startup, the service will attempt to restart every minute until the API is available (CrowdSec Docker container started).

   2. (Optional) Configure the remote monitoring interface (Console):

      > The CrowdSec Console allows you to visualize alerts and the health of the CrowdSec instance via an external web interface.
      1. Authenticate at <https://docs.crowdsec.net/u/getting_started/post_installation/console>
      2. Follow the procedure (pair the instance then restart)

4. Authelia:
   1. Create the file containing Authelia users (including the administrator):

      ```bash
      cat > ./authelia/config/users_database.yml << 'EOF'
      users:
         admin:
            password: ""
            displayname: "Admin"
      EOF
      ```

   2. Generate the hash for the desired administrator password and copy it into `user.admin.password`:

      ```bash
      docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2
      ```

5. Ollama (Open WebUI):

   On first launch, no models are installed. At least one must be downloaded to start chatting:

   ```bash
   docker compose exec ollama ollama pull mistral
   ```

   Available models are listed on [ollama.com/library](https://ollama.com/library). Some examples:

   | Model         | Size    | Description                                  |
   | ------------- | ------- | -------------------------------------------- |
   | `mistral`     | ~4 GB   | Good performance / size balance              |
   | `llama3.2`    | ~2 GB   | Lighter, suitable for modest hardware        |
   | `llama3.2:1b` | ~1.3 GB | Very lightweight                             |

   > Models are persisted in the `ollama_datas` Docker volume. They survive container restarts and updates.

   **Using an external Ollama server (optional)**:

   The embedded server (Shuttle) has limited processing power. If a more powerful device is available on the local network (e.g. a powerful laptop with Ollama installed), Open WebUI can connect to it to run more demanding models.

   Prerequisites on the remote machine:
   1. Install Ollama ([ollama.com](https://ollama.com))
   2. Enable external access on Ollama. The simplest way is via the Ollama interface: **Settings** > **Networking** > enable **Allow external connections**. Alternatively, set the environment variable `OLLAMA_HOST=0.0.0.0` before launching Ollama.
   3. Create a **static DHCP lease** on the router for this machine so its local IP does not change (mDNS does not work with Open WebUI, a fixed IP is required)

   Configuration in Open WebUI:
   1. Log into Open WebUI
   2. Go to **Admin Panel** > **Settings** > **Connections**
   3. In the **Ollama** section, add a new connection with the URL `http://<LAPTOP_FIXED_IP>:11434`
   4. Verify the connection: models installed on the remote machine should appear in the list of available models

   > When the laptop is connected and reachable on the local network, Open WebUI can access it and run much more powerful models than the server allows. When the machine is off or absent from the network, only the server's local models remain available.

6. Hermes (AI agent dashboard):

   The agent configuration is versioned (`hermes/config.yaml`, mounted read-only), but the Nous Portal credentials live in the `hermes_data` volume and must be initialized once:

   ```bash
   docker compose run --rm hermes auth add nous --type oauth
   ```

   Follow the printed OAuth flow to log in with your Nous account. The dashboard is then available at `https://hermes.<DOMAIN>`, behind Authelia (SSO) plus Hermes' own basic auth (credentials from `.env`).

7. (Optional) To enable automatic service startup when the server boots, create this `systemctl` auto-start service:

   ```bash
   sudo cp home-srv.service /etc/systemd/system/
   sudo sed -i "s|<REPO_PATH>|$(pwd)|" /etc/systemd/system/home-srv.service
   sudo systemctl enable home-srv
   ```

   > With this service, containers will start automatically when the server boots — particularly useful after a power outage. `restart=unless-stopped` has been disabled to facilitate crash diagnosis and avoid restart loops.

8. (Optional) Cloud streaming on detection (YouTube Live):
   1. In YouTube Studio, create a new live stream (the "Go Live" tab), copy the generated stream key and set the stream to **Private**
   2. Copy the key into `.env`: `YOUTUBE_STREAM_KEY=xxxx-xxxx-xxxx`
   3. `docker compose restart ha`

   > YouTube may display a warning "bitrate below recommended" — this is normal on static scenes (H264 compresses very efficiently). The bitrate rises automatically when there is movement.

## Firewall and Network

The server **must not have an active firewall** (ufw, iptables) at the host level — this risks blocking internal services. Internet filtering is handled **at the router level**: only ports 80 and 443 are forwarded to the server.

Ports not forwarded by the router remain accessible on the LAN, but are not insecure: all services go through Traefik + Authelia or have their own authentication. Services without auth are bound to `127.0.0.1` only.

**CrowdSec** complements the setup by blocking malicious IPs via the firewall bouncer.

## Server Configuration

For server configuration, follow the documentation [here](./docs/server-setup.md).
