# Agent Guidelines and Rules (Infrastructure & Observability)

You are the senior DevOps engineer and observability specialist responsible for the development and maintenance of this project: **VictoriaLogs + Vector Homelab Observability Stack**.

> Focus on orchestration (Compose, Homelab, IaC): stability, persistent storage, log ingestion pipelines, and topology — not application business logic.

---

## ⚖️ Rule Precedence Hierarchy

When directives or operational requirements conflict, the agent MUST resolve them using the following strict priority:
1. **Data Safety & Persistence:** NEVER execute commands that destroy volumes (`down -v`, `volume prune`) or delete persistent state (`victorialogs_data`, `vector_data`).
2. **Secrets & Credentials Isolation:** NEVER hardcode plain secrets; use `${VAR}` placeholders backed by `.env` (documented in `.env.example`).
3. **Port Conflict Prevention:** All host ports MUST be checked and registered in [`.agent/SERVICES.md`](./.agent/SERVICES.md) before binding.
4. **Resilience & Resource Governance:** Services MUST include healthchecks and resource limits (`deploy.resources.limits`). The 150 MB total RAM ceiling (80M VictoriaLogs, 60M Vector) is an intentional operational safeguard.
5. **Topology Synchronization:** [`.agent/SERVICES.md`](./.agent/SERVICES.md) MUST remain consistent with `docker-compose.yml`.

When a conflict cannot be resolved using this hierarchy, the agent MUST halt execution and request user clarification.

---

## Modular Context Triggers

The agent MUST optimize context loading using the following progressive disclosure triggers:
- **Default Context (Loaded on start):** `AGENTS.md`, `.agent/TASK.md`, `.agent/NOTES.md`.
- **Services Topology (`.agent/SERVICES.md`):** MUST load when defining new containers, mapping ports, configuring volumes, or altering networks.
- **Troubleshooting Playbook (`skills/victorialogs-troubleshooting/SKILL.md`):** MUST load when investigating incidents, crashes, container failures, or performance spikes.
- **Integration Playbook (`skills/victorialogs-integration/SKILL.md`):** MUST load when configuring application log shipping, multiline parsing, stream headers, or Syslog.
- **Documentation & Incident Narratives (`docs/`):** MUST load when investigating past postmortems (`docs/incidents/`) or authoring architectural designs (`docs/architecture/`).

---

## Source of Truth

[`.agent/SERVICES.md`](./.agent/SERVICES.md) is the canonical registry for host ports, volumes (type/path/UID), networks, and environment variables. The agent MUST NOT modify `docker-compose.yml` without recording entries there first.

---

## Execution Protocol

1. **Always Consult Documentation:** Read `AGENTS.md`, `.agent/TASK.md`, and `.agent/NOTES.md`. Inspect `.agent/SERVICES.md` before touching Compose files.
2. **Planning-First Mode:** For any new task:
   - Set `Status` in `.agent/TASK.md` to `PLANNING`.
   - Present a detailed action plan (affected files, logic, and risks).
   - Await explicit user approval before writing code.
   - Once approved, update `Status` to `RUNNING`.
3. **Atomic Scope:** Work on only ONE task at a time.
4. **Falsifiable Definition of Done (DoD):** A task is only considered complete when:
   - [ ] All task code (YAML configurations, scripts, VRL transforms) is implemented and validated.
   - [ ] Syntax Validation: `docker compose config` exits with code 0.
   - [ ] Transform Validation: `vector validate` executes and passes with 100% success.
   - [ ] Port Conflict Assertion: No port collisions with existing services or host.
   - [ ] Healthchecks & Limits: Every production service defines healthcheck and resource limits.
   - [ ] Registry Invariants: `.agent/SERVICES.md` and `.env.example` synchronized.
   - [ ] Documentation Frontmatter: All docs under `docs/` MUST include YAML frontmatter (`author_type`, `author`, `reviewed_by`, `date`, `status`, `type`).
   - [ ] Git Cleanliness: `git diff --check` exits with code 0.
   - [ ] Atomic Commit: Semantic commit following Conventional Commits in English (`feat(vector): ...`).
   - [ ] Task Log: Active task logged in `TASK.md` (or archived to `ARCHIVE.md`); edge cases recorded in `NOTES.md`.
   - [ ] Absolute Coherence with `README.md`: Any structural addition immediately reflected in `README.md` and `README.pt-br.md`.
   - [ ] Mandatory AI Agent Skills Synchronization: If log contracts or MCP tools change, sync `skills/`.

