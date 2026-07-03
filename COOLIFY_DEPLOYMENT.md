# Deploying to Coolify

This document covers deploying this repository to [Coolify](https://coolify.io/)
specifically, including a few non-obvious gotchas discovered while setting up
this project. For general ChirpStack/Docker Compose usage, see [README.md](README.md).

## Initial setup

1. **Install Coolify** on a fresh server (Ubuntu 22.04/24.04 recommended):
   ```bash
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
   ```
   Access `http://<server-ip>:8000` to create the admin account.

2. **Connect the GitHub repo** as a source (Dashboard → Sources). Public
   repos need no further auth; private repos need a GitHub App or Deploy Key.

3. **New Resource → Public Repository** (or Private, depending on repo
   visibility) → point at this repo, branch `main`.

4. **Build Pack**: set to **Docker Compose**.

5. **Base Directory**: `/`
   **Docker Compose Location**: `/docker-compose.yml`

6. **Enable "Preserve Repository During Deployment"** (Configuration →
   General). **This is critical** — see [Gotcha #1](#gotcha-1-preserve-repository-during-deployment) below.

7. Click **Deploy**.

## Gotchas discovered during setup

### Gotcha #1: "Preserve Repository During Deployment"

By default Coolify does **not** keep the git-checked-out files around for
plain bind-mounted directories (e.g. `./configuration/chirpstack:/etc/chirpstack`).
Only files defined via the `content:` bind-mount syntax (see mosquitto/postgres
below) get written reliably. Without "Preserve Repository During Deployment"
enabled, directories like `configuration/chirpstack/` and
`configuration/chirpstack-gateway-bridge/` end up **empty** on the host, so
the containers start with missing config and ChirpStack silently falls back
to default config values (e.g. connecting to `localhost` instead of `postgres`),
causing a permanent crash-restart loop that looks like a Postgres connectivity
issue but isn't.

**Fix:** enable the toggle in Configuration → General → Preserve Repository
During Deployment.

### Gotcha #2: `content:` bind mounts don't do Compose variable interpolation

For files that must exist reliably even without Gotcha #1's fix (e.g.
`mosquitto.conf`, `001-chirpstack_extensions.sh`), this repo uses Coolify's
`content:` extension to `type: bind` volumes:

```yaml
volumes:
  - type: bind
    source: ./configuration/mosquitto/config/mosquitto.conf
    target: /mosquitto/config/mosquitto.conf
    content: |
      listener 1883
      allow_anonymous true
```

Coolify writes the `content:` block **verbatim** to the file — it does not
collapse `$$` to `$` the way `docker compose` normally does when interpolating
compose files. If you need a literal `$` in a script (e.g. `$POSTGRES_USER`),
write a single `$`, not `$$` — otherwise bash interprets `$$` as its own PID
special variable, producing garbage like `52POSTGRES_USER`.

### Gotcha #3: Postgres role privileges

Don't create a custom Postgres role via an init script with
`GRANT ALL PRIVILEGES ON DATABASE ... TO ...` — since Postgres 15, that grant
does **not** include `CREATE` on the `public` schema (revoked from `PUBLIC` by
default), which can break ChirpStack's schema migrations. Instead, set
`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` directly on the `postgres`
service — the official Postgres image bootstraps that user as full owner of
the database automatically. This matches the DSN in
`configuration/chirpstack/chirpstack.toml`.

### Gotcha #4: Port 8080 is taken by Traefik

Coolify's Traefik proxy (`coolify-proxy`) binds host port 8080 for itself, so
you cannot reach ChirpStack at `http://<server-ip>:8080`. ChirpStack must be
reached through the Coolify-generated domain (see below) which Traefik routes
internally.

### Gotcha #5: Traefik needs an explicit `expose`

Even with `SERVICE_FQDN_CHIRPSTACK_8080` set as an environment variable
(Coolify's magic var for auto-generating a domain + router), Traefik's Docker
provider needs to know which container port to load-balance to. Without an
explicit `expose`, Traefik logs `error: port is missing` and returns 404 for
any request. Fix:

```yaml
chirpstack:
  expose:
    - "8080"
```

## Post-deploy checklist

```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -i -E "postgres|chirpstack|mosquitto|redis"
```
All should be `Up`, none `Restarting`/`Exited`.

```bash
docker logs coolify-proxy --since 2m | grep -i "port is missing"
```
Should be empty.

## Adding a custom domain

By default Coolify assigns a free `*.sslip.io` wildcard domain (resolves to
your server IP automatically, no DNS setup needed, but no real SSL). To use
your own domain:

1. **Point DNS at the server**: create an `A` record for your domain (or
   subdomain, e.g. `chirpstack.example.com`) pointing to the server's IP.
2. In Coolify → resource → **Configuration → Domains for chirpstack**,
   replace the auto-generated `sslip.io` URL with your domain, prefixed with
   `https://` (e.g. `https://chirpstack.example.com`) so Coolify knows to
   provision SSL.
3. **Save**, then **Redeploy**.
4. Coolify automatically requests a **Let's Encrypt** certificate for the
   domain. This requires:
   - Ports 80/443 reachable from the internet on this server.
   - DNS already propagated (can take minutes to hours depending on TTL).
5. Verify with `docker logs coolify-proxy --tail 50 | grep -i acme` if the
   certificate isn't issuing.

Do the same for `chirpstack-gateway-bridge` and `mosquitto` domains if you
want them reachable externally over HTTPS (not required for MQTT/UDP traffic,
which uses raw TCP/UDP ports `1883`/`1700` directly).
