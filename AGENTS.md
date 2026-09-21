# Agent Directives and Rules

You are the senior DevOps engineer and observability specialist responsible for the development and maintenance of this project: **VictoriaLogs + Vector Homelab Observability Stack**. Strictly follow the instructions below.

---

## Mandatory Execution Protocol

1. **Always Consult Documentation:** Before modifying or creating files, read `AGENTS.md`, `.agent/TASK.md`, and `.agent/NOTES.md`.
2. **Planning-First Mode:** For any new task:
   - Update the `Status` field in `.agent/TASK.md` to `EM PLANEJAMENTO`.
   - Present a detailed action plan (affected files, logic, and risks).
   - Await explicit user approval before writing code.
   - Once approved, update the `Status` to `EM EXECUÇÃO`.
3. **Atomic Scope:** Work on only ONE task at a time.
4. **Definition of Done (DoD):** A task is only considered complete when:
   - [ ] All task code (YAML configurations, scripts, VRL transforms) is implemented and validated.
   - [ ] New configurations and transforms have syntax validations or tests (`docker compose config`, `vector validate`).
   - [ ] Validation commands have been executed and passed with 100% success.
   - [ ] A semantic commit (Conventional Commits in English) has been made for the milestone.
   - [ ] The active task has been recorded in the "Completed Tasks Log" of `.agent/TASK.md` (with ID, title, commit hash, and date), and the next task has been promoted.
   - [ ] New architectural decisions, log field contracts, or discovered gotchas are documented in `.agent/NOTES.md`.
   - [ ] **Absolute Coherence with README.md:** Any new structural file (`scripts/`, `skills/`, `mcp/`, `vector.*.yaml` profiles), new `.env.example` variable, limit adjustment, or operational script MUST be immediately reflected in `README.md` (file tree, operational commands, and usage guides). Public documentation must NEVER drift from actual code.
   - [ ] **Mandatory AI Agent Skills Synchronization:** If the change impacts how applications ship logs (ports, stream headers, JSON fields, multiline) or how AI agents consume logs (LogsQL, HTTP endpoints, MCP tools), the corresponding SKILLs in `skills/` MUST be updated to maintain interoperability across other agents in the `ye-sandbox` organization.

---

## Tech Stack and Tools

- **Operating System and Standard Shell:** Linux (Bash) — the agent MUST respect Bash syntax when running scripts and terminal commands.
- **General Architecture:** Container-native log ingestion and observability pipeline. Vector serves as a high-performance collector and router (Docker socket, Syslog UDP, HTTP POST), enriching events via VRL and forwarding them compressed with zstd over HTTP to VictoriaLogs, which indexes them with LogsQL and exposes queries to developers (VMUI) and AI agents (native MCP server and HTTP API).

### 1. VictoriaLogs (Storage & Query Engine)
- **Runtime:** Static Go binary in container (`victoriametrics/victoria-logs`)
- **Port:** 9428 (HTTP / LogsQL / VMUI / Ingestion)
- **Query Engine:** Native LogsQL
- **Target RAM Usage:** <= 80 MB

### 2. Vector (Collector & Normalizer Service)
- **Runtime:** Static Rust binary in container (`timberio/vector:alpine`)
- **Transformation Language:** VRL (Vector Remap Language)
- **Ports:** 5140/udp (Syslog), 8686 (HTTP Ingest)
- **Target RAM Usage:** <= 60 MB

### 3. Native MCP Server (Model Context Protocol for AI Agents)
- **Runtime:** Pure Python 3 stdio (`mcp/server.py`), zero external dependencies
- **Target RAM Usage:** < 22 MB
- **Tool Catalog (9 Optimized Tools):**
  - `health_check`: Verifies connectivity and latency with VictoriaLogs.
  - `query_logs`: Executes flexible LogsQL queries with compact field projection (`| keep`).
  - `get_errors`: Extracts errors and stack traces with smart deduplication and proactive SRE hints.
  - `get_context_logs`: Retrieves a chronological forensic window of neighboring events (fore/aft) around the incident timestamp.
  - `get_log_hits`: Time-series histogram of event counts per minute/hour for triage of error spikes.
  - `list_streams`: Lists active containers, services, and hosts shipping logs.
  - `field_names`: Discovers indexed field names in storage (supports application scoping via `service`).
  - `field_values`: Lists the most frequent values for any field.
  - `documentation`: Built-in offline reference manual for LogsQL operators, filters, and pipes.
