#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs + vmalert Alerting Notification Smoke Test Script
# ==============================================================================
# Valida o canal de notificações do vmalert e alert-bridge.
#
# Modos de operação:
#   ./scripts/test-alerting.sh           # Teste direto simulando disparo de alerta para o alert-bridge
#   ./scripts/test-alerting.sh --direct  # Envia alertas de teste (OOMKilled e HighErrorRate) para o bridge
#   ./scripts/test-alerting.sh --inject  # Injeta evento sintético de OOMKilled no Vector para validar ingestão
#   ./scripts/test-alerting.sh --help    # Exibe opções disponíveis
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

BRIDGE_PORT="${ALERT_BRIDGE_HTTP_PORT:-9093}"
HOST="${VICTORIALOGS_HOST:-127.0.0.1}"
BRIDGE_URL="http://${HOST}:${BRIDGE_PORT}"
HEALTH_URL="${BRIDGE_URL}/health"
ALERTS_API_URL="${BRIDGE_URL}/api/v2/alerts"

MODE="direct"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --direct)
      MODE="direct"
      shift
      ;;
    --inject)
      MODE="inject"
      shift
      ;;
    -h|--help)
      cat << 'EOF'
Uso: ./scripts/test-alerting.sh [OPÇÕES]

Opções:
  --direct    (Padrão) Envia payloads de alerta (OOMKilled e HighErrorRate) diretamente ao alert-bridge
  --inject    Injeta evento sintético de crash/OOM no pipeline do Vector para validar indexação
  -h, --help  Exibe esta tela de ajuda

Exemplos:
  ./scripts/test-alerting.sh
  ./scripts/test-alerting.sh --inject
EOF
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      echo "Use ./scripts/test-alerting.sh --help para ver as opções disponíveis." >&2
      exit 1
      ;;
  esac
done

echo "================================================================================"
echo "🔔 [vmalert Notification Smoke Test] Iniciando validação de alertas..."
echo "================================================================================"

