---
name: victorialogs-troubleshooting
description: SRE and incident investigation playbook for AI agents to diagnose errors, crashes, and metrics in VictoriaLogs via MCP and LogsQL with maximum token efficiency and zero context loss.
---

# VictoriaLogs Troubleshooting & Investigation Playbook (for AI Agents)

This skill guides AI agents (Claude, Antigravity, Cursor, Roo Code) to operate as **SRE specialists** diagnosing errors, crashes, and anomalies across homelab services using the **VictoriaLogs + Vector** stack.

If the user wants to **record an issue for later** (not fix it immediately), use the `github-bug-issue` skill: open an issue in the owning repo's GitHub with a VictoriaLogs pointer, without making it the active task.

---

## 🎯 Incident Investigation Protocol & The 3-Phase SRE Funnel

When the user reports an issue ("the API crashed", "the worker stopped", "I'm getting 500 errors"), AI agents MUST follow the progressive **3-Phase SRE Triage Funnel** to preserve context tokens:

```text
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Step 0: Target Service Identification                                  │
  │ Inspect docker-compose.yml or run list_streams(time_range="1h")        │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │ (e.g. service="payments-api")
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Phase 1: Aggregate Time & Volume Triage (get_log_hits)                 │
  │ • Zero log bodies fetched (0 token waste on raw payloads)              │
  │ • Pinpoint exact start of spike and error rate: step="1m" or "5m"      │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │ (Discovered incident at 14:18:41Z)
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Phase 2: Deduplicated Error Isolation (get_errors)                     │
  │ • Conservative sampling: limit=5..10                                   │
  │ • Deduplicates repetitive error storms: displays [42x] count           │
  │ • Preserves intact root-cause stack trace without noise                │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │ (Isolated traceback: KeyError: 'user_id')
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Phase 3: Forensic Fore/Aft Window or Column Projection                 │
  │ • get_context_logs(target_timestamp="...", window_seconds=10, limit=10)│
  │   Inspect precursor requests marked with 🎯 [TARGET / INCIDENT]        │
  │ • OR query_logs(fields="http_status,duration_ms,request_id", limit=10) │
  │   Ultra-compact column projection via | keep                           │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │ (Identified malformed payload in precursor log)
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Phase 4: Source Code Correlation & Remediation                         │
  │ Read workspace file (e.g. api/routes.py:L42) -> Propose atomic fix     │
  └────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **SRE Golden Rule:** NEVER execute generic queries without specifying `service="app-name"`. Global queries pull noise from other homelab containers and waste context tokens unnecessarily. If you don't know the exact service name, run `list_streams()` first.
>
> 💡 **Default Telemetry Suppression:** In global searches without `service`, query tools (`query_logs`, `get_errors`, `get_context_logs`, `get_log_hits`) automatically exclude high-frequency telemetry streams (`docker-stats` and `cadvisor`). If you explicitly need to inspect container CPU/RAM stats or cAdvisor logs, specify `service="docker-stats"` or `service="cadvisor"`.

---

## 🛠️ Complete MCP Tool Catalog

The repository's native MCP server (`mcp/server.py`) exposes **9 optimized tools**, designed to deliver to the AI exactly what it needs to resolve bugs without wasting tokens on irrelevant metadata:

### 1. `health_check`
- **When to use:** At the start of a session to verify connectivity with VictoriaLogs.
- **Parameters:** `{}`

### 2. `get_log_hits` (Phase 1: Zero-Payload Time Triage)
- **When to use:** To answer *"when did the problem start?"* or *"how many failures occurred per minute?"* without pulling raw log payloads.
- **Parameters:**
  - `query`: `_stream:{service="payments"} AND level:error`
  - `time_range`: `"30m"`, `"1h"`, `"6h"`, `"24h"`
  - `step`: `"1m"`, `"5m"`, `"1h"`
  - `max_buckets`: `15` (default: `15`, displays most recent buckets; increase if a wider timespan is needed)

### 3. `get_errors` ⭐ (Phase 2: Primary for Debugging)
- **When to use:** Extracts errors and multiline stack traces formatted in code blocks without `info` log noise.
- **Smart Deduplication:** By default (`deduplicate=true`), groups repetitive error storms, displaying occurrence counts and time intervals (`[34x] First: 11:20 | Last: 11:25`), while preserving the full root-cause stack trace.
- **Parameters:**
  - `service`: `"application-name"` (**RECOMMENDED:** always provide your task's target service; only omit for global infrastructure audits)
  - `time_range`: `"30m"`, `"1h"` (default: `"1h"`)
  - `limit`: `5` or `10` (**RECOMMENDED for AI:** `5..10` to conserve context tokens; default: `10`)
  - `deduplicate`: `true` (default) or `false` (for raw sequential list)
  - `full`: `false` (default, truncating giant tracebacks after 1,200 chars) or `true` (100% uncut stack trace)

### 4. `get_context_logs` ⭐ (Phase 3: Forensic Fore/Aft Context)
- **When to use:** After identifying an error via `get_errors()`, use the exact failure timestamp to retrieve the chronological history of immediately preceding and succeeding logs (including `info`, `debug`, etc.), revealing what the user or system was doing right before the crash.
- **Smart Features:** Central incident event is marked with `🎯 [TARGET / INCIDENT]`. Consecutive identical events are automatically collapsed (`(repeats Nx until HH:MM:SS)`).
- **Parameters:**
  - `target_timestamp`: `"2026-09-10T14:18:41Z"` (mandatory, accepts ISO-8601 format)
  - `service`: `"application-name"` (recommended)
  - `window_seconds`: `10` or `15` (default: 15s before and 15s after)
  - `limit`: `10` to `15` (**RECOMMENDED for AI:** `10..15` records; default: `30`)
  - `full`: `false` (default) or `true`

### 5. `query_logs` (Phase 3: Flexible LogsQL & Column Projection)
- **When to use:** Flexible queries using LogsQL (e.g. searching for a `request_id`, user, or free-text term), or auditing tabular metrics.
- **Smart Features:** Strips noisy ANSI escape sequences, collapses consecutive identical records, and projects compact key-value lines when `fields` is specified.
- **Parameters:**
  - `query`: `"120363421617257978@g.us"` or `status:500`
  - `service`: `"application-name"` (**RECOMMENDED:** automatically injects stream partitioning `_stream:{container_name="..."}`)
  - `time_range`: `"1h"`
  - `limit`: `5` or `10` (**RECOMMENDED for AI:** `5..10`; default: `20`)
  - `fields`: `"http_status, duration_ms, request_id"` (**STRONGLY RECOMMENDED for metrics/IDs:** projects columns via `| keep` and renders ultra-compact key-value output, saving >80% tokens)
  - `format`: `"markdown"` (compact default with icons) or `"json"` (raw ndjson)
  - `full`: `false` (default) or `true` (disables truncation of long messages)

### 6. `list_streams` (Phase 0: Service Discovery)
- **When to use:** To discover which containers, services, and hosts are currently sending logs.
- **Parameters:**
  - `time_range`: `"24h"`

### 7. `field_names`
- **When to use:** To inspect indexed field names in VictoriaLogs (e.g. `user_id`, `path`, `status`). Use `service` to isolate fields belonging to a specific container/application and eliminate cross-container noise.
- **Parameters:**
  - `service`: `"app-name"` (optional, recommended when diagnosing a specific service)
  - `time_range`: `"24h"`

### 8. `field_values`
- **When to use:** To list the most frequent existing values of a specific field (e.g. see which `level` or `service` values exist).
- **Parameters:**
  - `field`: `"service"` or `"level"` (mandatory)
  - `time_range`: `"24h"`
  - `limit`: `10` or `20`

### 9. `documentation`
- **When to use:** To inspect LogsQL syntax (filters, pipes, stats) without leaving the chat.
- **Parameters:**
  - `query`: `"stats"`, `"filters"`, `"streams"`, `"pipes"` (or empty for the full guide)

---

## 🪙 Token Budget Governance for AI Agents

Observability operations can consume significant LLM context tokens if handled naively. All AI agents operating within `ye-sandbox` MUST follow these governance principles:

### 1. The Token Cost Hierarchy
| Phase / Tool | Average Token Footprint | Diagnostic Value |
|---|---|---|
| `get_log_hits` | **~50 – 150 tokens** | Immediate time-spike isolation with zero body payload |
| `get_errors(deduplicate=true, limit=5)` | **~300 – 800 tokens** | Distinct root-cause tracebacks with repeat counts |
| `get_context_logs(limit=10)` | **~400 – 900 tokens** | Bounded chronological timeline around failure |
| `query_logs(fields="...", limit=10)` | **~200 – 500 tokens** | Ultra-dense key-value projections without message bloat |
| *Unscoped raw query (`query_logs`, limit=50+)* | *10,000 – 40,000+ tokens* | **PROHIBITED:** Causes context window exhaustion |

### 2. Sampling Limits & Directives
1. **Default to Conservative Limits:** Always query with `limit=5` or `limit=10`. Only expand limits if initial results indicate distinct unseen error classes.
2. **Always Project Columns When Auditing Attributes:** When analyzing HTTP statuses, API latencies, or correlation IDs, pass `fields="http_status,duration_ms,request_id"`. This eliminates verbose log messages and repetitive JSON envelopes.
3. **Keep Deduplication Active:** Never set `deduplicate=false` in `get_errors` unless the exact physical arrival order of every single error occurrence is strictly required.
4. **Scope by Service Immediately:** Never execute queries without `service="..."` unless performing an explicit cross-cluster infrastructure audit.

### 3. Anti-Patterns to Avoid
- ❌ **Anti-Pattern 1:** Running `query_logs(query="error", limit=50)` on an issue report. *(Violates Phase 1 & 2; floods context with un-deduplicated noise).*
- ❌ **Anti-Pattern 2:** Requesting `full=true` on initial triage calls. *(Always inspect compact preview first; use `full=true` only if the traceback was cut mid-frame).*
- ❌ **Anti-Pattern 3:** Fetching entire log lines when only auditing latency distribution. *(Use `fields="duration_ms"` or `| stats` aggregations).*

---

## 🧠 Zero Context Loss Guarantee for AI

The MCP compacting logic was engineered by observability practitioners to **never compromise AI diagnostic capability**:

1. **What is discarded (Useless Noise):**
   - Internal Docker Compose labels (`label.com.docker.compose.config-hash`, `label.com.docker.compose.project_dir`, `label.com.docker.compose.version`, etc.).
   - SHA256 image hashes and raw stream IDs (`_stream_id: 000000000000...`).
2. **What is 100% Preserved (Vital SRE Context):**
   - **Error Message & Full Stack Trace:** Exception name, file line (`routes.py:L42`), and full call chain.
   - **Service Identity:** Container (`container_name`), service (`service`), and host (`host`).
   - **Time Dimension:** Exact UTC timestamp, first occurrence, and last occurrence of the incident.
   - **Failure Frequency:** Exact count of how many times the error fired (`[42x occurrences]`).
3. **Escape Hatch (`full=true`):**
   - If a traceback or message is unusually long and the AI needs to inspect truncated trailing characters, simply re-run with `full=true`.

---

## ⚡ LogsQL Cheat-Sheet (Fast Patterns)

### 1. Stream Filters (Indexed in Memory)
```text
_stream:{service="my-backend"}
_stream:{container_name="vector"}
_stream:{host="mini-pc-proxmox"}
```

### 2. Severity & Negation Filters
```text
level:error
level:(error OR warn)
level:error AND NOT "/health"
```

### 3. Phrase & Keyword Searches
```text
"connection refused"
"out of memory" OR "OOMKilled"
timeout AND NOT "keepalive"
```

### 4. Aggregation Pipes & Statistics
Count errors grouped by container in the last hour:
```text
_time:1h AND level:error | stats by (container_name) count() as total | sort by (total) desc | limit 5
```

### 5. Identifiers with Special Characters (WhatsApp JIDs, Emails, URLs)
> ⚠️ **Critical LogsQL Rule:** Any search term containing `@`, `:`, `/`, `-`, `.`, spaces, or parentheses **MUST be enclosed in double quotes** (`"..."`). Otherwise, VictoriaLogs will return an HTTP 400 error (`probably, the whole string must be put into quotes`).

```text
# WhatsApp JID (Groups or Users):
"120363421617257978@g.us"
_stream:{container_name="evolution-api"} AND "120363421617257978@g.us"
exact:"120363421617257978@g.us"
_msg:~"120363421617257978@g.us"