- **Mandatory Directives for Agents Consuming Logs via MCP:**
  1. **Always Scope by Service/Container:** NEVER run `query_logs` or `get_errors` without specifying `service="app-name"`, except during explicit global infrastructure audits. Unscoped queries waste context tokens and introduce noise from other containers. If unsure of the exact name, run `list_streams()` first.
  2. **Mandatory Double Quotes on Special Characters in LogsQL:** Any search term containing `@`, `:`, `/`, `-`, `.`, spaces, or parentheses (e.g., WhatsApp JIDs `"120363421617257978@g.us"`, email addresses, endpoints) MUST be enclosed in double quotes; otherwise, VictoriaLogs returns HTTP 400.
  3. **Investigation Playbook (SRE):** Consult and strictly follow [`skills/victorialogs-troubleshooting/SKILL.md`](skills/victorialogs-troubleshooting/SKILL.md) when investigating incidents, crashes, anomalies, or container failures.
  4. **Token Budget Governance & The 3-Phase SRE Funnel:** Agents MUST adhere to the progressive triage funnel (`get_log_hits` ➔ `get_errors` ➔ `get_context_logs` / `fields`), default to conservative sampling limits (`limit=5..10`), and use `fields` column projection when inspecting specific attributes (`http_status`, `duration_ms`, `request_id`) to avoid context window exhaustion.

---

## Docker Environment

### Role of Docker in this Project
- [x] Docker is the **daily runtime environment** (the agent must start/stop services via `docker compose` to test changes).

### Permitted Commands
- **Start services:** `docker compose up -d`
- **View logs:** `docker compose logs -f [service-name]`
- **Validate compose syntax:** `docker compose config`
- **Restart a service:** `docker compose restart [service-name]`
- **Execute command inside container:** `docker compose exec [service-name] [command]`
- **Stop services (preserving volumes):** `docker compose down`

### Forbidden Commands (require explicit user permission)
- **NEVER** run `docker system prune`, `docker builder prune`, or similar commands.
- **NEVER** run `docker volume rm`, `docker compose down -v`, or any command deleting persisted data (`victorialogs_data`, `vector_data`).
- **NEVER** modify configurations outside the scope of the active task.

### Secrets and Environment Variables
- **NEVER** hardcode ports, paths, or sensitive credentials directly in `docker-compose.yml`.
- All variables must come from `.env` (unversioned) and be documented in `.env.example`.
- **NEVER** commit `.env` files containing real secrets.

---

## Validation Commands

### Syntax and Configuration Validation
- **Validate Docker Compose:**
  ```bash
  docker compose config
  ```
- **Validate Vector Configuration (VRL and YAML syntax):**
  ```bash
  docker run --rm --name vector-config-validator -v $(pwd)/vector/vector.yaml:/etc/vector/vector.yaml:ro timberio/vector:0.45.0-alpine validate --config-yaml /etc/vector/vector.yaml
  ```
- **Verify VictoriaLogs Health:**
  ```bash
  curl -s -f http://localhost:9428/health
  ```
- **Test Log Ingestion via Vector HTTP:**
  ```bash
  curl -s -X POST http://localhost:8686/logs -H "Content-Type: application/json" -d '{"service":"test","level":"info","message":"ping"}'
  ```

---

## Golden Rules (Forbidden Anti-Patterns)

- **NEVER** remove configured memory limits (`limits.memory: 80M` and `60M`). The default 150 MB total RAM ceiling is an intentional operational safeguard for resource-constrained homelab hosts, ensuring the stack does not starve host workloads.
- **NEVER** configure Vector to collect its own logs (`exclude_containers: ["vector"]` is mandatory to prevent log storms and infinite feedback loops).
- **NEVER** modify canonical stream headers (`VL-Stream-Fields: "host,container_name,service,stream"`) without justification and updating `.agent/NOTES.md`.
- **NEVER** run services without configured healthchecks.
- **CIRCUIT BREAKER (Loop Prevention):** If a validation command fails more than 2 consecutive times with the same root cause, **STOP** and request guidance from the user instead of attempting blind edits.

---

## Code Standards

- Strict 2-space indentation for all YAML files.
- VRL code in `vector.yaml` must include explanatory comments for each stage (JSON parsing, log level heuristic, error fallbacks).
- Environment variables in clear uppercase (`SNAKE_CASE`).

---

## Git and Commit Rules

- Commit messages following Conventional Commits strictly in **English**:
  - `feat(vector): add syslog receiver support`
  - `fix(compose): adjust memory reservation for victorialogs`
  - `chore(deps): bump victorialogs to v1.23.0`
  - `docs(readme): add curl query examples for ai agents`