---
name: victorialogs-integration
description: Integrates ye-sandbox organization applications into the VictoriaLogs + Vector pipeline. Use when creating or modifying logging, docker-compose, stdout JSON, Proxmox syslog, or HTTP POST to Vector. Defines NDJSON contract, canonical fields, stream fields, and anti-patterns.
---

# VictoriaLogs Integration Guide (for AI Agents)

This skill guides AI agents when developing, configuring, or refactoring applications across the `ye-sandbox` organization so their logs are captured, normalized, and indexed flawlessly by the **VictoriaLogs + Vector** pipeline.

Canonical source: `ye-sandbox/infra-victoria-logs/skills/victorialogs-integration`. Do not copy this file to other repositories — update it here and point to this skill in the application's `AGENTS.md`. In Cursor, auto-discovery is enabled via a symlink in `~/.cursor/skills/` pointing to this directory.

---

## 🏗️ How Ingestion Works

```text
[ Applications / Containers / Scripts ]
                │
                ▼ (Docker socket / Syslog UDP :5140 / HTTP POST :8686/logs)
         ┌─────────────┐
         │   VECTOR    │  <- Normalizes VRL, aggregates multiline, compresses (zstd)
         └──────┬──────┘
                │ HTTP POST (:9428/insert/jsonline)
                ▼
      ┌───────────────────┐
      │   VICTORIALOGS    │  <- Compresses and indexes internally (not a JSON dump)
      └───────────────────┘
```

JSON is the application's **emission** format (stdout or POST). It is not the storage format on disk: Vector ships NDJSON compressed with zstd; VictoriaLogs stores logs in its proprietary LSM-tree engine. Never "export a JSON file to the database".

---

## 📜 Canonical Fields Contract

Every application should preferably emit **one JSON object per line (NDJSON)** containing:

| Field | Type | Populated By | Description |
|---|---|---|---|
| `timestamp` | `string` ISO-8601 UTC | App (fallback: Vector `now()`) | E.g. `2026-09-03T15:00:00.000Z` |
| `level` | `string` lowercase | App | `debug`, `info`, `warn`, `error` |
| `service` | `string` | App (fallback: `container_name`) | Logical name: `auth-api`, `billing-worker` |
| `app` | `string` | App (fallback: copies `service`) | Repository/service identifier |
| `env` | `string` | App (fallback: `production`) | `production` or `development` |
| `message` | `string` | App | Main event text |
| `trace_id` | `string` optional | App | Distributed trace ID (`traceId`/`trace_id`) |
| `request_id` | `string` optional | App | Request/transaction ID (`requestId`/`correlation_id`) |
| `http_status` | `int` optional | App | HTTP response status code (`statusCode`/`status`) |
| `duration_ms` | `float`/`int` optional | App | Request latency/duration (`duration`/`latency_ms`) |
| `stack_trace` | `string` optional | App | Traceback with `\n` in the same event |
| `context` / extras | top-level fields | App | `userId`, etc. — **never** converted to stream |

Vector also injects `host`, `container_name`, and `stream` (`stdout` / `stderr` / `syslog` / `http`), in addition to automatically promoting `trace_id`, `request_id`, `http_status`, and `duration_ms` to the root level. If the message is valid JSON, the original parsed payload is stored in `structured`.

> **Plain text:** if an application does not emit JSON, Vector infers `level` via regex (`error`, `warn`, `debug`) and uses the container name as `service`. This works, but LogsQL queries and MCP tools (`get_errors`, filtering by `service`) become less effective. Always prefer structured JSON in applications; **do not** force JSON on Proxmox host syslog.

---

## 📐 How to Emit JSON (and What NOT to Do)

### Mandatory
- **One line = one event.** `json.dumps(obj)` / `pino` / `slog JSONHandler` write one object per line. Never use `JSON.stringify([e1, e2], null, 2)` or multi-line pretty-printed JSON: Vector performs `parse_json` on every line of stdout.
- **`message` at the root of the object.** Do not bury log text inside `data.msg` or deeply nested objects without a root `message`/`msg` field.
- **`level` in lowercase** (`error`, not `ERROR`). VRL automatically applies `downcase` during JSON parsing.

### Stream Fields vs Event Fields
Canonical sink header: `VL-Stream-Fields: "host,container_name,service,app,env,stream"`.

- **Allowed as stream dimensions:** stable source identity (`service=auth-api`, `env=production`).
- **NEVER use as stream fields:** `userId`, `request_id`, WhatsApp JID, URL, email, file path. These are **event fields** (or inside `context`). High stream cardinality degrades indexing performance on limited Mini PC hardware. Query them via LogsQL on the field itself (`"1203…@g.us"`, `userId:123`) instead of spawning a new stream.

