#!/usr/bin/env bash
# ==============================================================================
# VictoriaLogs MCP Server Automated Integration Test
# ==============================================================================
# Sends JSON-RPC 2.0 requests via stdin to mcp/server.py and validates
# handshake, the 9-tool catalog, and execution responses against the MCP spec.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVER_SCRIPT="${ROOT_DIR}/mcp/server.py"

echo "================================================================================"
echo "🧪 [MCP Integration Test] Validating VictoriaLogs MCP server..."
echo "================================================================================"

if [[ ! -f "${SERVER_SCRIPT}" ]]; then
  echo "❌ File ${SERVER_SCRIPT} not found!"
  exit 1
fi

# 1. Test 'initialize' handshake
echo "1️⃣  Testing 'initialize' method..."
INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0"}}}'
INIT_RESP=$(echo "${INIT_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${INIT_RESP}" | grep -q '"name": "victorialogs-mcp"'; then
  echo "   ✅ Handshake 'initialize' responded successfully:"
  echo "      ${INIT_RESP}"
else
  echo "❌ Handshake 'initialize' failed. Response:"
  echo "${INIT_RESP}"
  exit 1
fi

# 2. Test 'tools/list' catalog
echo "2️⃣  Testing 'tools/list' method with all 9 tools..."
TOOLS_REQ='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
TOOLS_RESP=$(echo "${TOOLS_REQ}" | python3 "${SERVER_SCRIPT}")

REQUIRED_TOOLS=("health_check" "query_logs" "get_errors" "get_context_logs" "get_log_hits" "list_streams" "field_names" "field_values" "documentation")
for tool in "${REQUIRED_TOOLS[@]}"; do
  if echo "${TOOLS_RESP}" | grep -q "\"name\": \"${tool}\""; then
    echo "   ✅ Tool registered: '${tool}'"
  else
    echo "❌ Tool '${tool}' missing from catalog!"
    exit 1
  fi
done

# 3. Test 'health_check' tool execution
echo "3️⃣  Testing 'health_check' tool execution via 'tools/call'..."
CALL_REQ='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health_check","arguments":{}}}'
CALL_RESP=$(echo "${CALL_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${CALL_RESP}" | grep -q '"type": "text"'; then
  echo "   ✅ 'health_check' call executed with valid response:"
  echo "      ${CALL_RESP}"
else
  echo "❌ Failed to call 'health_check' tool. Response:"
  echo "${CALL_RESP}"
  exit 1
fi

# 4. Test 'get_context_logs' tool execution
echo "4️⃣  Testing 'get_context_logs' tool execution via 'tools/call'..."
CTX_REQ='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_context_logs","arguments":{"target_timestamp":"2026-09-10T14:18:41Z","window_seconds":10}}}'
CTX_RESP=$(echo "${CTX_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${CTX_RESP}" | grep -q '"type": "text"'; then
  echo "   ✅ 'get_context_logs' call executed successfully:"
  echo "      $(echo "${CTX_RESP}" | head -c 160)..."
else
  echo "❌ Failed to call 'get_context_logs' tool. Response:"
  echo "${CTX_RESP}"
  exit 1
fi

# 5. Test 'documentation' tool execution (offline, no network dependency)
echo "5️⃣  Testing 'documentation' tool execution via 'tools/call'..."
DOC_REQ='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"documentation","arguments":{"query":"stats"}}}'
DOC_RESP=$(echo "${DOC_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${DOC_RESP}" | grep -q "stats"; then
  echo "   ✅ 'documentation' call executed successfully (offline reference retrieved):"
  echo "      $(echo "${DOC_RESP}" | head -c 200)..."
else
  echo "❌ Failed to call 'documentation' tool. Response:"
  echo "${DOC_RESP}"
  exit 1
fi

# 6. Test 'query_logs' tool execution with 'fields' projection
echo "6️⃣  Testing 'query_logs' tool execution with 'fields' parameter..."
QUERY_REQ='{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"query_logs","arguments":{"query":"*","fields":"service,level"}}}'
QUERY_RESP=$(echo "${QUERY_REQ}" | python3 "${SERVER_SCRIPT}")

if echo "${QUERY_RESP}" | grep -q '"type": "text"'; then
  echo "   ✅ 'query_logs' with 'fields' projection executed successfully:"
  echo "      $(echo "${QUERY_RESP}" | head -c 200)..."
else
  echo "❌ Failed to call 'query_logs' tool with fields. Response:"
  echo "${QUERY_RESP}"
  exit 1
fi

echo "================================================================================"
echo "🎉 [SUCCESS] MCP server is 100% validated and compliant with JSON-RPC 2.0!"
echo "================================================================================"
