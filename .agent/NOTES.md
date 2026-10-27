# NOTES.md — Active Infrastructure Contracts, Decisions, and Gotchas

> Stores active service port bindings, volume strategies, data contracts, and operational invariants.
> Architectural decisions log lives in [`docs/adr/decisions.md`](../docs/adr/decisions.md).
> Service topology and port registry live in [`.agent/SERVICES.md`](SERVICES.md).
> Multi-repo ecosystem and sibling contracts live in [`.agent/ECOSYSTEM.md`](ECOSYSTEM.md).
> Atomic knowledge cards live in [`.agent/knowledge/`](knowledge/).

---

## How to Use this File (for the Agent)

1. **Read before planning any task:** Active contracts prevent host-level port collisions, volume wipes, and telemetry storms.
2. **Keep this file lean:** Only store active infrastructure contracts and critical runtime invariants.
3. **Architectural decisions:** Record historical and cumulative decisions in [`docs/adr/decisions.md`](../docs/adr/decisions.md).
4. **Knowledge Cards:** Detailed troubleshooting lessons and platform quirks belong in [`.agent/knowledge/`](knowledge/).

---

## Active Contracts

### 1. Active Storage & Port Invariants

- **Persistence Policy:**
  - Named volumes for high-write engines: `victorialogs_data` and `vector_data`.
  - Read-only bind mounts (`:ro`) for configuration files (`./vector:ro`) and `/var/run/docker.sock:ro`.
- **Host Port Allocation:**
  - `9428`: VictoriaLogs HTTP API & Web UI (VMUI).
  - `8686`: Vector HTTP log ingestion.
  - `5140/udp`: Vector Syslog UDP ingestion.
  - `9598`: Vector Prometheus metrics exporter.
  - `8880`: Optional `vmalert` web and status endpoint.
- **Resource Boundaries:**
  - Mandatory 150 MB RAM combined ceiling (`80M` VictoriaLogs + `60M` Vector) as homelab operational safeguard.

### 2. Canonical Log Event Schema & Stream Dimensions

Every log processed by Vector and indexed by VictoriaLogs adheres to the following contract:

| Field | Type | Description | Example |
|---|---|---|---|
| `timestamp` | `string (ISO8601)` | Log event timestamp in UTC | `2026-10-27T12:00:00.000Z` |
| `level` | `string` | Normalized log level (`error`, `warn`, `info`, `debug`) | `info` |
| `app` | `string` | Service or repository identifier | `api-gateway` |
| `env` | `string` | Runtime environment (`production`, `development`) | `production` |
| `message` | `string` | Primary readable log message text | `Server started on port 8080` |
| `service` | `string` | Service name (synchronized with `app`) | `api-gateway` |
| `container_name`| `string` | Source Docker container or host identifier | `api-gateway` |
| `host` | `string` | Hostname or physical/virtual node identifier | `proxmox-homelab` |
| `stream` | `string` | Origin channel (`stdout`, `stderr`, `syslog`, `http`) | `stdout` |
| `trace_id` | `string (opt)` | Promoted distributed trace correlation ID | `abc-123` |
| `request_id` | `string (opt)` | Promoted HTTP request correlation ID | `req-456` |
| `http_status` | `int (opt)` | Promoted HTTP response status code | `200` |
| `duration_ms` | `float (opt)` | Promoted execution duration in milliseconds | `42.5` |
| `context` | `object (opt)` | Optional nested key-value metadata | `{"userId": 123}` |
| `structured` | `object (opt)` | Raw parsed JSON payload when message is JSON | `{"path": "/health"}` |
| `stack_trace` | `string (opt)` | Extracted traceback in error events | `Error: ...\n at ...` |

- **Stream Header Contract:** `VL-Stream-Fields: "host,container_name,service,app,env,stream"`
- **High Cardinality Invariant:** `trace_id`, `request_id`, `userId`, JIDs, and URLs MUST NEVER be promoted to stream fields. They remain discrete event fields.

### 3. Native MCP Server & SRE Investigation Triad

- **Transport:** Pure Python 3 (`mcp/server.py`), supporting `stdio` mode and native HTTP/SSE daemon via `--sse PORT` (< 22 MB RAM).
- **Mandatory Directives for Agents:**
  1. *Scope by Service:* Always specify `service="app-name"` in `query_logs` and `get_errors` to avoid multi-tenant noise.
  2. *Mandatory Quotes:* Double quotes `"` are mandatory for identifiers containing `@`, `:`, `/`, `-`, `.` in LogsQL (see [k-004](knowledge/k-004-logsql-special-character-quoting.md)).
  3. *3-Phase SRE Funnel:* `get_log_hits` (Phase 1) ➔ `get_errors` (Phase 2, `limit=5..10`) ➔ `get_context_logs` / `fields` (Phase 3).

---

## Multi-Agent Collaboration Roles

> For infrastructure environments operating with multiple AI agents.

- **Planner:** Manages `.agent/TASK.md`, coordinates topology changes, and asserts blast radius.
- **Operator (Developer):** Authors Compose manifests, VRL transforms, and MCP tooling strictly within task scope.
- **Auditor:** Verifies resource limits, healthchecks, permissions, and zero `-v` in teardown commands.

---

## Critical Runtime Gotchas & Knowledge Links

- **Vector Self-Exclusion:** Vector MUST exclude itself (`exclude_containers: ["vector"]`) in `docker_logs` to prevent infinite recursive log loops.
- **VictoriaLogs Distroless Healthcheck:** Image is scratch-based without `/bin/sh` or `/bin/tar`. Healthcheck MUST use `["CMD", "/victoria-logs-prod", "-version"]`.
- **Vector HTTP Sink Framing:** In Vector HTTP sinks, `framing:` must be sibling to `encoding:` (not nested inside) to output valid NDJSON rather than a JSON array.
- **Clamping in VRL:** Non-error logs exceeding 8192 chars are clamped with `... [truncated by collector]` and `.truncated = true`. Error events with stack traces are never truncated.
- **Healthcheck Probe Discarding:** Routine successful probes (`/health`, `/healthz`, `/live`, `/ready`, `/ping`, `/metrics`) returning HTTP 200/204 are discarded at the collector edge to prevent disk and indexing churn (see [k-002](knowledge/k-002-healthcheck-logging-contract.md)).
- **Partition Snapshots & Backup:** See [k-003](knowledge/k-003-victorialogs-partition-snapshot-backup.md).
- **LogsQL Character Quoting:** See [k-004](knowledge/k-004-logsql-special-character-quoting.md).
- **Virtual Disk Scheduler Tuning:** See [k-005](knowledge/k-005-proxmox-qemu-disk-scheduler-tuning.md).

---

## Assumed Technical Debt

| Debt | Decision Rationale | Revisit When |
|---|---|---|
| Single-node VictoriaLogs without clustering | Homelab hardware constraint (< 150 MB RAM total stack) | Multi-node cluster migration (> 100k events/sec) |
| Local disk queue buffer in Vector | Minimal footprint without Kafka/Redis dependencies | Cross-node distributed ingestion requirement |