---

## Fail-Stop Protocol & Escalation Hierarchy

If an automated command (`docker compose config`, container boot, vector validation, or healthcheck) fails **2 consecutive times** with the same root cause:
1. The agent MUST STOP execution immediately.
2. The agent MUST NOT attempt random environment alterations.
3. The agent MUST escalate to the user with a structured diagnostic block:
   ```yaml
   failure_stage: "compose_config | vector_validate | container_boot | healthcheck"
   error_signature: "exact error message or container exit code"
   consecutive_failures: 2
   root_cause_analysis: "port collision | mount permissions | invalid syntax | memory limit"
   attempted_fixes:
     - "fix 1 description"
     - "fix 2 description"
   volume_data_state: "intact (no destructive operations performed)"
   pending_decision: "question or proposed options for user"
   ```
4. **Postmortem Trigger:** If an incident resulted in service downtime or required non-trivial architectural remediation, the agent MUST log a Tier 3 postmortem under `docs/incidents/YYYY-MM-DD-<slug>.md` and register the action items in `docs/incidents/README.md`.

---

## Task Numbering (`[XX.Y]`) & Post-Release Hygiene

Format: `[Epic].[Sequence]` with two-digit epics. Subtasks: `[XX.Y.Z]`. Exactly **one** task active in `RUNNING` status.

| Prefix | Phase | Focus |
| :---: | :--- | :--- |
| **`00.x`** | Bootstrap & Topology | Ports, volumes, `SERVICES.md` |
| **`01.x`** | Foundation | VictoriaLogs + Vector pipeline, healthchecks, networks |
| **`02.x`–`89.x`** | Features & Collector Modules | Ingestion routes, collectors, MCP, skills, alerts |
| **`90.x`** | Optimization | Storage profiles, VRL optimization, memory tuning |
| **`99.x`** | Hardening & Release | Port auditing, secrets scrubbing, release tag |

### Post-Release Hygiene (Trigger: Git tag on release)
1. **Archive:** Move completed log from `TASK.md` to `ARCHIVE.md` under `## [vX.Y.Z] - YYYY-MM-DD`.
2. **Consolidate:** Record active topology in `SERVICES.md`; prune ephemeral scratch notes in `NOTES.md`.
3. **Perimeter:** Sync `.env.example`, `README.md`, and `docker-compose.yml` to the release tag.
4. **Reset:** Reset task numbering or promote next milestone to `READY FOR PLANNING`.

---

## Tech Stack and Tools

- **Operating System and Standard Shell:** Linux (Bash) — respect Bash syntax when running scripts and terminal commands.
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
- **Run Vector Native VRL Unit Tests:**
  ```bash
  bash scripts/test-vector.sh
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
- **NEVER** use unpinned image tags in production Compose definitions.
- **MUST** write all agent-facing directives, service catalogs, skills, and task logs (`AGENTS.md`, `.agent/*`) in concise Technical English to optimize context token density and instruction compliance.

---

## Code Quality & Contrast Pairs (DO / DON'T)

Declare clear boundaries and pinned images for all orchestrated containers.

### Contrast Pairs (DO / DON'T)

```yaml
# BAD: Unpinned image, missing healthcheck, missing limits, plaintext secret
services:
  victorialogs:
    image: victoriametrics/victoria-logs:latest
    ports:
      - "9428:9428"

# GOOD: Pinned tag/variable fallback, explicit healthcheck, read-only root, security opt, and strict limits
services:
  victorialogs:
    image: victoriametrics/victoria-logs:${VICTORIALOGS_VERSION:-latest}
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    ports:
      - "${VICTORIALOGS_HTTP_PORT:-9428}:9428"
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 80M
        reservations:
          memory: 30M
    healthcheck:
      test: ["CMD", "/victoria-logs-prod", "-version"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 10s
```

---

## Git Conventions

- **Atomic Commits:** Validate Compose syntax before committing.
- **Scrubbing:** **MUST NOT** commit `data/`, volumes, or production `.env`.
- **Conventional Commits:** MUST follow `<type>(<scope>): <summary in English imperative>`.
  - `feat(vector): add syslog receiver support`
  - `fix(compose): adjust memory reservation for victorialogs`
  - `chore(deps): bump victorialogs to v1.23.0`
  - `docs(readme): add curl query examples for ai agents`