# Emails:
"dev@company.com"

# Endpoints and URLs:
"/api/v1/auth/login"
```

### 5.1. Distributed Tracing & HTTP Metrics (Promoted Fields)
Structured fields automatically extracted to the root level:
```text
# Trace an end-to-end transaction by Gateway ID:
request_id:"req-checkout-98765"

# Trace distributed flow by trace_id:
trace_id:"trace-hex-445566"

# Filter HTTP 5xx failures in a microservice:
_stream:{service="checkout-api"} AND http_status:>=500

# Identify high-latency requests (> 1.5s):
_stream:{service="checkout-api"} AND duration_ms:>1500

# Group total request count by HTTP status code:
_stream:{service="checkout-api"} | stats by (http_status) count() as total
```

### 6. Container Resource Diagnostics (`docker-stats`)
With the `scripts/ship-docker-stats.sh` collector active, point-in-time metrics for CPU, RAM, and Limits reside in stream `service="docker-stats"`:
```text
# Recent resource consumption history for a specific container:
_stream:{service="docker-stats",container_name="my-app"} | sort by (_time) desc | limit 20

# Detect containers with high memory usage (> 85% of allocated limit):
_stream:{service="docker-stats"} AND mem_percent:>85

# Detect CPU usage spikes (> 80% utilization):
_stream:{service="docker-stats"} AND cpu_percent:>80
```

### 7. Crash & OOMKilled Detection (`docker-events`)
With the `scripts/ship-docker-events.sh` collector active, Docker daemon lifecycle events reside in stream `service="docker-events"`:
```text
# Detect all containers that exited with error or OOM:
_stream:{service="docker-events"} AND level:error

# Confirm whether a specific container was OOMKilled:
_stream:{service="docker-events",container_name="my-app"} AND oom_killed:true

# Inspect stop and restart history for a container:
_stream:{service="docker-events",container_name="my-app"} | sort by (_time) desc | limit 10
```

High-cardinality IDs (`userId`, `request_id`, JID, email, URL) are **event fields**, not `_stream` dimensions. Filter them in LogsQL (with double quotes) or via `query_logs`; never request an application to promote these fields to stream headers (`VL-Stream-Fields`). Emission contracts are detailed in `victorialogs-integration`.


