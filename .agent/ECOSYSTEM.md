# Multi-Repository Ecosystem Topology & Contracts (ECOSYSTEM.md)

> 🎯 **Purpose:** Canonical source of truth for topology, sibling services, shared contracts, and cross-repo boundaries in the homelab observability ecosystem.
>
> ⚠️ **Mandatory Rules for the Agent:**
> 1. You MUST NOT break active log ingestion contracts or stream header definitions consumed by sibling containers without an expand/contract deprecation period.
> 2. You MUST NOT attempt to directly inspect or mutate files outside this repository directory.
> 3. You MUST mock or isolate external service interactions in local automated tests.

---

## 1. Repository Topology Matrix

| Repository / Node | Role / Responsibility | Relationship | Location / Repository URL | Owner / Team |
| :--- | :--- | :---: | :--- | :--- |
| **`infra-victoria-logs`** *(Current)* | Central log ingestion, indexing (LogsQL), MCP server, and alerts | `Self` | `https://github.com/ye-sandbox/infra-victoria-logs` | Homelab / Observability Lead |
| `clipflow-extension` | Satellite Chrome Extension emitting application client logs | `Downstream (Log Shipper)` | `https://github.com/ye-sandbox/clipflow-extension` | Frontend Team |
| `live-screen` | Satellite media & stream processor emitting high-throughput container logs | `Downstream (Log Shipper)` | `https://github.com/ye-sandbox/live-screen` | Media Team |
| `sinergia` | Core backend domain services running in sibling Docker Compose networks | `Downstream (Log Shipper)` | `https://github.com/ye-sandbox/sinergia` | Backend Team |
| `proxmox-host` | Virtualization host emitting system journal and kernel events via Syslog UDP | `Upstream (Source)` | Baremetal / Proxmox VE node | SysAdmin / SRE |
| `ai-agent-runtimes` | Antigravity / Claude Code / Cursor agents querying logs via MCP | `Consumer (Analyst)` | Local Developer Workstation & Host Daemons | AI Platform Team |

*(Relationships: `Self` [this repository], `Upstream (Source)` [delivers telemetry to this repo], `Downstream (Log Shipper)` [emits application logs to this repo], `Consumer (Analyst)` [queries logs via MCP/HTTP])*

---

## 2. Shared Contracts & Source of Truth

- **Log Ingestion Contract (Docker Engine):**
  - Containers log to stdout/stderr in NDJSON format with root `message`/`level`/`service` attributes.
  - Collector reads `/var/run/docker.sock` (read-only), auto-extracts container labels and names.
- **Log Ingestion Contract (HTTP Ingest):**
  - Endpoint: `POST http://<vector-host>:8686/logs`
  - Content-Type: `application/json` (single event or newline-delimited JSON)
  - Required payload attributes: `service`, `message` (or `msg`), `level`.
- **Syslog UDP Contract:**
  - Endpoint: `udp://<vector-host>:5140` (RFC 3164 / RFC 5424).
- **VictoriaLogs Storage & Stream Header Contract:**
  - Canonical Header: `VL-Stream-Fields: "host,container_name,service,stream"`
  - High-cardinality values (`request_id`, `userId`, `url`) MUST NOT be injected into stream fields; they remain in event fields.
- **MCP Server Protocol:**
  - Protocol: Model Context Protocol (JSON-RPC 2.0). Zero third-party dependencies (`mcp/server.py`).
  - Transports: `stdio` (stdin/stdout) and `sse` (`GET /sse` + `POST /messages?sessionId=...` via `--sse PORT`).

---

## 3. Cross-Repo Interfaces Catalog

### A. Consumed by this Repository (Upstream Dependencies & Ingestion)

| Source / Client | Protocol / Transport | Target Endpoint / Port | Contract / Payload | Fallback / Blast Radius |
| :--- | :---: | :--- | :--- | :--- |
| `Docker Engine` | Unix Domain Socket | `/var/run/docker.sock:ro` | Docker Events & Container stdout/stderr | Local disk queue buffer (`vector_data`) |
| `Host / Proxmox` | Syslog (UDP) | `5140/udp` | RFC 3164 / 5424 Syslog payloads | Best-effort UDP delivery |
| `Satellite Apps` | HTTP (POST) | `8686/tcp` (`/logs`) | NDJSON or JSON payload | HTTP 400 on malformed JSON; buffer retry |

### B. Exposed by this Repository (Downstream Consumers & Interfaces)

| Route / Tool | Consumer(s) | Payload / Schema | Breaking Change Risk | Deprecation Policy |
| :--- | :--- | :--- | :---: | :--- |
| `MCP Tools (9 tools)` | AI Agents (`Cursor`, `Claude Code`, `Antigravity`) | JSON-RPC 2.0 MCP schema | **HIGH** | 2 release cycles with backwards compatibility |
| `HTTP /select/logsql/query` | Grafana, VMUI, Operators | VictoriaLogs LogsQL NDJSON stream | **HIGH** | Pinned to VictoriaLogs upstream compatibility |
| `POST /alerts` | Webhooks / Telegram / ntfy | Alert JSON payload via `alert-bridge` | **MEDIUM** | Graceful schema fallback |

---

## 4. Blast Radius & Contract Evolution Rules

1. **Additive-First (Expand / Contract):**
   - NEVER alter canonical stream headers (`VL-Stream-Fields`) without updating `skills/victorialogs-integration/SKILL.md` and verifying impact on existing storage index shards.
   - When adding fields to MCP tool signatures, always provide sensible defaults to maintain compatibility with existing agent prompts.
2. **Hermetic Testing & Zero Cross-Repo Mutation:**
   - Automated tests (`test_mcp_error_enricher.py`, `tests/vector/*.yaml`) MUST NOT require live remote network access.
   - Vector VRL tests use deterministic native unit testing (`vector test`).
3. **Cross-Repo Task Sequencing:**
   - When logging formats change across satellite services:
     1. `infra-victoria-logs` updates VRL transforms to accept both legacy and new formats.
     2. Satellite repositories update their logging serializers.
     3. Remove legacy transform handling only after all containers run the new format.
