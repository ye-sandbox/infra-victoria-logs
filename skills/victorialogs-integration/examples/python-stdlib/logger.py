"""
Plug-and-Play Logger in pure Python (Standard Library) for VictoriaLogs + Vector.

Zero external dependencies.
Strictly emits 1 JSON object per line (NDJSON) on stdout without intermediate line breaks,
with canonical support for ISO-8601 UTC timestamp, lowercase level, app, env, service,
correlation fields (trace_id, request_id, http_status, duration_ms), and serialized stack_trace.
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone

SERVICE_NAME = os.getenv("SERVICE_NAME", os.getenv("APP_NAME", "app-python"))
ENV_NAME = os.getenv("ENVIRONMENT", os.getenv("ENV", "production"))

CANONICAL_FIELDS = {
    "trace_id",
    "request_id",
    "http_status",
    "duration_ms",
    "user_id",
    "ip",
}


class VictoriaLogsJsonFormatter(logging.Formatter):
    """Strict NDJSON formatter for VictoriaLogs + Vector."""

    def format(self, record: logging.LogRecord) -> str:
        # ISO-8601 UTC timestamp with millisecond precision
        dt = datetime.fromtimestamp(record.created, tz=timezone.utc)
        ts = dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

        event = {
            "timestamp": ts,
            "level": record.levelname.lower(),
            "service": getattr(record, "service", SERVICE_NAME),
            "app": getattr(record, "app", getattr(record, "service", SERVICE_NAME)),
            "env": getattr(record, "env", ENV_NAME),
            "message": record.getMessage(),
        }

        # Exception serialization in the same JSON record
        if record.exc_info:
            stack = self.formatException(record.exc_info)
            event["stack_trace"] = stack
            if not event["message"]:
                event["message"] = str(record.exc_info[1])
            else:
                event["message"] += "\n" + stack

        # Python stdlib logging reserved fields
        reserved = {
            "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
            "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
            "created", "msecs", "relativeCreated", "thread", "threadName",
            "processName", "process", "message", "taskName", "service", "app", "env",
        }

        context_extra = {}
        for key, value in record.__dict__.items():
            if key in reserved:
                continue
            if key in CANONICAL_FIELDS:
                event[key] = value
            else:
                context_extra[key] = value

        if context_extra:
            event["context"] = context_extra

        # Single line without pretty formatting
        return json.dumps(event, ensure_ascii=False)


def setup_logger(name: str = "app", level: int = logging.INFO) -> logging.Logger:
    """Configures and returns a logger instance formatted for NDJSON."""
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.propagate = False

    # Prevent duplicate handlers
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(VictoriaLogsJsonFormatter())
        logger.addHandler(handler)

    return logger


if __name__ == "__main__":
    log = setup_logger("example-stdlib")
    log.info("HTTP server started on port 8000")

    # Log with correlation
    log.info(
        "Request processed successfully",
        extra={
            "trace_id": "tr-12345",
            "request_id": "req-98765",
            "http_status": 200,
            "duration_ms": 35.5,
            "user_id": "user-42",
        },
    )

    # Error log with exception
    try:
        raise ConnectionResetError("Connection unexpectedly closed by peer")
    except Exception:
        log.error(
            "External communication failure",
            exc_info=True,
            extra={
                "trace_id": "tr-12345",
                "request_id": "req-98765",
                "http_status": 502,
                "duration_ms": 1500.0,
            },
        )
