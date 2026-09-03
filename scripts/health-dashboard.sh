#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs & Vector — Homelab Health & Telemetry CLI Dashboard
# ==============================================================================
# Monitor leve em linha de comando que consome as APIs nativas do VictoriaLogs:
# - /health (status de prontidão)
# - /metrics (telemetria interna de memória, ingestão e partições)
# - /select/logsql/hits (contagem de erros e warnings agregados no tempo)
# - /select/logsql/query (top containers geradores de logs)
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

VICTORIALOGS_PORT="${VICTORIALOGS_HTTP_PORT:-9428}"
HOST="127.0.0.1"
VL_BASE_URL="http://${HOST}:${VICTORIALOGS_PORT}"

# Configurar autenticação para curl se configurada
CURL_AUTH_OPTS=()
if [[ -n "${VICTORIALOGS_AUTH_USERNAME:-}" ]]; then
  CURL_AUTH_OPTS=(-u "${VICTORIALOGS_AUTH_USERNAME}:${VICTORIALOGS_AUTH_PASSWORD:-}")
fi

WATCH_MODE=false
WATCH_INTERVAL=5

# Parse de argumentos
for arg in "$@"; do
  case "${arg}" in
    -w|--watch)
      WATCH_MODE=true
      ;;
    -i|--interval)
      shift
      WATCH_INTERVAL="${1:-5}"
      ;;
    -h|--help)
      echo "Uso: $0 [opções]"
      echo "Opções:"
      echo "  -w, --watch         Executa em modo contínuo (atualiza a cada N segundos)"
      echo "  -i, --interval N    Intervalo de atualização no modo watch (padrão: 5s)"
      echo "  -h, --help          Exibe esta ajuda"
      exit 0
      ;;
  esac
done

