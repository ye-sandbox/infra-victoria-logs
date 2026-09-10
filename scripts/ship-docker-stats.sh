#!/usr/bin/env bash
# ==============================================================================
# Coletor de Consumo de Recursos Docker (docker stats) para VictoriaLogs + Vector
# ==============================================================================
# Captura estatísticas instantâneas de CPU, memória, limites e I/O de containers
# locais via `docker stats --no-stream` e envia como logs estruturados ao Vector
# no endpoint HTTP (:8686/logs), permitindo observabilidade leve em Homelabs.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Carregar variáveis do .env se existir
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
INTERVAL="${STATS_INTERVAL:-60}"
DRY_RUN=false
LOOP_MODE=false

usage() {
  cat <<HELP_EOF
Uso: $(basename "$0") [OPÇÕES]

Opções:
  -l, --loop [SEGUNDOS]   Executa em loop contínuo (padrão se omitido: ${INTERVAL}s)
  -d, --dry-run           Apenas extrai e imprime o JSON no stdout sem enviar via HTTP
  -e, --endpoint URL      Define o endpoint do Vector (padrão: ${VECTOR_URL})
  -h, --help              Exibe esta ajuda e encerra

Variáveis de Ambiente:
  VECTOR_ENDPOINT         URL completa do endpoint Vector (ex: http://127.0.0.1:8686/logs)
  STATS_INTERVAL          Intervalo em segundos para o modo loop (padrão: 60)
  HOST_IDENTIFIER         Identificador do host (padrão: hostname atual)
HELP_EOF
  exit 0
}

# Parsing de argumentos de linha de comando
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--loop)
      LOOP_MODE=true
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        INTERVAL="$2"
        shift 2
      else
        shift
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

# Checar dependências obrigatórias
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

collect_and_ship() {
  # 1. Coletar stats brutos do Docker
  local raw_stats
  if ! raw_stats=$(docker stats --no-stream --format '{{json .}}' 2>/dev/null); then
    echo "⚠️ Falha ao executar 'docker stats'. Verifique permissões do socket Docker." >&2
    return 1
  fi

  if [[ -z "${raw_stats//[[:space:]]/}" ]]; then
    return 0
  fi

  # 2. Processar e estruturar via Python (biblioteca padrão)
  local json_payload
  json_payload=$(python3 - <<PY_EOF
import json
import re
from datetime import datetime, timezone

raw_input = """${raw_stats}"""
host_id = "${HOST_ID}"

def parse_bytes_to_mb(val_str):
    if not val_str:
        return 0.0
    val_str = val_str.strip()
    match = re.match(r"^([\d\.]+)\s*([a-zA-Z]+)$", val_str)
    if not match:
        return 0.0
    num = float(match.group(1))
    unit = match.group(2).lower()
    
    multipliers = {
        "b": 1.0 / (1024 * 1024),
        "kib": 1.0 / 1024,
        "kb": 1.0 / 1024,
        "mib": 1.0,
        "mb": 1.0,
        "gib": 1024.0,
        "gb": 1024.0,
        "tib": 1024.0 * 1024.0,
        "tb": 1024.0 * 1024.0
    }
    return round(num * multipliers.get(unit, 1.0), 2)

now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
events = []

for line in raw_input.strip().split("\n"):
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
    except Exception:
        continue

    container_name = data.get("Name", "unknown")
    container_id = data.get("ID", "")
    
    # CPU
    cpu_str = data.get("CPUPerc", "0.0%").replace("%", "").strip()
    try:
        cpu_percent = round(float(cpu_str), 2)
    except ValueError:
        cpu_percent = 0.0

    # Memória
    mem_perc_str = data.get("MemPerc", "0.0%").replace("%", "").strip()
    try:
        mem_percent = round(float(mem_perc_str), 2)
    except ValueError:
        mem_percent = 0.0

    mem_usage_str = data.get("MemUsage", "")
    mem_usage_mb = 0.0
    mem_limit_mb = 0.0
    if "/" in mem_usage_str:
        parts = mem_usage_str.split("/", 1)
        mem_usage_mb = parse_bytes_to_mb(parts[0])
        mem_limit_mb = parse_bytes_to_mb(parts[1])

    # PIDs
    try:
        pids = int(data.get("PIDs", 0))
    except (ValueError, TypeError):
        pids = 0

    net_io = data.get("NetIO", "")
    block_io = data.get("BlockIO", "")

    level = "info"
    if mem_percent >= 90.0 or cpu_percent >= 90.0:
        level = "warn"

    msg = f"container {container_name}: cpu={cpu_percent}% mem={mem_usage_mb}MB/{mem_limit_mb}MB ({mem_percent}%) pids={pids}"

    event = {
        "timestamp": now_iso,
        "level": level,
        "service": "docker-stats",
        "app": "docker-stats",
        "env": "production",
        "host": host_id,
        "container_name": container_name,
        "target_container": container_name,
        "target_container_id": container_id,
        "cpu_percent": cpu_percent,
        "mem_usage_mb": mem_usage_mb,
        "mem_limit_mb": mem_limit_mb,
        "mem_percent": mem_percent,
        "net_io": net_io,
        "block_io": block_io,
        "pids": pids,
        "message": msg
    }
    events.append(event)

if events:
    print(json.dumps(events))
PY_EOF
)

  if [[ -z "${json_payload}" ]]; then
    return 0
  fi

  # 3. Dry-run ou Envio via HTTP
  if [[ "$DRY_RUN" == true ]]; then
    echo "${json_payload}"
    return 0
  fi

  local count
  count=$(python3 -c "import json, sys; print(len(json.loads('''${json_payload}''')))")

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${VECTOR_URL}" \
    -H "Content-Type: application/json" \
    --data-binary "${json_payload}" || echo "000")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Enfileirados ${count} registros de recursos no Vector (${VECTOR_URL}) [HTTP ${http_code}]."
  else
    echo "❌ [$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Falha ao enviar para ${VECTOR_URL}: HTTP ${http_code}" >&2
    return 1
  fi
}

cleanup() {
  echo -e "\n🛑 Finalizando coletor docker-stats..."
  exit 0
}
trap cleanup SIGINT SIGTERM

if [[ "$LOOP_MODE" == true ]]; then
  echo "🚀 Iniciando coletor docker-stats em loop contínuo (intervalo: ${INTERVAL}s, destino: ${VECTOR_URL})..."
  while true; do
    collect_and_ship || true
    sleep "${INTERVAL}"
  done
else
  collect_and_ship
fi
