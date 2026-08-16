# Compose Conventions — Adding a New Service

**This file documents only the choices specific to this repository** — the non-obvious conventions and the _why_ behind them. Generic Docker/Compose practices that any competent setup follows (declaring `depends_on`, adding a `healthcheck`, capping resources, mounting the timezone…) are intentionally left out: if it is logical and not specific to this stack, it does not belong here.

Each rule points to an existing service you can copy.

## Traefik & exposure

- **`traefik.enable: true`** is required — `exposedByDefault: false`.
- **No `rule`** — `defaultRule` already maps each service to `Host(<service>.${DOMAIN})` from its compose name. Add a `rule` only for a non-default hostname (`go2rtc` served by `frigate`).
- **No `certresolver`, no `tls`** — already applied globally on the `websecure` entrypoint.
- **Middlewares**: always `errp-redirect@file`. Add `authelia@file` only for a browser UI behind SSO. A programmatic API with its own token does not need it (ForwardAuth is browser-only).
- **`network_mode: host`** (`ha`, `glances`): route via `loadbalancer.server.url: http://${DOCKER_GATEWAY_IP}:<port>`, and omit `security_opt`.

## Ports — publish nothing by default

Traefik handles all ingress on 443. Publish a port only for a consumer outside Docker (`ha` reaching `frigate`) or a protocol Traefik cannot proxy (RTSP, WebRTC). **Bind sensitive/management ports to `127.0.0.1`** (Portainer, Frigate API, MQTT); a LAN-reachable port is acceptable only with the service's own auth (`8883`). Comment why each published port exists.

## Hardening

- **`security_opt: no-new-privileges:true`** by default (omit for host networking).
- **`restart`: never set it.** A crashed container must stay down so the problem is diagnosed, not looped. Boot recovery is handled by the `home-srv.service` systemd unit (README §7).
- **`privileged` / `cap_add` / `devices`**: only when strictly required, with an inline comment. Reference `devices` via stable `/dev/serial/by-id/...` paths, never `/dev/ttyUSBx` (`z2m`).

## Images

**Always pin an explicit version** — never `:latest` or a channel tag like `frigate:stable`.

## Environment & secrets

- **Short form** (`- VAR`) when the name is identical to `.env`; long form only for a transformed value or a renamed variable (`vw`).
- Split many variables between `env_file` (static) and `environment` (dynamic), as `vw` does.
- **`.env.template`**: document every new variable with a generation hint when relevant (`openssl rand`, `htpasswd`, `authelia crypto rand`). Sections: `Necessary edits` (required, no default), `Optionnal edits` (tunable, has a default), and optional-without-default (the service works without it).
- Never hardcode a secret in YAML.

## Config & data — Docker-first

- Prefer a versioned, bind-mounted config file (`./service/config/...:ro`) over manual UI/runtime setup, so the setup is reproducible from a fresh pull. If the image needs custom startup logic, add a bind-mounted entrypoint script (`:ro`), as `mosquitto` and `traefik` do — never an inline shell one-liner.
- **Anything that cannot be pre-configured in Docker must be documented in the README.** When a service needs a manual or runtime step that no compose field, env var, or config file can capture (UI-only settings, a one-shot init, an interactive wizard), the README is the single mandatory place to explain it — leave nothing implicit.
- When a tool generates its own state (config + secrets + data) in a single directory, do **not** version a hand-written config that fights its generator. Use a **named volume** and document the one-shot init command in the README (`hermes`: `hermes_data:/opt/data` → `docker compose run --rm hermes auth add nous --type oauth`). Where the tool supports it, override the generated config via `environment` rather than editing files inside the volume.
- **Volumes**: `:ro` when read-only; **named volume** for opaque runtime state, **bind mount** for files versioned in git or edited manually. Name named volumes `<service>_data`.

## CrowdSec

When the service produces logs reachable by CrowdSec (especially anything Traefik proxies to the internet), wire a collection/parser in `cs/`.

## Renovate

Renovate links the upstream repo and changelog by reading the `org.opencontainers.image.source`
OCI label on the image's `latest` tag. When adding a service, check the label is present
(`docker buildx imagetools inspect <image> --raw | jq '.config.Labels'` or the registry's own UI).
If it is missing, add a `packageRule` to `renovate.json` with an explicit `sourceUrl` and a
`description` explaining why (see the existing `portainer`/`frigate`/`hermes-agent`/
`docker-github-actions-runner` entries).
