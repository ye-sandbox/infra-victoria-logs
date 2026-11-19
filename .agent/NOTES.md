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

4. **CRITICAL INVARIANT:** NEVER create task-specific headings (e.g., `## [Task XX.Y] Description` or `### [Task XX.Y]`) in `NOTES.md`. Task completion details live in `git log` and `.agent/ARCHIVE.md`. Architectural decisions live in `docs/adr/decisions.md`. In `NOTES.md`, maintain and update ONLY the live tables/lists of active contracts, interfaces, and topology.

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

---

### Multi-Agent Collaboration Contracts

> Canonical 3-tier subagent topology, Tier 2 (`dev-harness`) micro-contracts, worktree isolation, and hermetic sandboxes.

| Role | Interface / Channel | Responsibilities | Boundary & Invariants |
|---|---|---|---|
| **`Lead / Orchestrator`** | `.agent/TASK.md` / Interactive Prompt | Decomposes initiatives into tasks, manages task lifecycle, routes to model/quota tiers, interacts with human. | Sole manager of `TASK.md` and commit log. Does not run parallel worker tasks directly. |
| **`Worker / Implementer`** | Worktree / Target Workspace | Executes atomic code/doc changes strictly adhering to delegated micro-contract (`files_read`, `files_edit`, `verify`). | Restricted exclusively to `files_edit`. Adheres to DoD in `AGENTS.md`. |
| **`Reviewer / Sentinel`** | Diffs / Test Harness (`verify`) | Read-only inspection of diffs against task DoD, regression tests, and security blast radius. | Read-only; reports structured Pass/Fail diagnostic payload. |

#### Worktree Isolation & Dependency Bootstrap Contract

| Element | Protocol / Mechanism | Invariant / Boundary |
|---|---|---|
| **Workspace Provisioning** | `git worktree add -b task-<id> <path> HEAD` | Default ephemeral path (`${TMPDIR:-/tmp}/worktrees/task-<id>`) or `.worktrees/task-<id>` (`.worktrees/` in `.gitignore`). |
| **Dependency Bootstrap** | Fast-Link vs. Isolated-Install | Fast-Link (symlink `node_modules/` or `.venv/`) when `files_edit` has no manifest changes (<50ms, zero-copy). Isolated-Install when manifests change. |
| **Environment Injection** | Copy `.env` / `.env.example` to worktree | Ensures test harness execution without leaking uncommitted tokens or mutating root config. |
| **Teardown & GC** | `git worktree remove --force` + `branch -D` + `prune` | Immediate cleanup post-integration; trap declared in runners to prevent dangling worktree locks. |

#### Project Lifecycle Hooks & Fast-Link Bootstrap Contract

| Hook / Phase | Script Target | Invocation & Contract |
|---|---|---|
| **Fast-Link Bootstrap** | `bootstrap-worktree.sh` | Zero-copy symlinking of `node_modules/` and `.venv/`, `.env` isolation copy, and `.agent/scratch/` provisioning. |
| **Post-Provisioning** | `.agent/hooks/post-worktree-create` | Executed post-bootstrap for test DB seeding, port binding, and ephemeral fixtures. Halts on non-zero exit. |
| **Pre-Verification** | `.agent/hooks/pre-verify` | Executed before `verify` command execution to ensure clean test state and fixture validation. |
| **Post-Teardown** | `.agent/hooks/post-worktree-teardown` | Executed prior to worktree removal (`git worktree remove`) for graceful daemon/resource teardown. |

#### Multi-Account Quota Routing & Failover Contract

| Element | Protocol / Mechanism | Invariant / Boundary |
|---|---|---|
| **Profile Routing Priority** | `select-profile.sh --exclude-current` | Autonomous workers route to secondary accounts with highest quota; active IDE profile reserved for Lead Orchestrator. |
| **Quota Floor Circuit Breaker** | `remaining_fraction <= 0.05` | Immediate disqualification of profiles with <=5% quota; halts execution if all candidate profiles are below floor. |
| **Model Tier Selection** | `default-tier` / `escalation-tier` (mapped via `WORKER_MODEL_DEFAULT_TIER` / `WORKER_MODEL_ESCALATION_TIER`) | Low token footprint default; escalation to `escalation-tier` permitted only for complex architecture or max 1 retry after verification failure. |
| **Cooldown Tracking** | `<profile>/.multigravity/quota-history.jsonl` | 429 rate limit backoff and cooldown persistence to prevent immediate re-dispatch. |
| **Worktree Recovery** | Worktree verify on timeout | Runs `verify` inside worktree on timeout; if code 0 and matches `files_edit`, recovers diff cleanly. |

#### Hermetic Agent Sandbox & Container Isolation Contract

| Element | Protocol / Mechanism | Invariant / Boundary |
|---|---|---|
| **Tier 1 (Bubblewrap)** | `bwrap --unshare-all --ro-bind /usr ...` | Rootless user namespace, read-only system binaries, ephemeral tmpfs `/tmp`, worktree read-write bind, `--die-with-parent`. |
| **Tier 2 (Rootless Container)** | `podman run --read-only --cap-drop=ALL` | Rootless OCI container, read-only rootfs, `no-new-privileges`, memory (2G) and CPU (2.0) limits, tmpfs `/tmp` with `noexec`. |
| **Network Namespacing** | `--unshare-net` / `--network none` | Hermetic air-gap by default; egress permitted exclusively for explicit external API or dependency fetching tasks. |
| **Fallback & Escalation** | `audit-command-security.sh` | Static pre-execution audit for hazardous commands (`sudo`, `/etc` writes, curl pipes) when namespaces unavailable. |

#### LLM Gateway & Virtual Model Routing Contract

| Element | Protocol / Mechanism | Invariant / Boundary |
|---|---|---|
| **API Protocol** | OpenAI v1 (`/v1/chat/completions`, `/v1/models`, `/v1/hydra/models`) | Standard JSON schema, streaming SSE, tool calling via `hydra-llm-router`; discover operator-configured virtual aliases via `/v1/models` or `/v1/hydra/models` with zero provider-specific SDK lock-in. |
| **Virtual Model Routing** | `fast` vs. `deep` | Operator-configured virtual aliases (`fast` default for low-latency <1.5s intent/extractions; `deep` opt-in for complex reasoning/synthesis up to 1M tokens). |
| **Network Isolation** | `hydra_shared_net` (`external: true`) | Co-located sibling containers join `hydra_shared_net` for direct DNS `http://hydra-llm-router:3000/v1` (external hosts use `https://hydra-router.homelab.yegear.dev/v1`). Joining `hydra_router_internal` or legacy `hydra_ai_net` is strictly forbidden. |
| **Client Timeout & Budget** | `LLM_TIMEOUT_SECONDS >= 180` | Minimum 180s timeout for deep reasoning calls; minimum `max_tokens >= 60` on test probes to prevent empty completions caused by reasoning token consumption. |