# 1. Checar saúde do alert-bridge
echo "1️⃣  Verificando disponibilidade do alert-bridge em ${HEALTH_URL}..."
HEALTH_RESP=""
if ! HEALTH_RESP=$(curl -s -f "${HEALTH_URL}" 2>/dev/null); then
  # Se o HOST configurado for remoto e falhar, tenta localhost antes de desistir
  if [[ "${HOST}" != "127.0.0.1" && "${HOST}" != "localhost" ]] && HEALTH_RESP=$(curl -s -f "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null); then
    echo "   ℹ️  Host configurado (${HOST}) indisponível, mas detectado alert-bridge ativo em 127.0.0.1. Utilizando localhost."
    HOST="127.0.0.1"
    BRIDGE_URL="http://127.0.0.1:${BRIDGE_PORT}"
    HEALTH_URL="${BRIDGE_URL}/health"
    ALERTS_API_URL="${BRIDGE_URL}/api/v2/alerts"
  else
    echo "❌ alert-bridge não está respondendo em ${HEALTH_URL}."
    echo ""
    echo "💡 Para iniciar os serviços de alerta, execute:"
    echo "   docker compose --profile alerting up -d alert-bridge vmalert"
    echo ""
    echo "Ou execute localmente em outro terminal para testes rápidos:"
    echo "   python3 alert-bridge/server.py"
    exit 1
  fi
fi

echo "   ✅ alert-bridge está saudável e respondendo!"
echo "   📊 Informações do bridge: ${HEALTH_RESP}"
echo ""

if [[ "${MODE}" == "direct" ]]; then
  # 2. Enviar alerta simulado de ContainerOOMKilled (Crítico)
  TEST_ID="test_oom_$(date +%s)"
  echo "2️⃣  Enviando alerta simulado 'ContainerOOMKilled' (severidade: critical)..."

  PAYLOAD_CRITICAL=$(cat <<EOF
[
  {
    "status": "firing",
    "labels": {
      "alertname": "ContainerOOMKilled",
      "severity": "critical",
      "container_name": "simulated-worker",
      "service": "batch-processor",
      "host": "homelab-node-01"
    },
    "annotations": {
      "summary": "Container simulated-worker sofreu OOMKilled (Out Of Memory)",
      "description": "O container simulated-worker foi finalizado pelo kernel do host devido a estouro de limite de memória RAM (Exit Code 137). [${TEST_ID}]"
    },
    "startsAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
]
EOF
)

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${ALERTS_API_URL}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD_CRITICAL}")

  if [[ "${HTTP_STATUS}" != "200" ]]; then
    echo "❌ Falha ao enviar alerta para o alert-bridge. Código HTTP: ${HTTP_STATUS}"
    exit 1
  fi
  echo "   ✅ Alerta crítico processado com sucesso pelo bridge (HTTP ${HTTP_STATUS})."
  echo ""

  # 3. Enviar alerta simulado de HighErrorRate (Warning)
  echo "3️⃣  Enviando alerta simulado 'HighErrorRate' (severidade: warning)..."
  PAYLOAD_WARNING=$(cat <<EOF
[
  {
    "status": "firing",
    "labels": {
      "alertname": "HighErrorRate",
      "severity": "warning",
      "service": "api-gateway",
      "host": "homelab-node-01"
    },
    "annotations": {
      "summary": "Taxa de erro elevada detectada no serviço api-gateway",
      "description": "O serviço api-gateway registrou mais de 10 mensagens de erro nos últimos 5 minutos."
    },
    "startsAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
]
EOF
)

  HTTP_STATUS_WARN=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${ALERTS_API_URL}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD_WARNING}")

  if [[ "${HTTP_STATUS_WARN}" != "200" ]]; then
    echo "❌ Falha ao enviar alerta de warning. Código HTTP: ${HTTP_STATUS_WARN}"
    exit 1
  fi
  echo "   ✅ Alerta warning processado com sucesso pelo bridge (HTTP ${HTTP_STATUS_WARN})."
  echo ""

  # 4. Verificar histórico recente em /alerts
  echo "4️⃣  Consultando histórico de alertas recebidos em ${BRIDGE_URL}/alerts..."
  RECENT_ALERTS=$(curl -s "${BRIDGE_URL}/alerts" | grep -oE '"count":\s*[0-9]+' | tr -d ' "count:' || true)
  echo "   ✅ Total de alertas registrados no histórico: ${RECENT_ALERTS:-0}"
  echo ""
  echo "🎉 [SUCESSO] O canal de notificações (alert-bridge) está operacional e recebendo alertas!"
  echo "================================================================================"
  exit 0

elif [[ "${MODE}" == "inject" ]]; then
  VECTOR_PORT="${VECTOR_HTTP_PORT:-8686}"
  VECTOR_URL="http://${HOST}:${VECTOR_PORT}/logs"
  TEST_RUN_ID="sim_oom_$(date +%s)"

  echo "2️⃣  Injetando evento simulado de OOMKilled no Vector (${VECTOR_URL})..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${VECTOR_URL}" \
    -H "Content-Type: application/json" \
    -d "{
      \"app\": \"docker-events\",
      \"service\": \"docker-events\",
      \"env\": \"production\",
      \"action\": \"die\",
      \"oom_killed\": \"true\",
      \"exit_code\": \"137\",
      \"container_name\": \"synthetic-oom-app\",
      \"message\": \"Container synthetic-oom-app terminated with OOMKilled (Exit Code 137)\",
      \"sim_id\": \"${TEST_RUN_ID}\"
    }")

  if [[ "${HTTP_STATUS}" != "200" && "${HTTP_STATUS}" != "204" ]]; then
    echo "❌ Falha ao enviar evento para o Vector. Código HTTP: ${HTTP_STATUS}"
    echo "Certifique-se de que a stack base está rodando ('docker compose up -d')."
    exit 1
  fi
  echo "   ✅ Evento de OOMKilled ingerido no Vector (HTTP ${HTTP_STATUS})."
  echo ""
  echo "💡 O evento foi enviado para indexação no VictoriaLogs."
  echo "   O vmalert avaliará a regra 'ContainerOOMKilled' no próximo ciclo de avaliação (-evaluationInterval=30s)."
  echo "   Acompanhe os logs do vmalert e alert-bridge:"
  echo "   docker compose logs -f vmalert alert-bridge"
  echo "================================================================================"
  exit 0
fi
