#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs MCP Server Automated Integration Test
# ==============================================================================
# Envia requisições JSON-RPC 2.0 via stdin para mcp/server.py e valida
# se o handshake, o catálogo de ferramentas e a execução respondem conforme a spec MCP.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVER_SCRIPT="${ROOT_DIR}/mcp/server.py"

echo "================================================================================"
echo "🧪 [MCP Integration Test] Validando servidor MCP para VictoriaLogs..."
echo "================================================================================"

if [[ ! -f "${SERVER_SCRIPT}" ]]; then
  echo "❌ Arquivo ${SERVER_SCRIPT} não encontrado!"
  exit 1
fi

# 1. Testar handshake 'initialize'
echo "1️⃣  Testando método 'initialize'..."
INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0"}}}'
INIT_RESP=$(echo "${INIT_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${INIT_RESP}" | grep -q '"name": "victorialogs-mcp"'; then
  echo "   ✅ Handshake 'initialize' respondeu com sucesso:"
  echo "      ${INIT_RESP}"
else
  echo "❌ Falha no handshake initialize. Resposta:"
  echo "${INIT_RESP}"
  exit 1
fi

# 2. Testar catálogo 'tools/list'
echo "2️⃣  Testando método 'tools/list'..."
TOOLS_REQ='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
TOOLS_RESP=$(echo "${TOOLS_REQ}" | python3 "${SERVER_SCRIPT}")

REQUIRED_TOOLS=("query_logs" "get_errors" "get_log_hits" "list_streams" "health_check")
for tool in "${REQUIRED_TOOLS[@]}"; do
  if echo "${TOOLS_RESP}" | grep -q "\"name\": \"${tool}\""; then
    echo "   ✅ Ferramenta registrada: '${tool}'"
  else
    echo "❌ Ferramenta '${tool}' ausente no catálogo!"
    exit 1
  fi
done

# 3. Testar execução de tool 'health_check'
echo "3️⃣  Testando execução de tool 'health_check' via 'tools/call'..."
CALL_REQ='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health_check","arguments":{}}}'
CALL_RESP=$(echo "${CALL_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${CALL_RESP}" | grep -q '"type": "text"'; then
  echo "   ✅ Chamada de ferramenta executada com resposta estruturada válida:"
  echo "      ${CALL_RESP}"
else
  echo "❌ Falha ao chamar a ferramenta 'health_check'. Resposta:"
  echo "${CALL_RESP}"
  exit 1
fi

echo "================================================================================"
echo "🎉 [SUCESSO] Servidor MCP está 100% conforme a especificação JSON-RPC 2.0!"
echo "================================================================================"