render_dashboard() {
  local NOW
  NOW="$(date '+%Y-%m-%d %H:%M:%S')"
  local PROFILE="${STORAGE_PROFILE:-hdd}"
  local HOSTNAME_LABEL="${HOST_IDENTIFIER:-mini-pc-proxmox}"

  # 1. Checar saúde do VictoriaLogs
  local HEALTH_STATUS="OFFLINE"
  local HEALTH_HTTP_CODE
  HEALTH_HTTP_CODE=$(curl "${CURL_AUTH_OPTS[@]}" -s -o /dev/null -w "%{http_code}" "${VL_BASE_URL}/health" 2>/dev/null || echo "000")
  if [[ "${HEALTH_HTTP_CODE}" == "200" ]]; then
    HEALTH_STATUS="OK (Saudável)"
  fi

  # 2. Consultar métricas do /metrics do VictoriaLogs
  local TOTAL_ROWS_INGESTED="0"
  local MEM_BYTES="0"
  local MEM_MB="0"

  if [[ "${HEALTH_HTTP_CODE}" == "200" ]]; then
    local METRICS_OUTPUT
    METRICS_OUTPUT=$(curl "${CURL_AUTH_OPTS[@]}" -s "${VL_BASE_URL}/metrics" 2>/dev/null || true)
    
    # Extrair linhas ingeridas
    TOTAL_ROWS_INGESTED=$(echo "${METRICS_OUTPUT}" | grep -E '^vl_rows_ingested_total' | awk '{print $2}' | head -n1 || echo "0")
    if [[ -z "${TOTAL_ROWS_INGESTED}" ]]; then TOTAL_ROWS_INGESTED="0"; fi

    # Extrair memória alocada pelo Go runtime (process_resident_memory_bytes)
    MEM_BYTES=$(echo "${METRICS_OUTPUT}" | grep -E '^process_resident_memory_bytes' | awk '{print $2}' | head -n1 || echo "0")
    if [[ -n "${MEM_BYTES}" && "${MEM_BYTES}" =~ ^[0-9]+$ ]]; then
      MEM_MB=$(( MEM_BYTES / 1024 / 1024 ))
    fi
  fi

  # 3. Consultar contagem de eventos via /select/logsql/hits
  local ERRORS_15M="0"
  local ERRORS_1H="0"
  local WARNS_1H="0"

  if [[ "${HEALTH_HTTP_CODE}" == "200" ]]; then
    # Erros nos últimos 15 minutos
    local HITS_15M_JSON
    HITS_15M_JSON=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${VL_BASE_URL}/select/logsql/hits" \
      --data-urlencode 'query=_time:15m AND level:error' 2>/dev/null || true)
    ERRORS_15M=$(echo "${HITS_15M_JSON}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(sum(x.get('total', 0) for x in data.get('hits', [])))" 2>/dev/null || echo "0")

    # Erros na última 1 hora
    local HITS_1H_JSON
    HITS_1H_JSON=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${VL_BASE_URL}/select/logsql/hits" \
      --data-urlencode 'query=_time:1h AND level:error' 2>/dev/null || true)
    ERRORS_1H=$(echo "${HITS_1H_JSON}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(sum(x.get('total', 0) for x in data.get('hits', [])))" 2>/dev/null || echo "0")

    # Warnings na última 1 hora
    local WARNS_1H_JSON
    WARNS_1H_JSON=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${VL_BASE_URL}/select/logsql/hits" \
      --data-urlencode 'query=_time:1h AND level:warn' 2>/dev/null || true)
    WARNS_1H=$(echo "${WARNS_1H_JSON}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(sum(x.get('total', 0) for x in data.get('hits', [])))" 2>/dev/null || echo "0")
  fi

  # 4. Consultar Top 5 Containers geradores de logs na última 1h
  local TOP_CONTAINERS=""
  if [[ "${HEALTH_HTTP_CODE}" == "200" ]]; then
    TOP_CONTAINERS=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${VL_BASE_URL}/select/logsql/query" \
      --data-urlencode 'query=_time:1h | stats count() rows by (container_name) | sort by (rows) desc | limit 5' 2>/dev/null || true)
  fi

  # 5. Consultar status e RAM dos containers Docker se o comando docker estiver acessível
  local DOCKER_STATS_TEXT=""
  if command -v docker >/dev/null 2>&1; then
    DOCKER_STATS_TEXT=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | grep -E 'NAME|victorialogs|vector' || true)
  fi

  # RENDERIZAÇÃO FORMATADA NO TERMINAL
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║         🪵  VICTORIALOGS & VECTOR — HOMELAB HEALTH & TELEMETRY DASHBOARD      ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  printf " 🕒 Atualizado: %-20s  🏷️  Host: %-15s  💾 Perfil: %s\n" "${NOW}" "${HOSTNAME_LABEL}" "${PROFILE^^}"
  echo "────────────────────────────────────────────────────────────────────────────────"

  # Seção 1: Saúde dos Serviços
  echo "📌 STATUS DA STACK"
  if [[ "${HEALTH_STATUS}" == *"OK"* ]]; then
    printf "  • VictoriaLogs API (:9428): \033[0;32m%s\033[0m (RAM no Processo: ~%s MB)\n" "${HEALTH_STATUS}" "${MEM_MB}"
  else
    printf "  • VictoriaLogs API (:9428): \033[0;31m%s\033[0m\n" "${HEALTH_STATUS}"
  fi
  printf "  • Total de Logs Ingeridos (Lifetime): %'d registros\n" "${TOTAL_ROWS_INGESTED}" 2>/dev/null || printf "  • Total de Logs Ingeridos: %s registros\n" "${TOTAL_ROWS_INGESTED}"
  echo ""

  # Seção 2: Monitoramento de Erros e Alertas
  echo "🚨 TELEMETRIA DE ERROS (Via /select/logsql/hits)"
  if [[ "${ERRORS_15M}" != "0" ]]; then
    printf "  • Erros nos últimos 15 min: \033[0;31m%s eventos\033[0m ⚠️\n" "${ERRORS_15M}"
  else
    printf "  • Erros nos últimos 15 min: \033[0;32m0 eventos\033[0m (Estável)\n"
  fi
  printf "  • Erros na última 1 hora:   %s eventos\n" "${ERRORS_1H}"
  printf "  • Alertas (Warn) na 1 hora: %s eventos\n" "${WARNS_1H}"
  echo ""

  # Seção 3: Top Containers mais barulhentos
  echo "📊 TOP 5 CONTAINERS GERADORES DE LOGS (Última 1 hora)"
  if [[ -n "${TOP_CONTAINERS}" && "${TOP_CONTAINERS}" != *"error"* ]]; then
    echo "${TOP_CONTAINERS}" | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
if not lines:
    print('  (Nenhum log registrado na última hora)')
else:
    for i, line in enumerate(lines, 1):
        try:
            d = json.loads(line)
            c = d.get('container_name', 'desconhecido')
            r = d.get('rows', d.get('count', 0))
            print(f'  {i}. {c:<25} -> {r:>8} logs')
        except Exception:
            pass
" 2>/dev/null || echo "  (Aguardando registros...)"
  else
    echo "  (Nenhum log registrado na última hora)"
  fi
  echo ""

  # Seção 4: Docker Stats se disponível
  if [[ -n "${DOCKER_STATS_TEXT}" ]]; then
    echo "🐳 RECURSOS DOCKER AO VIVO"
    echo "${DOCKER_STATS_TEXT}" | sed 's/^/  /'
    echo ""
  fi

  echo "────────────────────────────────────────────────────────────────────────────────"
  echo "🔗 VMUI Web: ${VL_BASE_URL}/select/vmui/ | Documentação: README.md"
  echo "════════════════════════════════════════════════════════════════════════════════"
}

if [[ "${WATCH_MODE}" == true ]]; then
  while true; do
    clear || true
    render_dashboard
    echo "Pressione [Ctrl+C] para sair do modo contínuo (atualiza a cada ${WATCH_INTERVAL}s)..."
    sleep "${WATCH_INTERVAL}"
  done
else
  render_dashboard
fi
