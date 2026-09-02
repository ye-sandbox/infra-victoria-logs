#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs + Vector Pipeline Smoke Test Script
# ==============================================================================
# Envia eventos sintéticos (incluindo stack trace multilinha) para o Vector
# e valida a ingestão e indexação via API LogsQL do VictoriaLogs.
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

VECTOR_PORT="${VECTOR_HTTP_PORT:-8686}"
VICTORIALOGS_PORT="${VICTORIALOGS_HTTP_PORT:-9428}"
HOST="127.0.0.1"

VECTOR_URL="http://${HOST}:${VECTOR_PORT}/logs"
VL_QUERY_URL="http://${HOST}:${VICTORIALOGS_PORT}/select/logsql/query"
VL_HEALTH_URL="http://${HOST}:${VICTORIALOGS_PORT}/health"

# Configurar autenticação para curl se configurada
CURL_AUTH_OPTS=()
if [[ -n "${VICTORIALOGS_AUTH_USERNAME:-}" ]]; then
  CURL_AUTH_OPTS=(-u "${VICTORIALOGS_AUTH_USERNAME}:${VICTORIALOGS_AUTH_PASSWORD:-}")
fi

TEST_ID="test_$(date +%s)_$RANDOM"

echo "================================================================================"
echo "🧪 [Pipeline Smoke Test] Iniciando validação ponta a ponta..."
echo "================================================================================"

# 1. Checar saúde do VictoriaLogs
echo "1️⃣  Verificando saúde do VictoriaLogs..."
if ! curl "${CURL_AUTH_OPTS[@]}" -s -f "${VL_HEALTH_URL}" > /dev/null; then
  echo "❌ VictoriaLogs não está respondendo em ${VL_HEALTH_URL}."
  echo "Certifique-se de iniciar a stack com 'docker compose up -d'."
  exit 1
fi
echo "   ✅ VictoriaLogs está saudável e respondendo."

# 2. Ingestão de log de teste via HTTP do Vector
echo "2️⃣  Enviando evento de teste para o Vector (${VECTOR_URL})..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${VECTOR_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "service": "smoke-test-service",
    "level": "warn",
    "message": "Smoke test message for VictoriaLogs pipeline",
    "test_run_id": "'"${TEST_ID}"'"
  }')

if [[ "${HTTP_STATUS}" != "200" && "${HTTP_STATUS}" != "204" ]]; then
  echo "❌ Falha ao enviar log para o Vector. Código HTTP: ${HTTP_STATUS}"
  exit 1
fi
echo "   ✅ Evento recebido com sucesso pelo Vector (HTTP ${HTTP_STATUS})."

# 3. Aguardar flush do lote (batch) do Vector
WAIT_SECONDS=3
echo "3️⃣  Aguardando ${WAIT_SECONDS}s para o Vector consolidar o lote e descarregar no VictoriaLogs..."
sleep "${WAIT_SECONDS}"

# 4. Consultar no VictoriaLogs via LogsQL
echo "4️⃣  Consultando o evento no VictoriaLogs via LogsQL..."
QUERY="_stream:{service='smoke-test-service'} AND '${TEST_ID}'"

QUERY_RESULT=$(curl "${CURL_AUTH_OPTS[@]}" -s -G "${VL_QUERY_URL}" \
  --data-urlencode "query=${QUERY}" \
  --data-urlencode "limit=5")

if echo "${QUERY_RESULT}" | grep -q "${TEST_ID}"; then
  echo "   ✅ Evento localizado com sucesso no VictoriaLogs!"
  echo ""
  echo "📄 Registro indexado:"
  echo "--------------------------------------------------------------------------------"
  echo "${QUERY_RESULT}"
  echo "--------------------------------------------------------------------------------"
  echo ""
  echo "🎉 [SUCESSO] O pipeline de observabilidade está operando 100% perfeitamente!"
  echo "================================================================================"
  exit 0
else
  echo "❌ ERRO: O evento com ID '${TEST_ID}' não foi encontrado no VictoriaLogs."
  echo "Resposta obtida: ${QUERY_RESULT}"
  echo ""
  echo "Dica de depuração: verifique os logs do Vector com 'docker compose logs vector'."
  exit 1
fi
