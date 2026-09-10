"""
Logger Plug-and-Play em Python puro (Standard Library) para VictoriaLogs + Vector.

Zero dependências externas.
Emite estritamente 1 objeto JSON por linha (NDJSON) em stdout sem quebras intermediárias,
com suporte canônico a timestamp ISO-8601 UTC, nível minúsculo, app, env, service,
campos de correlação (trace_id, request_id, http_status, duration_ms) e stack_trace serializado.
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
    """Formatador estrito de NDJSON para VictoriaLogs + Vector."""

    def format(self, record: logging.LogRecord) -> str:
        # Timestamp em ISO-8601 UTC com precisão de milissegundos
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

        # Serialização de exceções no mesmo registro JSON
        if record.exc_info:
            stack = self.formatException(record.exc_info)
            event["stack_trace"] = stack
            if not event["message"]:
                event["message"] = str(record.exc_info[1])
            else:
                event["message"] += "\n" + stack

        # Campos reservados da stdlib logging do Python
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

        # Linha única sem formatação pretty
        return json.dumps(event, ensure_ascii=False)


def setup_logger(name: str = "app", level: int = logging.INFO) -> logging.Logger:
    """Configura e retorna uma instância de logger configurada para NDJSON."""
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.propagate = False

    # Evita duplicação de handlers
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(VictoriaLogsJsonFormatter())
        logger.addHandler(handler)

    return logger


if __name__ == "__main__":
    log = setup_logger("example-stdlib")
    log.info("Servidor HTTP iniciado na porta 8000")

    # Log com correlação
    log.info(
        "Requisição processada com sucesso",
        extra={
            "trace_id": "tr-12345",
            "request_id": "req-98765",
            "http_status": 200,
            "duration_ms": 35.5,
            "user_id": "user-42",
        },
    )

    # Log de erro com exceção
    try:
        raise ConnectionResetError("Conexão fechada inesperadamente pelo peer")
    except Exception:
        log.error(
            "Falha de comunicação externa",
            exc_info=True,
            extra={
                "trace_id": "tr-12345",
                "request_id": "req-98765",
                "http_status": 502,
                "duration_ms": 1500.0,
            },
        )
