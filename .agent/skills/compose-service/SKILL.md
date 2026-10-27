---
name: compose-service
description: Standard operating procedure for adding or updating services in Docker Compose ensuring port isolation, storage persistence, healthchecks, and resource limits.
---

# Procedure: Add or Update Service in Docker Compose

> 💡 **Objective:** Add or modify services in `compose.yaml` (or `docker-compose.yml`) idempotently and safely, avoiding port collisions and data loss risks.

---

## Prerequisites and Mandatory Invariants

1. **Prior Topology Review:** The agent MUST read [.agent/SERVICES.md](../../SERVICES.md) before modifying configuration.
2. **Pinned Images:** Tag `:latest` is forbidden. Always use stable semantic tags (e.g. `v1.2.3`, `1.23-alpine`) or SHA digests.
3. **Mandatory Healthcheck & Endpoint Convention:** Every container MUST define an explicit `healthcheck` block. HTTP-based services MUST expose dedicated `/health` or `/healthz` endpoints.
4. **Probe Log Discarding:** Web servers, reverse proxies, and applications MUST discard or suppress access logs for successful (2xx) `/health` and `/healthz` probes to prevent disk churn and VictoriaLogs telemetry pollution (see [.agent/knowledge/k-002-healthcheck-logging-contract.md](../../knowledge/k-002-healthcheck-logging-contract.md)).
5. **Resource Limits:** Every container must define CPU and memory limits (`cpus` and `memory`).
6. **Zero Plaintext Secrets:** Passwords and tokens must be injected via environment variables (`${VAR_NAME}`).

---

## Step-by-Step Procedure

### Stage 1: Port Availability Verification
1. Check the "Host Port Allocations" table in [.agent/SERVICES.md](../../SERVICES.md).
2. If exposing ports on the host, ensure the selected port is not already allocated.
3. On the local host (if shell commands are authorized), verify that the port is not bound by an external process:
   ```bash
   ss -tuln | grep ":<PORT>" || echo "Port available"
   ```

### Stage 2: Network Segregation & Storage Persistence
1. Determine network boundaries:
   - User-facing services connect to the reverse-proxy network (e.g. `proxy_public`).
   - Backend services (databases, queues, storage) reside exclusively on isolated networks (e.g. `db_isolated`).
2. Configure volumes:
   - For databases and high-write state, use **Named Volumes** declared in the root `volumes:` block of `compose.yaml`.
   - For static configuration files, use **Bind Mounts** with read-only `:ro` flags.

### Stage 3: Author Service Block in `compose.yaml`
Author the service block following canonical syntax:

```yaml
  service-name:
    image: vendor/image:v1.0.0
    container_name: service-name
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - proxy_public
      - monitoring_internal
    ports:
      - "${SERVICE_PORT:-8080}:8080"
    environment:
      - TZ=${TZ:-UTC}
      - APP_SECRET=${APP_SECRET}
    volumes:
      - service_data:/path/in/container
      - ./config/service.conf:/etc/service/service.conf:ro
    # INVARIANT: Probe /health or /healthz on loopback; probe access logs must be suppressed
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
```

### Stage 4: Update Environment Variables
1. Add new variables to `.env.example` with safe placeholder values.
2. Never commit production credentials to `.env.example`.

### Stage 5: Update `.agent/SERVICES.md`
1. Record the host port allocation in `.agent/SERVICES.md`.
2. Record volume persistence paths and UID:GID requirements.
3. Add the service definition to the services catalog.

### Stage 6: Syntax Validation & Idempotency
1. Validate Compose configuration syntax:
   ```bash
   docker compose config --quiet
   ```
2. If validation reports errors, correct formatting or missing variables before proceeding.
3. Verify that `/health` or `/healthz` responds with HTTP 200 and access logs discard probe heartbeats:
   ```bash
   # Assert probe endpoint responds cleanly
   curl -f http://127.0.0.1:<PORT>/health || curl -f http://127.0.0.1:<PORT>/healthz
   # Assert probe heartbeats do not flood container logs
   docker compose logs --tail=50 service-name | grep -E "GET /(health|healthz)" || echo "Probe logs suppressed"
   ```
4. If authorized to launch:
   ```bash
   docker compose up -d service-name
   docker compose ps service-name
   ```
