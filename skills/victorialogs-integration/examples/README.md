# Canonical Logging Examples and Templates (VictoriaLogs + Vector)

This directory contains plug-and-play code templates ready for use across `ye-sandbox` organization projects.

Each example strictly implements the canonical contract expected by the **VictoriaLogs + Vector** pipeline:
- **Pure NDJSON:** exactly 1 JSON object per line on `stdout`, without intermediate line breaks or *pretty* formatting.
- **Base Canonical Fields:** `timestamp` (ISO-8601 UTC), `level` (lowercase), `service`, `app`, `env`, `message`.
- **Correlation Canonical Fields:** `trace_id`, `request_id`, `http_status`, `duration_ms` at the root level for direct filtering in LogsQL (`http_status:>=500`, `duration_ms:>1000`).
- **Exception Handling:** stack traces serialized inside `stack_trace` or in the same event record, without emitting extra unattached lines.

---

## 📂 Available Templates

### 1. [Python with Loguru](./python-loguru) *(Recommended for modern Python / FastAPI)*
- Uses the `loguru` library.
- Custom sink formatting events according to the canonical contract.
- Native context binding via `logger.bind(...)` and exception capture via `logger.exception(...)`.
- See: [`python-loguru/logger.py`](./python-loguru/logger.py) and [`python-loguru/example_usage.py`](./python-loguru/example_usage.py).

### 2. [Python Standard Library](./python-stdlib) *(Zero dependencies)*
- Uses Python's native `logging` library.
- Custom `VictoriaLogsJsonFormatter`.
- Ideal for lightweight scripts, CLI utilities, or microservices without third-party dependencies.
- See: [`python-stdlib/logger.py`](./python-stdlib/logger.py).

### 3. [Node.js with Pino](./nodejs-pino) *(Recommended for Node / TypeScript)*
- Uses high-performance `pino`.
- Configured without `pino-pretty` for production.
- Child logger support (`logger.child(...)`) for request tracing.
- See: [`nodejs-pino/logger.js`](./nodejs-pino/logger.js) and [`nodejs-pino/example.js`](./nodejs-pino/example.js).

### 4. [Go with `slog`](./go-slog) *(Native Go 1.21+)*
- Uses the Go standard library `log/slog` package.
- `ReplaceAttr` configured for compatibility with the VictoriaLogs schema.
- See: [`go-slog/main.go`](./go-slog/main.go).

---

## 🚀 How to test locally

To verify that a script emits valid NDJSON accepted by the collector:

```bash
# Python Stdlib test
python3 python-stdlib/logger.py | python3 -c "import sys, json; [json.loads(line) for line in sys.stdin]; print('NDJSON validated!')"

# Python Loguru test (requires pip install loguru)
python3 python-loguru/example_usage.py | python3 -c "import sys, json; [json.loads(line) for line in sys.stdin]; print('NDJSON validated!')"
```