### Stack Traces
- **JSON:** a single event. Place tracebacks inside `message` (with `\n`) or in `stack_trace`. Vector's multiline aggregator **does not** stitch together fragmented JSON lines. Each NDJSON line (`{...}`) is treated as an independent event; multiline mode is configured as `continue_through` (not `halt_before`) to prevent rapid bursts from merging multiple JSON objects into a corrupted `_msg`.
- **Plain text (indented stdout):** Vector (`mode: continue_through`, `condition_pattern: '^[\s]'`) merges lines starting with spaces/tabs into the preceding line. Python/Java/Go panics with indentation become a single unified event. Unindented traceback lines at column 0 become disjointed events.

### What NOT to Emit (or Not in this Format)
- **Host syslog / rsyslog / journald:** send via UDP `:5140`. Do not convert Proxmox journald into JSON.
- **Healthchecks and pings** (`GET /health`, `/ping`, `/ready`, kube-probe) in HDD storage profile: Vector **drops** them at the edge (unless the line contains `error`/`fail`/`warn`). Do not rely on ping events for mechanical disk audits.
- **Pretty colors / ANSI escapes:** set `NO_COLOR=1`. In Node.js, **never** use `pino-pretty` (or pretty transport) in production containers.

---

## 🐳 Pattern 1: Docker Containers via Docker Compose

When creating or editing `docker-compose.yml` for any project:

```yaml
services:
  my-service:
    image: my-image:latest
    container_name: my-service           # Vector uses container_name as service fallback
    environment:
      LOG_FORMAT: "json"                 # If supported by your application
      NO_COLOR: "1"                      # Disables ANSI colors that pollute logs
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

`logging.driver: json-file` is Docker's **daemon logging driver**, not the application output format. The application must still output valid JSON to stdout.

---

## 🐍 Pattern 2: Python Applications (`py-*`)

For Python microservices and scripts in `ye-sandbox`, production-ready templates are available in [`skills/victorialogs-integration/examples/`](./examples/):
- **Loguru (Recommended for FastAPI/modern scripts):** [`examples/python-loguru/`](./examples/python-loguru/)
- **Standard Library (Zero dependencies):** [`examples/python-stdlib/`](./examples/python-stdlib/)

### Option A: With `loguru` (Recommended)
Configure a custom sink to guarantee canonical NDJSON without raw linebreaks in stack traces:

```python
import json, os, sys
from datetime import datetime, timezone
from loguru import logger

logger.remove()
CANONICAL = {"trace_id", "request_id", "http_status", "duration_ms", "user_id"}

def _sink(msg):
    rec = msg.record
    dt = rec["time"].astimezone(timezone.utc)
    event = {
        "timestamp": dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
        "level": rec["level"].name.lower(),
        "service": rec["extra"].get("service", os.getenv("SERVICE_NAME", "my-python-app")),
        "app": rec["extra"].get("app", rec["extra"].get("service", os.getenv("SERVICE_NAME", "my-python-app"))),
        "env": rec["extra"].get("env", os.getenv("ENV", "production")),
        "message": rec["message"],
    }
    if rec["exception"]:
        event["stack_trace"] = msg.format().strip()
    for k, v in rec["extra"].items():
        if k in CANONICAL:
            event[k] = v
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()

logger.add(_sink, format="{message}")

# Usage with tracing and metrics:
req_log = logger.bind(trace_id="tr-123", request_id="req-456")
req_log.bind(http_status=200, duration_ms=45.2).info("Request processed successfully")
```

### Option B: With Standard Library (`logging`)
```python
import json, logging, os, sys
from datetime import datetime, timezone

