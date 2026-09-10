"""
Logger Plug-and-Play com Loguru para VictoriaLogs + Vector.

Emite estritamente 1 objeto JSON por linha (NDJSON) em stdout sem quebras intermediárias,
com suporte canônico a timestamp ISO-8601 UTC, nível minúsculo, app, env, service,
campos de correlação (trace_id, request_id, http_status, duration_ms) e stack_trace serializado.
"""

import json
import os
import sys
from datetime import datetime, timezone
from loguru import logger

# Desativa o handler padrão colorido do loguru
logger.remove()

SERVICE_NAME = os.getenv("SERVICE_NAME", os.getenv("APP_NAME", "app-python"))
ENV_NAME = os.getenv("ENVIRONMENT", os.getenv("ENV", "production"))

# Campos canônicos de correlação promovidos a primeiro nível
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

    # Extrai o timestamp em UTC ISO-8601
    dt = record["time"].astimezone(timezone.utc)
    ts = dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    # Monta a estrutura base canônica
    event = {
        "timestamp": ts,
        "level": record["level"].name.lower(),
        "service": record["extra"].get("service", SERVICE_NAME),
        "app": record["extra"].get("app", record["extra"].get("service", SERVICE_NAME)),
        "env": record["extra"].get("env", ENV_NAME),
        "message": record["message"],
    }

    # Tratamento de exceção / traceback em uma linha só
    if record["exception"]:
        exc_type, exc_val, exc_tb = record["exception"]
        formatted_exc = message.format()
        event["stack_trace"] = formatted_exc.strip()
        if not event["message"]:
            event["message"] = f"Exception: {exc_type.__name__ if exc_type else 'Error'}: {exc_val}"

    # Extrai metadados e campos extras injetados via bind(...) ou extra={...}
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

    # Garante NDJSON rigoroso (1 linha JSON sem quebras de linha dentro do payload)
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# Registra o sink customizado
logger.add(_victorialogs_sink, format="{message}")

__all__ = ["logger"]
