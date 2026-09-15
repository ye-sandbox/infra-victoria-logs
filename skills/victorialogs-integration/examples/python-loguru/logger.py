"""
Plug-and-Play Logger with Loguru for VictoriaLogs + Vector.

Strictly emits 1 JSON object per line (NDJSON) on stdout without intermediate line breaks,
with canonical support for ISO-8601 UTC timestamp, lowercase level, app, env, service,
correlation fields (trace_id, request_id, http_status, duration_ms), and serialized stack_trace.
"""

import json
import os
import sys
from datetime import datetime, timezone
from loguru import logger

# Disable Loguru's default colored handler
logger.remove()

SERVICE_NAME = os.getenv("SERVICE_NAME", os.getenv("APP_NAME", "app-python"))
ENV_NAME = os.getenv("ENVIRONMENT", os.getenv("ENV", "production"))

# Canonical correlation fields promoted to root level
CANONICAL_FIELDS = {
    "trace_id",
    "request_id",
    "http_status",
    "duration_ms",
    "user_id",
    "ip",
}


def _victorialogs_sink(message):
    record = message.record

    # Extract timestamp in UTC ISO-8601
    dt = record["time"].astimezone(timezone.utc)
    ts = dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    # Assemble canonical base structure
    event = {
        "timestamp": ts,
        "level": record["level"].name.lower(),
        "service": record["extra"].get("service", SERVICE_NAME),
        "app": record["extra"].get("app", record["extra"].get("service", SERVICE_NAME)),
        "env": record["extra"].get("env", ENV_NAME),
        "message": record["message"],
    }

    # Exception and traceback handling in a single line
    if record["exception"]:
        exc_type, exc_val, exc_tb = record["exception"]
        formatted_exc = message.format()
        event["stack_trace"] = formatted_exc.strip()
        if not event["message"]:
            event["message"] = f"Exception: {exc_type.__name__ if exc_type else 'Error'}: {exc_val}"

    # Extract metadata and extra fields injected via bind(...) or extra={...}
    extra = record.get("extra", {})
    context_extra = {}

    for k, v in extra.items():
        if k in ("service", "app", "env"):
            continue
        if k in CANONICAL_FIELDS:
            event[k] = v
        else:
            context_extra[k] = v

    if context_extra:
        event["context"] = context_extra

    # Guarantee strict NDJSON (1 JSON line without line breaks inside payload)
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# Register custom sink
logger.add(_victorialogs_sink, format="{message}")

__all__ = ["logger"]