class VictoriaLogsJsonFormatter(logging.Formatter):
    def format(self, record):
        dt = datetime.fromtimestamp(record.created, tz=timezone.utc)
        event = {
            "timestamp": dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
            "level": record.levelname.lower(),
            "service": getattr(record, "service", os.getenv("SERVICE_NAME", "my-python-app")),
            "app": getattr(record, "app", getattr(record, "service", os.getenv("SERVICE_NAME", "my-python-app"))),
            "env": getattr(record, "env", os.getenv("ENV", "production")),
            "message": record.getMessage(),
        }
        if record.exc_info:
            event["stack_trace"] = self.formatException(record.exc_info)
            event["message"] += "\n" + event["stack_trace"]
        for key in ("trace_id", "request_id", "http_status", "duration_ms"):
            if hasattr(record, key):
                event[key] = getattr(record, key)
        return json.dumps(event, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(VictoriaLogsJsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger("app")
logger.info("Server started", extra={"request_id": "abc", "trace_id": "xyz"})
```

---

## 🟨 Pattern 3: Node.js / TypeScript Applications (`js-*`)

Use `pino` with pure JSON output. **Never** configure `pino-pretty` in production.
Complete template available at [`examples/nodejs-pino/`](./examples/nodejs-pino/).

```typescript
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  formatters: {
    level: (label) => ({ level: label }),
  },
  base: {
    service: process.env.SERVICE_NAME || 'my-node-app',
    app: process.env.SERVICE_NAME || 'my-node-app',
    env: process.env.NODE_ENV === 'development' ? 'development' : 'production',
  },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
});

// Log with request correlation
logger.child({ request_id: 'req-123', trace_id: 'tr-abc' }).info(
  { http_status: 200, duration_ms: 15.4 },
  'Request completed'
);
```

---

## 🔵 Pattern 4: Go Applications

Use the standard library `log/slog` package with `JSONHandler`.
Complete template available at [`examples/go-slog/`](./examples/go-slog/).

```go
package main

import (
    "log/slog"
    "os"
    "strings"
    "time"
)

func main() {
    handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
            switch a.Key {
            case slog.MessageKey:
                a.Key = "message"
            case slog.LevelKey:
                a.Key = "level"
                a.Value = slog.StringValue(strings.ToLower(a.Value.String()))
            case slog.TimeKey:
                a.Key = "timestamp"
                a.Value = slog.StringValue(a.Value.Time().UTC().Format(time.RFC3339Nano))
            }
            return a
        },
    }).WithAttrs([]slog.Attr{
        slog.String("service", "my-go-service"),
        slog.String("app", "my-go-service"),
        slog.String("env", "production"),
    })

    logger := slog.New(handler)
    logger.Info("Transaction completed",
        slog.String("trace_id", "tr-go-1"),
        slog.String("request_id", "req-go-1"),
        slog.Int("http_status", 200),
        slog.Float64("duration_ms", 22.5),
    )
}
```

---

## 📡 Pattern 5: Shell Scripts, Crons, and Microservices (Direct HTTP POST)

If an application runs outside Docker (e.g. backup script on Proxmox host):

```bash
send_log() {
  local level="${1:-info}"
  local message="${2}"
  local service="${3:-my-bash-script}"
  local vector_host="${VECTOR_HOST:-localhost}"
  local vector_port="${VECTOR_HTTP_PORT:-8686}"

  curl -s -X POST "http://${vector_host}:${vector_port}/logs" \
    -H "Content-Type: application/json" \
    -d "{
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"service\": \"${service}\",
      \"app\": \"${service}\",
      \"env\": \"production\",
      \"level\": \"${level}\",
      \"message\": \"${message}\"
    }" > /dev/null || true
}

send_log "info" "Starting ZFS snapshot on tank pool"
send_log "error" "Failed to replicate remote dataset"
```

The POST payload is already a JSON object (not an array). One POST = one event.

---

## 🖥️ Pattern 6: Proxmox VE Hosts / LXCs / Network Switches (Syslog UDP)

To forward logs from a Proxmox node (`journald` / `rsyslog`) **without** converting to JSON:

1. Create `/etc/rsyslog.d/60-vector.conf`:
   ```text
   *.* @<MINI_PC_IP>:5140
   ```
2. Restart rsyslog:
   ```bash
   systemctl restart rsyslog
   ```

---

## ✅ AI Agent Checklist When Integrating an Application

Before completing any integration task:

- [ ] Application emits **NDJSON** on `stdout`/`stderr` (one object per line), without colors (`NO_COLOR=1`) and without pretty-printers.
- [ ] Root fields present: `timestamp`, lowercase `level`, `service` (and preferably `app`/`env`), `message`.
- [ ] High-cardinality IDs (`userId`, `request_id`, JID, URL) are event fields, never stream dimensions.
- [ ] JSON stack traces are within the same event (`message`/`stack_trace` with `\n`); plain text remains indented for Vector's multiline aggregator.
- [ ] Host syslog forwards to UDP `:5140`; scripts outside Docker use HTTP POST `:8686/logs`.
- [ ] Verified in VictoriaLogs (adjust host if stack is not on localhost):
  ```bash
  curl -s -G "http://localhost:9428/select/logsql/query" \
    --data-urlencode 'query=_stream:{service="my-service"} AND _time:5m'
  ```
