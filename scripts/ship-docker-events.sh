#!/usr/bin/env bash
# ==============================================================================
# Coletor de Eventos do Daemon Docker (docker events) para VictoriaLogs + Vector
# ==============================================================================
# Escuta o stream de eventos do Docker Engine (die, oom, kill, restart) e envia
# como logs estruturados ao Vector no endpoint HTTP (:8686/logs).
# Permite detectar instantaneamente mortes por OOM (Exit 137) e falhas de processo.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

VECTOR_HOST="${VECTOR_HOST:-127.0.0.1}"
VECTOR_PORT="${VECTOR_HTTP_PORT:-8686}"
VECTOR_URL="${VECTOR_ENDPOINT:-http://${VECTOR_HOST}:${VECTOR_PORT}/logs}"
HOST_ID="${HOST_IDENTIFIER:-$(hostname)}"
SINCE_FILTER=""
UNTIL_FILTER=""
DRY_RUN=false

usage() {
  cat <<HELP_EOF
Uso: $(basename "$0") [OPÇÕES]

Opções:
  -s, --since DURAÇÃO     Coleta eventos históricos (ex: "1h", "10m") e encerra
  -u, --until DURAÇÃO     Limite superior de tempo (usado com --since)
  -d, --dry-run           Apenas extrai e imprime o JSON no stdout sem enviar via HTTP
  -e, --endpoint URL      Define o endpoint do Vector (padrão: ${VECTOR_URL})
  -h, --help              Exibe esta ajuda e encerra

Variáveis de Ambiente:
  VECTOR_ENDPOINT         URL completa do endpoint Vector (ex: http://127.0.0.1:8686/logs)
  HOST_IDENTIFIER         Identificador do host (padrão: hostname atual)
HELP_EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--since)
      if [[ $# -gt 1 ]]; then
        SINCE_FILTER="$2"
        shift 2
      else
        echo "Erro: --since requer uma duração/timestamp válido." >&2
        exit 1
      fi
      ;;
    -u|--until)
      if [[ $# -gt 1 ]]; then
        UNTIL_FILTER="$2"
        shift 2
      else
        echo "Erro: --until requer uma duração/timestamp válido." >&2
        exit 1
      fi
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -e|--endpoint)
      if [[ $# -gt 1 ]]; then
        VECTOR_URL="$2"
        shift 2
      else
        echo "Erro: --endpoint requer uma URL válida." >&2
        exit 1
      fi
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      usage
      ;;
  esac
done

if ! command -v docker &>/dev/null; then
  echo "❌ Erro: 'docker' não encontrado no PATH." >&2
  exit 1
fi

if ! command -v curl &>/dev/null && [[ "$DRY_RUN" == false ]]; then
  echo "❌ Erro: 'curl' não encontrado no PATH." >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "❌ Erro: 'python3' não encontrado no PATH." >&2
  exit 1
fi

export HOST_ID VECTOR_URL DRY_RUN

process_event_json() {
  python3 -c '
import sys
import os
import json
from datetime import datetime, timezone
import urllib.request
import urllib.error

host_id = os.environ.get("HOST_ID", "docker-host")
vector_url = os.environ.get("VECTOR_URL", "http://127.0.0.1:8686/logs")
dry_run = (os.environ.get("DRY_RUN", "false") == "true")

def parse_line(line):
    line = line.strip()
    if not line:
        return None
    try:
        raw = json.loads(line)
    except Exception:
        return None

    action = raw.get("Action", raw.get("status", ""))
    actor = raw.get("Actor", {})
    attrs = actor.get("Attributes", {})
    
    container_name = attrs.get("name", "unknown")
    image = attrs.get("image", raw.get("from", "unknown"))
    container_id = actor.get("ID", raw.get("id", ""))[:12]

    exit_code_str = attrs.get("exitCode", "")
    exit_code = None
    if exit_code_str != "":
        try:
            exit_code = int(exit_code_str)
        except ValueError:
            exit_code = None

    level = "info"
    oom_killed = (action == "oom")
    
    if action == "oom":
        level = "error"
        msg = f"container {container_name} suffered OOM (Out Of Memory)"
    elif action == "die":
        if exit_code == 137:
            level = "error"
            oom_killed = True
            msg = f"container {container_name} died with exitCode=137 (SIGKILL / likely OOM)"
        elif exit_code is not None and exit_code != 0:
            level = "error"
            msg = f"container {container_name} died with exitCode={exit_code}"
        else:
            level = "info"
            msg = f"container {container_name} stopped cleanly (exitCode=0)"
    elif action in ("kill", "restart"):
        level = "warn"
        msg = f"container {container_name} event: {action}"
    else:
        level = "info"
        msg = f"container {container_name} event: {action}"

    time_epoch = raw.get("time")
    if time_epoch:
        ts = datetime.fromtimestamp(time_epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    else:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

    event = {
        "timestamp": ts,
        "level": level,
        "service": "docker-events",
        "app": "docker-events",
        "env": "production",
        "host": host_id,
        "container_name": container_name,
        "target_container": container_name,
        "target_container_id": container_id,
        "image": image,
        "docker_action": action,
        "exit_code": exit_code,
        "oom_killed": oom_killed,
        "message": msg
    }
    return event

for line in sys.stdin:
    ev = parse_line(line)
    if not ev:
        continue

    if dry_run:
        print(json.dumps(ev))
        sys.stdout.flush()
    else:
        try:
            payload = json.dumps([ev]).encode("utf-8")
            req = urllib.request.Request(
                vector_url,
                data=payload,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                ts = ev.get("timestamp")
                action_name = ev.get("docker_action")
                target = ev.get("target_container")
                sys.stdout.write(f"[{ts}] Evento \"{action_name}\" de \"{target}\" enviado ao Vector.\n")
                sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Falha ao enviar evento para {vector_url}: {e}\n")
'
}

cleanup() {
  echo -e "\n🛑 Finalizando coletor docker-events..."
  exit 0
}
trap cleanup SIGINT SIGTERM

DOCKER_EVENTS_CMD=(docker events --filter 'type=container' --filter 'event=die' --filter 'event=oom' --filter 'event=kill' --filter 'event=restart' --format '{{json .}}')

if [[ -n "${SINCE_FILTER}" ]]; then
  DOCKER_EVENTS_CMD+=(--since "${SINCE_FILTER}")
fi

if [[ -n "${UNTIL_FILTER}" ]]; then
  DOCKER_EVENTS_CMD+=(--until "${UNTIL_FILTER}")
fi

if [[ -z "${SINCE_FILTER}" ]]; then
  echo "🚀 Coletor docker-events conectado ao Docker Engine (destino: ${VECTOR_URL})..."
fi

"${DOCKER_EVENTS_CMD[@]}" | process_event_json || true
