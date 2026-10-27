# Infrastructure Services Catalog and Topology (SERVICES.md)

> 🎯 **Purpose of this File:** Canonical living source of truth for topology, host port allocations, data persistence volumes, and network policies for services provisioned in this repository.
>
> ⚠️ **Mandatory Rule for the Agent:** NEVER bring up or modify containers in `compose.yaml` without first recording and verifying potential conflicts in the tables below.

---

## 1. Host Port Allocations

> Record all ports bound on the host to avoid binding collisions (`bind: address already in use`).

| Host Port | Protocol | Service | Container Port | Exposure | Purpose / Endpoint |
| :---: | :---: | :--- | :---: | :--- | :--- |
| `9428` | TCP | `victorialogs` | `9428` | `127.0.0.1` (Local) | VictoriaLogs HTTP ingestion and VMUI web interface |
| `8686` | TCP | `vector` | `8686` | `127.0.0.1` (Local) | Vector HTTP log ingestion API (`POST /logs`) and healthcheck |
| `5140` | UDP | `vector` | `5140` | `0.0.0.0` (LAN) | Vector Syslog UDP ingestion endpoint (RFC5424 / RFC3164) |
| `9598` | TCP | `vector` | `9598` | `127.0.0.1` (Local) | Vector Prometheus internal metrics exporter |
| `8880` | TCP | `vmalert` | `8880` | `127.0.0.1` (Local) | vmalert Web UI & HTTP healthcheck endpoint (profile: `alerting`) |
| `9093` | TCP | `alert-bridge` | `9093` | `127.0.0.1` (Local) | Alertmanager v2/v1 HTTP webhook API & healthcheck (profile: `alerting`) |
| `8000` | TCP | `mcp-server` (optional) | N/A (Host) | `0.0.0.0` (LAN) | Native Model Context Protocol (MCP) SSE & HTTP API (`--sse 8000`) |

*(Exposure types: `127.0.0.1` [local host only], `0.0.0.0` [public / LAN], `Internal Network` [no host port, Docker DNS only])*

---

## 2. Volumes and Data Persistence Matrix

> Ensure no production data is kept ephemerally inside container layers, and document required permissions.

| Service | Type | Host Path / Volume | Container Path | UID:GID | Mandatory Backup? |
| :--- | :---: | :--- | :--- | :---: | :---: |
| `victorialogs` | Named Volume | `victorialogs_data` | `/victoria-logs-data` | `1000:1000` | Yes (daily via `scripts/backup.sh`; optional off-site 3-2-1 sync) |
| `vector` | Named Volume | `vector_data` | `/var/lib/vector` | `1000:1000` | No (ephemeral disk buffer fallback) |
| `vector` | Bind Mount | `./vector/vector.${STORAGE_PROFILE:-hdd}.yaml` | `/etc/vector/vector.yaml:ro` | `root:root` | No (git-versioned) |
| `vector` | Bind Mount | `./vector` | `/etc/vector:ro` | `root:root` | No (git-versioned) |
| `vector` | Bind Mount | `/var/run/docker.sock` | `/var/run/docker.sock:ro` | `root:docker` | No (host system socket) |
| `vmalert` | Bind Mount | `./vmalert/rules.yaml` | `/etc/vmalert/rules.yaml:ro` | `root:root` | No (git-versioned) |
| `alert-bridge` | Bind Mount | `./alert-bridge` | `/app:ro` | `root:root` | No (git-versioned) |

*(Volume types: `Named Volume` [Docker-managed volume], `Bind Mount` [Host mapped directory])*

---

## 3. Docker Virtual Networks Matrix

> Segregate traffic for security containment and minimal blast radius.

| Network Name | Driver | Scope | Purpose and Connected Services |
| :--- | :---: | :---: | :--- |
| `logging-network` | bridge | Internal | Isolated telemetry network connecting `victorialogs`, `vector`, `vmalert`, and `alert-bridge` |

---

## 4. Services, Images, and Healthchecks Catalog

> Every service MUST declare explicit healthchecks, security opt (`no-new-privileges`), read-only root filesystems, and strict memory boundaries.

### 📌 `victorialogs`
- **Image:** `victoriametrics/victoria-logs:${VICTORIALOGS_VERSION:-latest}`
- **Description:** High-performance log indexing and query engine using native LogsQL.
- **Networks:** `logging-network`
- **Security Hardening:** `read_only: true`, `tmpfs: [/tmp]`, `no-new-privileges: true`, `stop_grace_period: 30s`
- **Healthcheck:**
  - **Command:** `["CMD", "/victoria-logs-prod", "-version"]`
  - **Interval:** `15s` | **Timeout:** `5s` | **Retries:** `3` | **Start Period:** `10s`
- **Resource Limits:** CPU: `0.50` | Memory: `80M` (Reservation: `30M`)

### 📌 `vector`
- **Image:** `timberio/vector:${VECTOR_VERSION:-0.45.0-alpine}`
- **Description:** High-throughput log router and normalizer running VRL transforms.
- **Networks:** `logging-network`
- **Security Hardening:** `read_only: true`, `tmpfs: [/tmp]`, `no-new-privileges: true`, `stop_grace_period: 15s`
- **Healthcheck:**
  - **Command:** `["CMD-SHELL", "nc -z 127.0.0.1 8686 || exit 1"]`
  - **Interval:** `15s` | **Timeout:** `5s` | **Retries:** `3` | **Start Period:** `10s`
- **Resource Limits:** CPU: `0.50` | Memory: `60M` (Reservation: `20M`)

### 📌 `vmalert`
- **Image:** `victoriametrics/vmalert:${VMALERT_VERSION:-latest}`
- **Description:** Alerting daemon evaluating alert rules against VictoriaLogs via HTTP.
- **Profiles:** `alerting` (optional, spun up on-demand)
- **Networks:** `logging-network`
- **Security Hardening:** `read_only: true`, `tmpfs: [/tmp]`, `no-new-privileges: true`
- **Healthcheck:**
  - **Command:** `["CMD-SHELL", "wget --spider -q http://127.0.0.1:8880/health || exit 1"]`
  - **Interval:** `30s` | **Timeout:** `5s` | **Retries:** `3` | **Start Period:** `10s`
- **Resource Limits:** CPU: `0.20` | Memory: `25M` (Reservation: `10M`)

### 📌 `alert-bridge`
- **Image:** `python:${ALERT_BRIDGE_PYTHON_VERSION:-3.14-alpine}`
- **Description:** Lightweight notification bridge receiving Alertmanager alerts from vmalert and dispatching to ntfy, Telegram, and generic Webhooks.
- **Profiles:** `alerting` (optional, spun up on-demand)
- **Networks:** `logging-network`
- **Security Hardening:** `read_only: true`, `tmpfs: [/tmp]`, `no-new-privileges: true`
- **Healthcheck:**
  - **Command:** `["CMD-SHELL", "wget --spider -q http://127.0.0.1:9093/health || exit 1"]`
  - **Interval:** `30s` | **Timeout:** `5s` | **Retries:** `3` | **Start Period:** `10s`
- **Resource Limits:** CPU: `0.20` | Memory: `25M` (Reservation: `10M`)
