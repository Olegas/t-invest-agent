# invest-opencode

A self-contained [OpenCode](https://opencode.ai/v2/docs/) v2 server, packaged for the
T-Bank Invest workflow. It runs `opencode serve` in the foreground, exposes its HTTP
API and web UI on a port, and ships with:

- a **DeepSeek** provider pre-configured as the default model,
- the **T-Bank Invest** remote MCP server (`invest-public-api.tbank.ru/mcp`),
- the **Russian Trusted Root/Sub CA** needed to validate that endpoint's TLS chain.

The image is built on the official base image `ghcr.io/anomalyco/opencode:2.0.0`
(Alpine 3.24, opencode v2 baked in) plus a few packages this project needs.

---

## Requirements

- Docker with the Compose plugin (`docker compose`)
- A DeepSeek API key
- A T-Bank Invest MCP token
- A password to protect the server (see below)

---

## 1. Configure

Copy the example environment file and fill it in:

```sh
cp .env.example .env
```

| Variable            | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `DEEPSEEK_API_KEY`  | DeepSeek API key. Used for the default model.                           |
| `TINVEST_MCP_TOKEN` | Token for the T-Bank Invest MCP endpoint. Sent as `Bearer <token>`.     |
| `OPENCODE_PASSWORD` | Password for the OpenCode HTTP server. **Required.**                    |

Notes:

- `OPENCODE_PASSWORD` is required because opencode v2 authenticates every request.
  Without it the server generates a random password on each start (printed in the
  logs), so clients cannot connect reliably. Generate one with:

  ```sh
  openssl rand -hex 32
  ```

- `TINVEST_MCP_TOKEN` should be the **raw token only**. The `Authorization: Bearer ...`
  prefix is added by the configuration, so do not include `Bearer` yourself.

`.env` holds secrets. Never commit it.

## 2. Build and run

```sh
docker compose up -d --build
```

Check that it is up:

```sh
docker compose logs -f
```

You should see:

```
Starting opencode server on 0.0.0.0:4444 (project /root/work)
server listening on http://0.0.0.0:4444
```

## 3. Connect

The server listens on container port `4444`, published on host port `4444`.

- **Web UI / API:** <http://localhost:4444>
- **Authentication:** HTTP Basic
  - username: `opencode`
  - password: the value of `OPENCODE_PASSWORD`

Quick health check:

```sh
curl -u "opencode:$OPENCODE_PASSWORD" http://localhost:4444/api/health
# {"healthy":true,"version":"2.0.0",...}
```

### First-time: add the project

In opencode v2 the web UI keeps its **own** list of projects in the browser, keyed
by server URL. The server starts with `/root/work` as its default location, but the
UI does not add it automatically, so a fresh browser shows an empty Home screen.

Once per browser (per server URL), click **Add project** and choose `/root/work`.
The choice is remembered, so later restarts reopen it. If you switch between
`localhost`, a LAN IP, and a domain name, each is a separate URL with its own list —
pick one and stay consistent.

---

## Files

| File                 | Role                                                                              |
| -------------------- | --------------------------------------------------------------------------------- |
| `Dockerfile`         | Builds on `ghcr.io/anomalyco/opencode:2.0.0`, adds tools + the Russian CA.        |
| `entrypoint.sh`      | Ensures data dirs, pins the working directory to `/root/work`, starts the server. |
| `docker-compose.yml` | Service definition, port mapping, env, named volumes.                             |
| `opencode.json`      | Global opencode config: default model, provider, MCP server. Baked into image.    |
| `.env.example`       | Template for secrets.                                                             |
| `.dockerignore`      | Keeps `.git`, `.env`, and `*.md` out of the build context.                        |

## How it works

**Base image.** `ghcr.io/anomalyco/opencode:2.0.0` is Alpine-based and already
contains the opencode v2 binary, `ripgrep`, `wget`, and a CA bundle. It runs as
`root` with `HOME=/root`, and has no `bash`, `git`, or `curl`. The Dockerfile adds
`bash`, `ca-certificates` (for `update-ca-certificates`), `curl`, `git`, and `python3` (with `pip`).

**Server.** `entrypoint.sh` runs `opencode serve --hostname 0.0.0.0 --port 4444`.
opencode's foreground server uses its **working directory** as the default
project/location, so the entrypoint `cd`s to `/root/work` explicitly. (This differs
from `opencode service`, the background mode, which always uses `$HOME`.)

**Configuration.** `opencode.json` is copied to `/root/.config/opencode/opencode.json`
and merged as the global config. It sets:

- `model: deepseek/deepseek-chat` — default model,
- `providers.deepseek.settings.apiKey` — from `DEEPSEEK_API_KEY`,
- `mcp.servers.t-invest` — remote MCP at `invest-public-api.tbank.ru/mcp` with an
  `Authorization: Bearer {env:TINVEST_MCP_TOKEN}` header,
- `update: disable` — the server never self-updates.

**TLS.** The T-Bank Invest MCP endpoint is signed by the Russian Trusted Root/Sub CA,
which is not in the default Mozilla bundle. The Dockerfile installs both certs into
`/usr/local/share/ca-certificates` and runs `update-ca-certificates`, and points
`NODE_EXTRA_CA_CERTS` at the resulting bundle for the Bun-based runtime.

**Data and persistence.** Named volumes:

| Volume            | Mount                        | Contents                                         |
| ----------------- | ---------------------------- | ------------------------------------------------ |
| `opencode-share`  | `/root/.local/share/opencode`| Database, sessions, logs (`opencode.db`, `log/`).|
| `opencode-state`  | `/root/.local/state/opencode`| Service registration (`service.json`).           |
| `opencode-work`   | `/root/work`                 | The project files the agent works on.            |

The container runs as **root**, matching the upstream image. There is no non-root
user; do not expose the port to untrusted networks without additional protection
beyond the Basic auth password.

---

## Common operations

```sh
# Rebuild after editing the Dockerfile / opencode.json / entrypoint.sh
docker compose up -d --build

# Follow logs (the server prints its auth-relevant startup there)
docker compose logs -f

# Restart without rebuilding
docker compose restart

# Stop and remove the container (volumes are kept)
docker compose down

# Stop and WIPE all state, including sessions and the project files
docker compose down -v
```

Upgrade the base image: change the tag in the `FROM` line of the `Dockerfile`, then

```sh
docker compose up -d --build
```

Inspect the effective configuration inside the running container:

```sh
docker exec invest-opencode opencode debug config
docker exec invest-opencode opencode mcp list
```

---

## Troubleshooting

**Every request returns `401`.**
Authentication is on. Send Basic auth with username `opencode` and the
`OPENCODE_PASSWORD` value. If you changed `OPENCODE_PASSWORD`, recreate the
container so the new value is applied (`docker compose up -d`).

**`self signed certificate in certificate chain` when talking to the Invest API.**
The Russian CA is not being trusted. Verify inside the container:

```sh
docker exec invest-opencode curl -sS -o /dev/null -w '%{http_code}\n' \
  https://invest-public-api.tbank.ru/mcp
```

A `401` (or any HTTP status) means TLS is fine; a certificate error means the CA
install failed. Rebuild with `docker compose build --no-cache`.

**The web UI opens an empty window asking to create a project.**
Expected on a fresh browser. Click **Add project** and select `/root/work` (see
[First-time: add the project](#first-time-add-the-project)). The server itself
already reports `/root/work` as its default location — check with
`curl -u "opencode:$OPENCODE_PASSWORD" http://localhost:4444/api/location`.

**MCP tools are not visible / `/api/mcp` is empty.**
The MCP server is configured globally and connects when a session/project is loaded,
so the list can be empty on a freshly started server. Confirm the config is loaded
with `docker exec invest-opencode opencode debug config`; it should show the
`t-invest` server under `mcp.servers`.

**Port already in use.**
The host port is set in `docker-compose.yml` (`"4444:4444"`). Change `4444` to a free
port and run `docker compose up -d`.

---

## Security notes

- `.env` contains live secrets and is excluded from the image via `.dockerignore`.
  Keep file permissions tight (`chmod 600 .env`) and never commit it.
- The server is bound to `0.0.0.0` inside the container and protected only by the
  Basic auth password. For anything other than localhost, put it behind a reverse
  proxy with TLS, or restrict access at the network/firewall level.
- The default model (`deepseek/deepseek-chat`) and the full request content are sent
  to DeepSeek; the agent also calls the T-Bank Invest MCP with your token.
