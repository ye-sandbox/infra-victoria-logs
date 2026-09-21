# 🪵 Minimalist Homelab Log Observability (VictoriaLogs + Vector)

**[English](README.md)** | **[Português (Brasil)](README.pt-br.md)**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/ye-sandbox/infra-victoria-logs)](https://github.com/ye-sandbox/infra-victoria-logs/releases)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2+-blue.svg)](https://docs.docker.com/compose/)
[![VictoriaLogs](https://img.shields.io/badge/VictoriaLogs-latest-orange.svg)](https://docs.victoriametrics.com/victorialogs/)
[![Vector](https://img.shields.io/badge/Vector-0.45.0--alpine-purple.svg)](https://vector.dev/)
[![Footprint](https://img.shields.io/badge/RAM%20Usage-%3C%20150MB-success.svg)]()

A minimalist, high-performance log observability and aggregation stack tailored for **Homelabs (Mini PCs, Intel NUCs, and Proxmox VE servers running Docker)**.

Configured with a default **RAM safeguard ceiling of < 150 MB (VictoriaLogs <= 80 MB, Vector <= 60 MB)** specifically because it runs on resource-constrained local infrastructure, ensuring it operates reliably without consuming excessive host resources. This solution comfortably replaces resource-heavy stacks like Grafana Loki/Promtail or Elasticsearch/Logstash while remaining fully tunable for larger environments. It is purpose-built for both human troubleshooting (native VMUI Web UI) and **autonomous AI coding agents** (Claude Code, Antigravity, Cursor, Roo Code) performing incident triage and root cause analysis.

> 💡 **Docker Host Coexistence:** If you run other applications on the same Docker host (e.g., Portainer, Traefik, Uptime Kuma), verify that ports `9428` (VictoriaLogs), `8686` (Vector HTTP), `5140/udp` (Syslog), and `9598` (Prometheus metrics) do not conflict with existing host bindings.

---

## 🏗️ Architecture & Data Flow

```mermaid
flowchart LR
    subgraph Sources["Log Sources (Homelab)"]
        D[Local Docker Containers\n/var/run/docker.sock]
        P[Proxmox VE / LXCs / VMs\nSyslog UDP 5140]
        A[External Apps / Scripts\nHTTP JSON 8686]
    end

    subgraph Collector["Collector & Router"]
        V[Vector Agent\n(~40-60 MB RAM)]
    end

    subgraph Storage["Storage & Search Engine"]
        VL[VictoriaLogs\n(~60-80 MB RAM)]
    end

    subgraph Consumers["Consumers"]
        UI[Operators & Developers\nVMUI Web :9428]
        AI[AI Agents & Automation\nLogsQL HTTP API / MCP :9428]
    end

    D --> V
    P --> V
    A --> V
    V -- "HTTP POST (zstd ndjson)\nVL-Stream-Fields" --> VL
    VL --> UI
    VL --> AI
```

### Why VictoriaLogs + Vector?
- **Ultra-Low Memory Footprint:** Both runtimes compile to static native binaries (VictoriaLogs in Go, Vector in Rust). Completely free of JVM, Python runtime bloat, or heavy background daemons. Default footprint is safeguarded **< 150 MB RAM** to avoid excessive host consumption on limited infrastructure.
- **High-Density Compression:** VictoriaLogs compresses logs by up to 10x–15x compared to raw text, significantly reducing SSD wear and disk usage on Mini PCs.
- **Intuitive LogsQL Query Language:** An expressive, pipe-based query engine designed for humans and AI agents alike, avoiding complex query generation and hallucination pitfalls.
- **Automatic Container Discovery:** Vector automatically discovers, enriches, and tags metadata from all running Docker containers via the local Docker socket.

---

## 📁 Repository Structure

```text
.
├── docker-compose.yml       # Production orchestration with strict RAM limits (140 MB combined)
├── vector/
│   ├── vector.hdd.yaml      # Spinning disk profile (RAM buffer, 15s batching, noise filtering)
│   ├── vector.ssd.yaml      # SSD/NVMe profile (disk buffer, 1s batching, full retention)
│   ├── vector.geoip.yaml    # GeoIP profile (MaxMind GeoLite2 enrichment for web workloads)
│   └── vector.yaml          # Base configuration and fallback pipeline
├── dashboards/
│   └── grafana-victorialogs.json      # Official pre-built Grafana dashboard (throughput, errors, status)
├── docs/
│   └── proxmox-hardening.md # Hardening, sysctl tuning, and I/O containment guide for Proxmox VE
├── mcp/
│   └── server.py            # Native stdio Model Context Protocol (MCP) server for AI Agents
├── scripts/
│   ├── audit-security.sh    # Host security auditor, permission enforcement, and Compose hardening
│   ├── backup.sh            # Atomic zero-downtime snapshot backup with retention rotation
│   ├── health-dashboard.sh  # Terminal CLI live telemetry dashboard powered by native APIs
│   ├── logsql-queries.sh    # Pre-canned analytical queries (top errors, latency, HTTP status codes)
│   ├── manage-partitions.sh # Partition auditor, daily ingestion projector, and emergency purge utility
│   ├── check-disk-growth.sh # Automated cron auditor and alert generator for disk consumption
│   ├── run-maintenance-pipeline.sh # Unified daily orchestrator (disk check + backup + smoke test)
│   ├── test-pipeline.sh     # End-to-end smoke test for ingestion and LogsQL queries in < 5s
│   ├── test-mcp.sh          # Automated test suite for JSON-RPC 2.0 MCP server tools
│   ├── ship-docker-stats.sh # Container CPU/RAM resource metric collector shipped to Vector
│   ├── ship-docker-events.sh# Real-time daemon event listener (crashes, restarts, OOMKilled)
│   ├── download-geolite2.sh # Automatic downloader/updater for MaxMind GeoLite2 City (.mmdb)
│   ├── install-agent-skills.sh # Global skill symlink installer for Cursor, Antigravity, and Claude
│   ├── install-host-collectors.sh # Registers continuous collectors as systemd host services
│   ├── tune-docker-host.sh  # Docker daemon optimizer (non-blocking logging mode for spinning disks)
│   └── tune-disk-host.sh    # Linux disk tuning assistant (virtualization-aware, noatime, schedulers)
├── skills/
│   ├── github-bug-issue/              # Parks bugs into GitHub issues with VictoriaLogs pointers
│   ├── victorialogs-integration/      # Canonical application logging contract (Python, Node, Go, Docker)
│   │   └── examples/                  # Plug-and-play templates (Loguru, stdlib, Pino, Slog)
│   └── victorialogs-troubleshooting/  # SRE investigation playbook for AI agents via LogsQL & MCP
├── vmalert/
│   └── rules.yaml           # LogsQL alert rules (error spikes, OOM kills, elevated latency)
├── tests/
│   └── test_mcp_error_enricher.py     # Unit tests for MCP query sanitization and syntax tips
├── .env.example             # Documented template for environment variables and security keys
├── .gitignore               # Ignores .env, .cursor/, data volumes, backups, and secrets
├── CHANGELOG.md             # Version history and release notes (Keep a Changelog standard)
├── LICENSE                  # Open-source license (Apache License 2.0)
├── CONTRIBUTING.md          # Contributor guide and default 150 MB RAM safeguard baseline
├── SECURITY.md              # Responsible vulnerability disclosure policy
├── AGENTS.md                # AI agent operating rules, engineering standards, and DoD criteria
├── .agent/                  # Persistent agent tracking files (TASK.md, NOTES.md)
├── README.pt-br.md          # Complete technical documentation in Portuguese
└── README.md                # Primary technical documentation in English
```

---

## 🚀 Quickstart Guide

### 1. Prerequisites
- Docker Engine 24+ and Docker Compose v2+ installed on the host (e.g., Debian/Ubuntu running natively or inside a Proxmox VE KVM VM).

### 2. Environment Setup
Clone the repository and copy the environment template:
```bash
cp .env.example .env
```

Edit `.env` to select your hardware storage profile and host parameters:
```env
# Set 'hdd' for mechanical spinning disks or 'ssd' for SSD/NVMe
STORAGE_PROFILE=hdd

HOST_IDENTIFIER=mini-pc-proxmox
RETENTION_PERIOD=1y
VICTORIALOGS_HTTP_PORT=9428
```

### 3. Launch the Stack
```bash
docker compose up -d
```

### 4. Run End-to-End Smoke Test
Validate log ingestion and query execution in under 5 seconds:
```bash
./scripts/test-pipeline.sh
```

### 5. Check Service Health & Memory Consumption
```bash
docker compose ps
docker stats --no-stream
```
*You will observe that the combined memory usage of `victorialogs` and `vector` remains strictly below 150 MB.*

---

## 🔍 How to Query Logs

### 1. Web User Interface (VMUI)
Open your browser and navigate to:
```text
http://<HOST_IP>:9428/select/vmui/
```
VMUI provides an interactive query editor, visual time histograms, and real-time field filtering.

---

### 2. HTTP API / Curl (For AI Agents & Automation)

AI agents and automated shell scripts can query VictoriaLogs directly via its HTTP endpoint (`/select/logsql/query`).

#### Example 1: Fetch the last 20 error logs across all containers
```bash
curl -s -G "http://localhost:9428/select/logsql/query" \
  --data-urlencode 'query=_time:1h AND level:error' \
  --data-urlencode 'limit=20'
```

#### Example 2: Filter logs from a specific container containing "timeout" or "panic"
```bash
curl -s -G "http://localhost:9428/select/logsql/query" \
  --data-urlencode 'query=_stream:{container_name="my-backend"} AND (timeout OR panic)' \
  --data-urlencode 'limit=50'
```

#### Example 3: Error event count grouped in 5-minute buckets (Hits)
```bash
curl -s -G "http://localhost:9428/select/logsql/hits" \
  --data-urlencode 'query=_time:30m AND level:error' \
  --data-urlencode 'step=5m'
```

---

### 3. Native Model Context Protocol (MCP) Server for AI Agents

The repository includes a **native stdio MCP Server** ([`mcp/server.py`](./mcp/server.py)) written in Pure Python 3 (zero third-party dependencies, < 22 MB RAM). It allows Claude Code, Cursor, Roo Code, and Antigravity to investigate errors and metrics directly with built-in deduplication, saving up to 99.8% of LLM context tokens compared to raw JSON dumps:

#### Available MCP Tools (9 Specialized Tools):
| Tool Name | Purpose | Token Optimization |
|---|---|---|
| `get_errors` | Extracts distinct errors and stack traces with **smart deduplication**, application filtering (`service`), default telemetry noise exclusion, and proactive SRE tips. | High (deduplicates errors, filters noise) |
| `get_context_logs` | Fetches chronological logs immediately before and after an error timestamp (fore/aft incident window; filters noise and collapses consecutive repeats by default). | High (bounded surrounding context) |
| `query_logs` | Executes flexible LogsQL queries with `service` scoping, consecutive repeated collapse, ANSI sanitization, optional `fields` projection, and compact markdown. | Configurable (filters metrics by default, collapses repeats) |
| `get_log_hits` | Visual event histogram over time grouped by minutes or hours for rapid anomaly triage (filters metric noise by default). | Extreme (aggregated counts) |
| `list_streams` | Instantly lists active containers, services, and hosts via native stream endpoints. | High |
| `field_names` | Discovers indexed field keys (e.g., `service`, `userId`, `http_status`; supports application scoping via `service`). | High (scopes discovery to service) |
| `field_values` | Lists the top most frequent values for any indexed field. | High |
| `documentation` | Built-in offline quick reference for LogsQL syntax, filters, pipes, and regex. | Offline reference |
| `health_check` | Tests reachability and response latency of VictoriaLogs. | Negligible |

> [!TIP]
> **Default Telemetry Noise Suppression:** To protect LLM context windows, global queries in `query_logs`, `get_errors`, `get_context_logs`, and `get_log_hits` automatically exclude high-frequency telemetry streams (`docker-stats` and `cadvisor`). If you explicitly need to inspect host metrics or cAdvisor logs, specify `service="docker-stats"` or `service="cadvisor"`.

#### 🎯 SRE Investigation Funnel & Token Budget Governance:

To prevent context window exhaustion and maximize diagnostic accuracy, AI agents operating on this stack follow the **3-Phase SRE Triage Funnel**:

1. **Phase 1 — Aggregate Time & Spike Triage (`get_log_hits`)**:
   - Query error counts over time (e.g. `query='_stream:{service="api"} AND level:error'`, `step="1m"` or `"5m"`, `max_buckets=15`).
   - Zero log body extraction (~50–150 tokens) to pinpoint the exact incident onset without message bloat.
2. **Phase 2 — Deduplicated Error Isolation (`get_errors`)**:
   - Query with `service="app-name"` and conservative sampling (`limit=5..10`).
   - Extracts deduplicated stack traces with occurrence counts (`[42x]`), eliminating repetitive traceback storms.
3. **Phase 3 — Forensic Context & Column Projection (`get_context_logs` / `query_logs`)**:
   - Retrieve immediate precursor events via `get_context_logs(target_timestamp="...", window_seconds=10, limit=10)` with visual incident highlighting (`🎯 [TARGET / INCIDENT]`) and consecutive repeat collapse.
   - For latency, status code, or correlation audits, use `query_logs(fields="http_status,duration_ms,request_id", limit=10)` to project compact key-value lines, saving >80% tokens.

#### Client Configuration:

> [!NOTE]
> `.cursor/` is local and excluded via `.gitignore`. Do not commit your local `mcp.json`. It points to the host IP where VictoriaLogs is reachable from your client workstation.

##### 1. Cursor & Claude Desktop:
Create or edit `.cursor/mcp.json` in your workspace (or `~/.cursor/mcp.json` / `%USERPROFILE%\.cursor\mcp.json` globally). The same block works for Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "victorialogs": {
      "type": "stdio",
      "command": "/usr/bin/python3",
      "args": ["/absolute/path/to/infra-victoria-logs/mcp/server.py"],
      "env": {
        "VICTORIALOGS_URL": "http://<HOST_IP>:9428"
      }
    }
  }
}
```

##### 2. Google Antigravity:
Configure your global `~/.gemini/config/mcp_config.json`:

```json
{
  "mcpServers": {
    "victorialogs": {
      "command": "/usr/bin/python3",
      "args": ["/absolute/path/to/infra-victoria-logs/mcp/server.py"],
      "env": {
        "VICTORIALOGS_URL": "http://<HOST_IP>:9428"
      }
    }
  }
}
```

Use `http://127.0.0.1:9428` only if VictoriaLogs runs on the same machine as the client. If running inside a remote VM, specify the reachable VM IP address.

**Verify MCP Server Locally:**
```bash
./scripts/test-mcp.sh
```

---

## 📡 Ingestion from Other Homelab Sources

### 1. Proxmox VE Host Syslog Forwarding
To forward Proxmox host system logs (`/var/log/syslog` and `journald`) to the stack:
1. On the Proxmox host, edit `/etc/rsyslog.d/60-vector.conf`:
   ```text
   *.* @<STACK_HOST_IP>:5140
   ```
2. Restart rsyslog on Proxmox:
   ```bash
   systemctl restart rsyslog
   ```

### 2. HTTP POST Ingestion (Applications & Scripts)
Any Python script, Bash utility, or microservice can emit JSON events directly to Vector:
```bash
curl -X POST http://<STACK_HOST_IP>:8686/logs \
  -H "Content-Type: application/json" \
  -d '{
    "service": "backup-script",
    "level": "info",
    "message": "ZFS pool backup finished successfully in 42s"
  }'
```

---

## 💾 Storage Profiles: HDD vs SSD Mode

Select the storage profile via `STORAGE_PROFILE` in your `.env` file to dynamically tune the ingestion pipeline for your physical hardware:

| Parameter / Behavior | 💾 HDD Mode (`STORAGE_PROFILE=hdd`) | ⚡ SSD Mode (`STORAGE_PROFILE=ssd`) | 🌍 GeoIP Mode (`STORAGE_PROFILE=geoip`) |
|---|---|---|---|
| **Operational Focus** | **Minimize IOPS & eliminate I/O wait** | **Low search latency & durable buffering** | **MaxMind GeoLite2 enrichment** |
| **Vector Buffer** | `memory` (RAM, max 10,000 events) — *Zero double disk writes on spinning disks* | `disk` (256 MB persistent volume) — *Crash resilience across restarts* | `memory` (5,000 events) — *Fast in-memory enrichment* |
| **Batching Strategy** | `2 MB` / `15s` — *Consolidates sequential disk writes, stops continuous I/O* | `1 MB` / `1s` — *Logs visible in queries almost instantly* | `1 MB` / `2s` — *Balanced latency and throughput* |
| **GeoIP Enrichment** | Disabled (saves memory) | Disabled (saves memory) | **Enabled** (extracts country, city, and ISO from `client_ip`) |
| **Edge Noise Filter** | **Active** — *Drops routine pings (`/health`, `/ping`, `GET /metrics` scrapes)* | **Active** — *Drops routine pings (`/health`, `/ping`, `GET /metrics` scrapes)* | **Active** — *Drops routine pings (`/health`, `/ping`, `GET /metrics` scrapes)* |
| **Oversized Clamping** | **Active** — *Clamps non-error `.message` > 8 KB with `.truncated=true`* | **Active** — *Clamps non-error `.message` > 8 KB with `.truncated=true`* | **Active** — *Clamps non-error `.message` > 8 KB with `.truncated=true`* |
| **In-Memory Flush (VL)**| `15s` (`VL_INMEMORY_FLUSH_INTERVAL=15s`) — *Reduces small LSM merges on HDD* | `5s` (`VL_INMEMORY_FLUSH_INTERVAL=5s`) — *Rapid disk persistence* | `15s` |
| **Concurrent Queries (VL)**| `2 queries` (`VL_MAX_CONCURRENT_REQUESTS=2`) | `4 queries` (`VL_MAX_CONCURRENT_REQUESTS=4`) | `2 queries` |

> **Activating the GeoIP Profile:**
> 1. Download MaxMind database: `./scripts/download-geolite2.sh`
> 2. Set `STORAGE_PROFILE=geoip` in `.env`
> 3. Restart stack: `docker compose up -d`

### 🔧 Docker Host Tuning for Spinning Disks (Non-Blocking Mode)

On hosts where both the OS and Docker share a single spinning hard drive, Docker's default `blocking` logging driver pauses containers during disk I/O spikes (e.g., nightly backups). To protect application stability:

#### Option A: Use the automated script
```bash
# Check current configuration
sudo ./scripts/tune-docker-host.sh --check

# Apply non-blocking ring-buffer (4 MB RAM buffer per container)
sudo ./scripts/tune-docker-host.sh --apply

# Reload Docker daemon without restarting containers
sudo systemctl reload docker
```

#### Option B: Manual configuration in `/etc/docker/daemon.json`
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "mode": "non-blocking",
    "max-buffer-size": "4m"
  }
}
```
Reload daemon:
```bash
sudo systemctl reload docker
```

### 💽 Host Storage & Kernel Tuning (noatime, I/O Schedulers, and APM)

In single-drive hosts (e.g. Proxmox VE servers where OS and containers share a single mechanical HDD) or virtualized guests (QEMU/KVM, Proxmox VMs), operating system storage configurations prevent latency and unnecessary wear:

1. **`noatime,nodiratime`:** Stops writing filesystem access timestamps every time logs are read.
2. **I/O Scheduler (`mq-deadline` vs `none`):** Orders disk requests via an elevator algorithm on physical rotational HDDs to prevent mechanical head thrashing, while using `none` (NOOP/passthrough) in virtual machines to eliminate redundant double scheduling with the hypervisor.
3. **APM (`hdparm -B 254`):** Maintains constant platter rotation 24/7 on physical rotational HDDs, avoiding destructive spindown cycles (automatically skipped inside VMs).

```bash
# Inspect disks, virtualization environment, and active schedulers
sudo ./scripts/tune-disk-host.sh --check

# Generate persistent udev rule (mq-deadline for physical HDDs, none for VMs)
sudo ./scripts/tune-disk-host.sh --generate-udev

# Remount with noatime immediately without rebooting
sudo ./scripts/tune-disk-host.sh --remount-noatime /
```

> [!TIP]
> For the complete architectural guide including `sysctl` kernel tuning (`vm.max_map_count`), Proxmox Firewall rules, and KVM vs LXC isolation trade-offs, read the [**Proxmox VE Hardening Guide**](docs/proxmox-hardening.md).

---

## ⚙️ Resource Limits & Sizing

The resource definitions in [`docker-compose.yml`](./docker-compose.yml) guarantee predictable operation on modest homelab hardware:

| Service | Hard RAM Limit (Max) | Memory Reservation (Min) | CPU Limit |
|---|---|---|---|
| **VictoriaLogs** | `80 MB` | `30 MB` | `0.50 core` |
| **Vector** | `60 MB` | `20 MB` | `0.50 core` |
| **Combined** | **`140 MB`** | **`50 MB`** | **`1.0 core`** |

- Total combined memory usage is **capped under 150 MB RAM** as a default safeguard against excessive resource consumption on limited hardware.
- In **HDD mode**, Vector buffers in RAM within its `60 MB` ceiling.
- In **SSD mode**, Vector utilizes a `256 MB` disk buffer on the `vector_data` volume.
- If your homelab generates high log throughput (> 20 GB/day), you may scale VictoriaLogs memory to `120M` if required.

---

## 🔒 Security & Basic Authentication (Optional)

To secure the Web UI and query APIs behind HTTP Basic Authentication, set the credentials in [`.env`](./.env.example):
```env
VICTORIALOGS_AUTH_USERNAME=admin
VICTORIALOGS_AUTH_PASSWORD=your_secure_password_here
```
VictoriaLogs will mandate HTTP Basic Auth on all endpoints, and Vector will authenticate automatically.

### 🛡️ Automated Security Audit (`audit-security.sh`)

Validate host security, file permissions, and Compose hardening with the built-in auditor:

```bash
# Interactive visual audit
./scripts/audit-security.sh

# Auto-remediation (chmod 600 .env, chmod 755 scripts)
./scripts/audit-security.sh --fix

# JSON output for CI/CD pipelines or AI agents
./scripts/audit-security.sh --json

# Strict mode for validation gates (fails on warnings)
./scripts/audit-security.sh --strict
```

#### Pillars Inspected:
1. **Host Permissions:** `.env` restricted to `600`/`400`, excluded from Git, and scripts free of world-writable (`o+w`) permissions.
2. **Docker Compose Hardening:** Docker socket (`/var/run/docker.sock`) mounted strictly read-only (`:ro`), immutable root filesystem (`read_only: true`) with ephemeral volatile mounts (`tmpfs: [/tmp]`), hard memory limits enforced (`<= 80M` and `<= 60M`, total `<= 150M`), log loop prevention (`exclude_containers: ["vector"]`), and active healthchecks.
3. **Network Exposure:** Flags unauthenticated public ports listening on `0.0.0.0`.
4. **Runtime Inspection:** Verifies that active kernel cgroups match configured limits, `/var/run/docker.sock` is read-only, and running containers enforce read-only root filesystems.

---

## 📑 Multiline Log Aggregation (Stack Traces)

Vector provides built-in multiline aggregation on its `docker_logs` source using `mode: continue_through`:
- Indented lines (Python tracebacks, Go panics, Java exceptions) are coalesced into the parent log event.
- Every NDJSON object (`{...}`) remains an isolated event. This prevents JSON bursts from being improperly concatenated—see [issue #1](https://github.com/ye-sandbox/infra-victoria-logs/issues/1).
- Prevents error stack traces from fragmenting into dozens of disconnected log records.

---

## 🛠️ Maintenance & Operations Tooling

- **Live Telemetry CLI Dashboard (`health-dashboard.sh`):**
  ```bash
  # Single status run
  ./scripts/health-dashboard.sh

  # Continuous live monitoring (refreshes every 5s)
  ./scripts/health-dashboard.sh --watch
  ```
- **Pre-Built Analytical LogsQL Queries (`logsql-queries.sh`):**
  ```bash
  # Top error-producing services in the last 24 hours
  ./scripts/logsql-queries.sh top-errors --time 24h

  # Slow HTTP requests (> 1s) sorted by duration
  ./scripts/logsql-queries.sh slow-requests -l 10

  # HTTP status distribution (2xx, 4xx, 5xx)
  ./scripts/logsql-queries.sh http-status --time 1h

  # Terminated containers (OOM Exit 137 or abnormal crashes)
  ./scripts/logsql-queries.sh crashes --time 24h

  # Distributed trace lookup by ID
  ./scripts/logsql-queries.sh trace "req-abc-12345"
  ```
- **Partition Management & Capacity Projection (`manage-partitions.sh`):**
  ```bash
  # Audit daily partitions and physical storage
  ./scripts/manage-partitions.sh list

  # Calculate ingestion rate and project 1-year disk requirement
  ./scripts/manage-partitions.sh estimate

  # Emergency partition purge simulation (dry-run)
  ./scripts/manage-partitions.sh purge --older-than 60d --dry-run

  # Execute emergency purge for partitions before a given date
  ./scripts/manage-partitions.sh purge --before 20260801
  ```
- **Periodic Disk Growth Check & Alerting (`check-disk-growth.sh`):**
  ```bash
  # Immediate check
  ./scripts/check-disk-growth.sh

  # Dry-run check with custom threshold
  ./scripts/check-disk-growth.sh --threshold-daily-mb 500 --dry-run

  # Install automated daily cron job (06:00 UTC)
  ./scripts/check-disk-growth.sh --install-cron
  ```
- **Unified Daily Maintenance Pipeline (`run-maintenance-pipeline.sh`):**
  ```bash
  # Run full maintenance (disk check + snapshot + smoke test)
  ./scripts/run-maintenance-pipeline.sh

  # Install unified daily maintenance in cron (03:00 UTC)
  ./scripts/run-maintenance-pipeline.sh --install-cron
  ```
- **Consistent Zero-Downtime Backup (`backup.sh`):**
  ```bash
  # Creates atomic snapshots via VictoriaLogs API and rotates archive copies
  ./scripts/backup.sh
  ```
- **Container Metric Collector (`ship-docker-stats.sh`):**
  ```bash
  # Collect CPU/RAM usage of all local containers once
  ./scripts/ship-docker-stats.sh

  # Run as daemon loop (e.g. every 60s)
  ./scripts/ship-docker-stats.sh --loop 60
  ```
- **Docker Daemon Event Listener (`ship-docker-events.sh`):**
  ```bash
  # Stream events (crashes, restarts, OOMKilled) continuously
  ./scripts/ship-docker-events.sh
  ```
- **Systemd Host Collectors (`install-host-collectors.sh`):**
  ```bash
  # Install continuous metric and event collectors as systemd units
  sudo ./scripts/install-host-collectors.sh --install

  # Check unit status
  ./scripts/install-host-collectors.sh --status
  ```
- **Sync Agent Skills with AI IDEs (`install-agent-skills.sh`):**
  ```bash
  # Symlink skills to Cursor, Antigravity, and Claude
  ./scripts/install-agent-skills.sh --all
  ```

---

## 📊 Self-Monitoring with Prometheus & Grafana

Both VictoriaLogs and Vector expose native Prometheus-compatible metrics out of the box:

| Component | Metrics Endpoint | Default Port | `.env` Variable |
|---|---|---|---|
| **VictoriaLogs** | `http://<HOST_IP>:9428/metrics` | `9428` | `VICTORIALOGS_HTTP_PORT` |
| **Vector** | `http://<HOST_IP>:9598/metrics` | `9598` | `VECTOR_METRICS_PORT` |

### Prometheus Scrape Configuration:
```yaml
scrape_configs:
  - job_name: 'victorialogs'
    scrape_interval: 15s
    static_configs:
      - targets: ['<HOST_IP>:9428']

  - job_name: 'vector'
    scrape_interval: 15s
    static_configs:
      - targets: ['<HOST_IP>:9598']
```

### Pre-Built Grafana Dashboard (`dashboards/grafana-victorialogs.json`)
1. In Grafana, click **Dashboards** > **New** > **Import**.
2. Upload [`dashboards/grafana-victorialogs.json`](./dashboards/grafana-victorialogs.json).
3. Select your Prometheus data source in `${DS_PROMETHEUS}` and click **Import**.

---

## 🚨 Automated Alerting with `vmalert` (Optional)

The optional `alerting` profile provides real-time alerting on LogsQL expressions using `vmalert` (< 25 MB RAM):

```bash
# Start the stack with the alerting profile
docker compose --profile alerting up -d
```

### Pre-Configured Rules in [`vmalert/rules.yaml`](./vmalert/rules.yaml):
1. **`HighErrorRate`:** Triggers if any service logs > 10 errors within 5 minutes.
2. **`ContainerOOMKilled`:** Triggers immediately upon detecting an Exit 137 event.
3. **`ContainerCrashOrDie`:** Triggers when a container terminates with a non-zero status.
4. **`ElevatedHttpLatency`:** Triggers when requests with `duration_ms:>3000` recur.

---

## 🤖 AI Agent Skills (`skills/`)

Versioned canonical skills are included in `skills/` for AI agents:

1. **[`skills/victorialogs-integration`](./skills/victorialogs-integration/SKILL.md):**
   - Canonical NDJSON contract, required stream fields, error tracebacks, and anti-patterns.
   - **Plug-and-Play Examples (`examples/`):** Complete setups for **Python Loguru/stdlib**, **Node.js Pino**, and **Go Slog** with distributed trace support (`trace_id`, `request_id`, `http_status`).
2. **[`skills/victorialogs-troubleshooting`](./skills/victorialogs-troubleshooting/SKILL.md):**
   - Incident investigation and SRE playbook for AI agents using MCP and LogsQL.
3. **[`skills/github-bug-issue`](./skills/github-bug-issue/SKILL.md):**
   - Parks bugs into GitHub issues on target repositories with VictoriaLogs forensic anchors.

To expose skills across all Cursor workspaces:
```bash
mkdir -p ~/.cursor/skills
ln -sfn "$(pwd)/skills/victorialogs-integration" ~/.cursor/skills/victorialogs-integration
ln -sfn "$(pwd)/skills/victorialogs-troubleshooting" ~/.cursor/skills/victorialogs-troubleshooting
ln -sfn "$(pwd)/skills/github-bug-issue" ~/.cursor/skills/github-bug-issue
```

---

## 🤝 Community & Governance

- [Contributing Guidelines](CONTRIBUTING.md): Setup instructions, pre-PR test suite, and the default 150 MB RAM safeguard for limited hardware.
- [Security Policy](SECURITY.md): Responsible vulnerability reporting via GitHub Security Advisories.
- [Changelog](CHANGELOG.md): Detailed release notes adhering to Keep a Changelog.
- [Apache 2.0 License](LICENSE): Permissive terms for personal and commercial usage.

---

## 📄 License

Distributed under the **Apache License 2.0**. See [`LICENSE`](LICENSE) for complete terms. Feel free to use, modify, and deploy within your homelab or organization!
