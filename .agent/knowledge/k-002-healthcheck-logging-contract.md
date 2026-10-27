---
id: "k-002"
title: "Standardize Healthcheck Endpoints and Suppress Probe Log Pollution"
date: 2026-10-27
tags:
  - "healthcheck"
  - "logging"
  - "victorialogs"
  - "vector"
  - "docker"
  - "compose"
severity: "medium"
affected_components:
  - "compose.yaml.example"
  - ".agent/skills/compose-service/SKILL.md"
  - ".agent/SERVICES.md"
symptoms:
  - "High log volume and disk write churn from frequent HTTP 200 healthcheck access logs"
  - "VictoriaLogs queries cluttered by periodic GET /health or GET /healthz access logs every 10-30s"
  - "Excessive network and parsing overhead in log collectors (Vector) from non-actionable probe events"
---

# [k-002] Standardize Healthcheck Endpoints and Suppress Probe Log Pollution

## Problem / Symptom

Container orchestrators and Docker Compose execute periodic healthcheck probes (e.g., every 15s to 30s) to evaluate container liveness and readiness. When web servers (Nginx, Traefik, Caddy) or backend runtimes (FastAPI, Express, Go) log every incoming HTTP request unconditionally, access logs become flooded with repetitive 200 OK probe lines:

```text
127.0.0.1 - - [27/Oct/2026:11:00:00 +0000] "GET /health HTTP/1.1" 200 15 "-" "curl/8.5.0"
127.0.0.1 - - [27/Oct/2026:11:00:15 +0000] "GET /health HTTP/1.1" 200 15 "-" "curl/8.5.0"
127.0.0.1 - - [27/Oct/2026:11:00:30 +0000] "GET /health HTTP/1.1" 200 15 "-" "curl/8.5.0"
```

This creates severe operational issues:
1. **Disk I/O amplification:** In small homelab environments (e.g., SSDs or HDDs), millions of useless log lines wear storage drives and exhaust disk quotas.
2. **Telemetry pollution:** Ingestion pipelines (Vector $\rightarrow$ VictoriaLogs) waste CPU, memory, and indexing bandwidth ingesting heartbeat noise.
3. **Reduced query signal-to-noise:** Searching logs for real user traffic or errors (`get_errors`, LogsQL) requires filtering out probe noise.

---

## Approved Solution

Adopt a two-part standard across all service definitions:

### 1. Endpoint Standardization: `/health` or `/healthz`
All HTTP-based services MUST expose dedicated, lightweight health endpoints adhering to the canonical naming standard:
- **`/health`** or **`/healthz`**: Liveness probe endpoint returning HTTP 200 with minimal payload (e.g. `{"status":"ok"}`).
- **Lightweight Execution:** Probes MUST execute in-memory checks only. Do not perform heavy database queries, distributed cache sweeps, or external third-party API calls on high-frequency liveness ticks.

### 2. Probe Access Log Suppression at the Source
Configure web servers, reverse proxies, and application loggers to discard or suppress access logging for successful (HTTP 2xx) probe hits while preserving non-2xx failures:

#### A. Nginx Configuration
Disable access logs specifically on the healthcheck location block:
```nginx
location = /health {
    access_log off;
    return 200 '{"status":"ok"}';
    add_header Content-Type application/json;
}
```

Or use conditional access logging based on response status:
```nginx
map $status $loggable {
    ~^[23]  0;
    default 1;
}

access_log /var/log/nginx/access.log combined if=$loggable;
```

#### B. Traefik Access Log Filtering
In Traefik static configuration or Compose labels, filter healthcheck paths from access logs:
```yaml
# In traefik.yml or command arguments:
accessLog:
  filters:
    statusCodes:
      - "400-599"
    retryAttempts: true
    minDuration: "10ms"
```

#### C. FastAPI / Python Middleware
Use custom logging middleware or route filtering to suppress probe noise from standard access log handlers:
```python
import logging

class EndpointFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        # INVARIANT: Drop successful health probes from access logs to prevent VictoriaLogs pollution
        return not any(path in record.getMessage() for path in ("/health", "/healthz"))

logging.getLogger("uvicorn.access").addFilter(EndpointFilter())
```

#### D. Edge Dropping in Vector (Pipeline Safety Net)
When applications cannot disable probe logs internally, drop them at the Vector edge:
```vrl
# Vector VRL transform: drop successful health checks
if match(string!(.message), r'GET /(health|healthz|ping)') && !match(string!(.message), r'(error|fail|warn|50[0-9]|40[0-9])') {
    abort
}
```

### 3. Docker Compose Healthcheck Configuration
In `compose.yaml`, use explicit loopback bindings, bounded timeouts, and sensible intervals:
```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/health || exit 1"]
  interval: 15s
  timeout: 5s
  retries: 3
  start_period: 10s
```

**Root Cause:** Health probes are periodic heartbeat signals intended for orchestrators, not audit-worthy business events. When treated as standard HTTP requests, they dominate log counts by orders of magnitude.

---

## What NEVER to Do

- ❌ **Anti-Pattern:** Removing `healthcheck:` blocks from Compose services to avoid log noise.
  - *Why:* Disabling healthchecks eliminates automatic container recovery, breaks `depends_on.condition: service_healthy` ordering, and degrades service reliability.
- ❌ **Anti-Pattern:** Probing heavy application endpoints (e.g. `GET /api/v1/dashboard` or `GET /api/v1/users`).
  - *Why:* Running complex business logic or DB queries on every probe tick induces unnecessary CPU and database load.
- ❌ **Anti-Pattern:** Suppressing all error logs on `/health` or `/healthz`.
  - *Why:* When a service turns unhealthy (returns HTTP 500 or 503), the failure MUST be logged to diagnose the incident.
- ❌ **Anti-Pattern:** Setting aggressive sub-second probe intervals (`interval: 1s`).
  - *Why:* Overly frequent probing starves the container's event loop and induces excessive CPU wakeups.

---

## Verification

1. Verify the service returns HTTP 200 on `/health` or `/healthz`:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/health
   # Expected output: 200
   ```

2. Confirm that access logs do NOT record repeating 200 OK lines while the container is healthy:
   ```bash
   docker compose logs --tail=20 app | grep -E "GET /(health|healthz)" || echo "Probe logs successfully discarded"
   ```

3. Confirm that healthcheck probe failures (e.g. during degraded state or shutdown) are still visible in logs:
   ```bash
   docker compose logs app | grep -E "level.*(error|warn)"
   ```

---

## References
- [Docker Compose Healthcheck Specification](https://docs.docker.com/reference/compose-file/services/#healthcheck)
- [VictoriaLogs Integration Guide (`victorialogs-integration` skill)](https://github.com/ye-sandbox/infra-victoria-logs)
- [Docker Compose Hygiene Guide (`docker-compose-hygiene` skill)](https://github.com/ye-sandbox/agent-skills)
