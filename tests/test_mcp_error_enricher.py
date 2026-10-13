#!/usr/bin/env python3
"""
Unit tests for the MCP Server query sanitization, error enrichment, and SRE hints module.
"""

import unittest
from unittest.mock import patch
import json
import sys
import os

# Add root directory to path to import mcp.server
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mcp.server import (
    DEFAULT_NOISE_EXCLUSION,
    clean_query,
    enrich_logsql_error,
    extract_time_part,
    strip_ansi,
    parse_timeout,
    process_jsonrpc_request,
    MCPSSEHandler,
    TOOLS,
    tool_health_check,
    tool_field_names,
    tool_field_values,
    tool_get_context_logs,
    tool_get_errors,
    tool_get_log_hits,
    tool_list_streams,
    tool_query_logs,
)


class TestMcpErrorEnricher(unittest.TestCase):

    def test_clean_query(self):
        self.assertEqual(clean_query(""), "")
        self.assertEqual(clean_query("level:error"), "level:error")
        # Newlines and whitespace
        raw = "\n  120363421617257978@g.us\n \t \n"
        self.assertEqual(clean_query(raw), "120363421617257978@g.us")
        # Multiple spaces in the middle of query
        multi = "level:error    AND    status:500\n| keep _time"
        self.assertEqual(clean_query(multi), "level:error AND status:500 | keep _time")

    def test_enrich_quotes_error(self):
        err = (
            'HTTP Error 400 accessing /select/logsql/query: cannot parse query arg '
            '[_time:30m AND (120363421617257978@g.us) | keep ...]: '
            'missing whitespace or \':\' between "120363421617257978" and "@"; '
            'probably, the whole string must be put into quotes; context: [...]'
        )
        enriched = enrich_logsql_error(err, "120363421617257978@g.us\n")
        self.assertIn("💡 **LogsQL Hint (Special Characters):**", enriched)
        self.assertIn('query=\'"120363421617257978@g.us"\'', enriched)
        self.assertIn('_msg:~"120363421617257978@g.us"', enriched)
        self.assertIn('exact:"120363421617257978@g.us"', enriched)

    def test_enrich_unclosed_quote_error(self):
        err = "HTTP Error 400: cannot parse query: unclosed quote at position 15"
        enriched = enrich_logsql_error(err, 'level:"error')
        self.assertIn("💡 **LogsQL Hint (Unclosed Quotes):**", enriched)

    def test_enrich_pipe_error(self):
        err = "HTTP Error 400: cannot parse pipe: unknown pipe 'stast'"
        enriched = enrich_logsql_error(err, "level:error | stast by (host)")
        self.assertIn("💡 **LogsQL Hint (Transformation Pipes):**", enriched)

    def test_no_enrichment_for_generic_error(self):
        err = "Connection failure to VictoriaLogs at http://127.0.0.1:9428: Connection refused"
        enriched = enrich_logsql_error(err, "level:error")
        self.assertEqual(err, enriched)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_with_syntax_error(self, mock_request):
        mock_request.side_effect = RuntimeError(
            'HTTP Error 400 accessing /select/logsql/query: '
            'missing whitespace or \':\' between "120363421617257978" and "@"; '
            'probably, the whole string must be put into quotes'
        )
        result = tool_query_logs({"query": "\n120363421617257978@g.us\n", "time_range": "30m"})
        self.assertIn("❌ Error querying LogsQL:", result)
        self.assertIn("💡 **LogsQL Hint (Special Characters):**", result)
        self.assertIn('query=\'"120363421617257978@g.us"\'', result)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_with_service(self, mock_request):
        mock_request.return_value = '{"_time":"2026-09-04T22:00:00Z","container_name":"evolution-api","level":"info","_msg":"ok"}'
        result = tool_query_logs({"query": '"120363421617257978@g.us"', "service": "evolution-api", "time_range": "30m"})

        # Verify endpoint was called with _stream:{container_name="evolution-api"}
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn('_stream:{container_name="evolution-api"}', called_query)
        self.assertIn('"120363421617257978@g.us"', called_query)
        # Should not display global hint because service was provided
        self.assertNotIn("Query executed globally across the homelab", result)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_global_hint(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-04T22:00:00Z","container_name":"evolution-api","level":"info","_msg":"msg1"}\n'
            '{"_time":"2026-09-04T22:00:01Z","container_name":"nginx","level":"info","_msg":"msg2"}'
        )
        # Call without service
        result = tool_query_logs({"query": "status:200", "time_range": "30m"})
        self.assertIn("💡 **SRE Hint:** Query executed globally across the homelab", result)
        self.assertIn("`evolution-api`", result)
        self.assertIn("`nginx`", result)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_default_noise_exclusion(self, mock_request):
        mock_request.return_value = '{"_time":"2026-09-21T03:00:00Z","container_name":"app","level":"info","_msg":"ok"}'

        # Test generic query without service
        tool_query_logs({"query": "level:error", "time_range": "30m"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn(DEFAULT_NOISE_EXCLUSION, called_query)

        # Test query="*" without service
        tool_query_logs({"query": "*", "time_range": "30m"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn(DEFAULT_NOISE_EXCLUSION, called_query)

        # Test explicit service="cadvisor" -> noise exclusion must NOT be added
        tool_query_logs({"query": "*", "service": "cadvisor", "time_range": "30m"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertNotIn(DEFAULT_NOISE_EXCLUSION, called_query)
        self.assertIn('_stream:{container_name="cadvisor"}', called_query)

        # Test query mentioning "docker-stats" -> noise exclusion must NOT be added
        tool_query_logs({"query": 'service:"docker-stats"', "time_range": "30m"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertNotIn(DEFAULT_NOISE_EXCLUSION, called_query)

    @patch("mcp.server.make_request")
    def test_tool_get_errors_default_noise_exclusion(self, mock_request):
        mock_request.return_value = '{"_time":"2026-09-21T03:00:00Z","container_name":"app","level":"error","_msg":"err"}'

        # Without service -> noise exclusion should be added
        tool_get_errors({"time_range": "1h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn(DEFAULT_NOISE_EXCLUSION, called_query)

        # With service="app" -> noise exclusion should NOT be added
        tool_get_errors({"service": "app", "time_range": "1h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertNotIn(DEFAULT_NOISE_EXCLUSION, called_query)
        self.assertIn('_stream:{container_name="app"}', called_query)

    @patch("mcp.server.make_request")
    def test_tool_get_context_logs_default_noise_exclusion(self, mock_request):
        mock_request.return_value = '{"_time":"2026-09-21T03:00:00Z","container_name":"app","level":"info","_msg":"context"}'

        # Without service -> noise exclusion should be added
        tool_get_context_logs({"target_timestamp": "2026-09-21T03:00:00Z"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn(DEFAULT_NOISE_EXCLUSION, called_query)

        # With service -> noise exclusion should NOT be added
        tool_get_context_logs({"target_timestamp": "2026-09-21T03:00:00Z", "service": "app"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertNotIn(DEFAULT_NOISE_EXCLUSION, called_query)
        self.assertIn('_stream:{container_name="app"}', called_query)

    @patch("mcp.server.make_request")
    def test_tool_get_log_hits_default_noise_exclusion(self, mock_request):
        mock_request.return_value = '{"hits":[{"time":"2026-09-21T03:00:00Z","total":10}]}'

        # Generic query "*" -> noise exclusion should be added
        tool_get_log_hits({"query": "*", "time_range": "1h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn(DEFAULT_NOISE_EXCLUSION, called_query)

        # Query targeting cadvisor -> noise exclusion should NOT be added
        tool_get_log_hits({"query": 'service:"cadvisor"', "time_range": "1h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertNotIn(DEFAULT_NOISE_EXCLUSION, called_query)

    @patch("mcp.server.make_request")
    def test_tool_get_log_hits_max_buckets(self, mock_request):
        # 20 mock buckets
        mock_hits = [{"time": f"2026-09-21T03:{i:02d}:00Z", "total": i + 1} for i in range(20)]
        mock_request.return_value = json.dumps({"hits": mock_hits})

        # 1. Default max_buckets (15): should show 15 and warn about 20
        res_default = tool_get_log_hits({"query": 'service:"app"'})
        self.assertIn("Showing last 15 of 20 time buckets", res_default)
        self.assertIn("2026-09-21T03:19:00Z", res_default)
        self.assertNotIn("2026-09-21T03:00:00Z", res_default)  # First bucket omitted

        # 2. Custom max_buckets (5): should show 5 and warn about 20
        res_5 = tool_get_log_hits({"query": 'service:"app"', "max_buckets": 5})
        self.assertIn("Showing last 5 of 20 time buckets", res_5)
        self.assertIn("2026-09-21T03:19:00Z", res_5)
        self.assertNotIn("2026-09-21T03:14:00Z", res_5)

        # 3. Fits within max_buckets (e.g. max_buckets=30): should show all 20
        res_30 = tool_get_log_hits({"query": 'service:"app"', "max_buckets": 30})
        self.assertIn("Showing all 20 time buckets", res_30)
        self.assertIn("2026-09-21T03:00:00Z", res_30)
        self.assertIn("2026-09-21T03:19:00Z", res_30)

        # 4. Invalid max_buckets: defaults gracefully to 15
        res_invalid = tool_get_log_hits({"query": 'service:"app"', "max_buckets": "invalid"})
        self.assertIn("Showing last 15 of 20 time buckets", res_invalid)

    def test_strip_ansi(self):
        self.assertEqual(strip_ansi(""), "")
        self.assertEqual(strip_ansi("plain text"), "plain text")
        self.assertEqual(strip_ansi("\x1b[31mError message\x1b[0m"), "Error message")
        self.assertEqual(strip_ansi("\x1b[1;32m[SUCCESS]\x1b[0m \x1b[38;5;208mwarning\x1b[0m"), "[SUCCESS] warning")
        self.assertEqual(strip_ansi("\x1b[2K\x1b[1GLine cleared"), "Line cleared")

    def test_extract_time_part(self):
        self.assertEqual(extract_time_part(""), "")
        self.assertEqual(extract_time_part("2026-09-21T14:18:42Z"), "14:18:42")
        self.assertEqual(extract_time_part("2026-09-21T14:18:42.123456Z"), "14:18:42")
        self.assertEqual(extract_time_part("2026-09-21 14:18:42"), "14:18:42")
        self.assertEqual(extract_time_part("14:18:42"), "14:18:42")

    @patch("mcp.server.make_request")
    def test_tool_query_logs_consecutive_collapse(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-21T14:18:40Z","container_name":"app","level":"info","_msg":"Heartbeat OK"}\n'
            '{"_time":"2026-09-21T14:18:41Z","container_name":"app","level":"info","_msg":"Heartbeat OK"}\n'
            '{"_time":"2026-09-21T14:18:42Z","container_name":"app","level":"info","_msg":"Heartbeat OK"}\n'
            '{"_time":"2026-09-21T14:18:45Z","container_name":"app","level":"info","_msg":"Connection opened"}'
        )
        result = tool_query_logs({"query": "*", "service": "app"})
        self.assertIn("(repeats 3x until 14:18:42)", result)
        self.assertIn("Connection opened", result)
        self.assertIn("records collapsed", result)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_fields_projection(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-21T14:18:40Z","level":"error","http_status":500,"duration_ms":124,"request_id":"req-abc"}'
        )
        result = tool_query_logs({
            "query": "status:500",
            "service": "api-gateway",
            "fields": "http_status, duration_ms, request_id"
        })

        # Verify query had | keep injected with _time and requested fields
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn("| keep _time, http_status, duration_ms, request_id", called_query)

        # Verify key-value compact output
        self.assertIn("http_status=500", result)
        self.assertIn("duration_ms=124", result)
        self.assertIn("request_id=req-abc", result)

    @patch("mcp.server.make_request")
    def test_tool_query_logs_fields_collapse(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-21T14:18:40Z","http_status":502,"error_code":"BAD_GATEWAY"}\n'
            '{"_time":"2026-09-21T14:18:41Z","http_status":502,"error_code":"BAD_GATEWAY"}\n'
            '{"_time":"2026-09-21T14:18:45Z","http_status":200,"error_code":"NONE"}'
        )
        result = tool_query_logs({
            "query": "*",
            "service": "nginx",
            "fields": ["http_status", "error_code"]
        })
        self.assertIn("(repeats 2x until 14:18:41)", result)
        self.assertIn("http_status=502 error_code=BAD_GATEWAY", result)
        self.assertIn("http_status=200 error_code=NONE", result)

    @patch("mcp.server.make_request")
    def test_tool_get_context_logs_consecutive_collapse(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-10T14:18:38Z","container_name":"app","level":"info","_msg":"polling"}\n'
            '{"_time":"2026-09-10T14:18:39Z","container_name":"app","level":"info","_msg":"polling"}\n'
            '{"_time":"2026-09-10T14:18:41Z","container_name":"app","level":"error","_msg":"crash occurred"}'
        )
        result = tool_get_context_logs({
            "target_timestamp": "2026-09-10T14:18:41Z",
            "service": "app",
            "window_seconds": 10
        })
        self.assertIn("(repeats 2x until 14:18:39)", result)
        self.assertIn("🎯 **[TARGET / INCIDENT]**", result)
        self.assertIn("crash occurred", result)

    @patch("mcp.server.make_request")
    def test_strip_ansi_in_tools(self, mock_request):
        mock_request.return_value = (
            '{"_time":"2026-09-21T14:18:40Z","container_name":"app","level":"error","_msg":"\x1b[31mFatal Exception\x1b[0m: connection closed"}'
        )
        result_query = tool_query_logs({"query": "level:error", "service": "app"})
        self.assertNotIn("\x1b[31m", result_query)
        self.assertIn("Fatal Exception: connection closed", result_query)

        result_err = tool_get_errors({"service": "app"})
        self.assertNotIn("\x1b[31m", result_err)
        self.assertIn("Fatal Exception: connection closed", result_err)

    @patch("mcp.server.make_request")
    def test_tool_field_names_unscoped(self, mock_request):
        mock_request.return_value = json.dumps({
            "values": [
                {"value": "_msg", "hits": 100},
                {"value": "service", "hits": 100},
                {"value": "level", "hits": 50},
            ]
        })
        result = tool_field_names({"time_range": "12h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertEqual(called_query, "_time:12h")
        self.assertIn("### 🏷️ Indexed Fields in VictoriaLogs (Window: 12h)", result)
        self.assertIn("- `_msg` (100 logs)", result)
        self.assertIn("- `level` (50 logs)", result)

    @patch("mcp.server.make_request")
    def test_tool_field_names_with_service(self, mock_request):
        mock_request.return_value = json.dumps({
            "values": [
                {"value": "_msg", "hits": 40},
                {"value": "structured.user_id", "hits": 40},
                {"value": "structured.status", "hits": 20},
            ]
        })
        result = tool_field_names({"service": "evolution-api", "time_range": "24h"})
        args, kwargs = mock_request.call_args
        called_query = kwargs.get("params", {}).get("query", "") if kwargs.get("params") else args[1].get("query", "")
        self.assertIn('_stream:{container_name="evolution-api"}', called_query)
        self.assertIn('_stream:{service="evolution-api"}', called_query)
        self.assertIn("### 🏷️ Indexed Fields in VictoriaLogs for `evolution-api` (Window: 24h)", result)
        self.assertIn("- `structured.user_id` (40 logs)", result)

    @patch("mcp.server.make_request")
    def test_tool_field_names_empty_service(self, mock_request):
        mock_request.return_value = json.dumps({"values": []})
        result = tool_field_names({"service": "unknown-svc", "time_range": "24h"})
        self.assertIn("ℹ️ No fields found for service `unknown-svc` in 24h window.", result)

    @patch("mcp.server.make_request")
    def test_tool_field_names_syntax_error(self, mock_request):
        mock_request.side_effect = RuntimeError("HTTP Error 400: unclosed quote at position 10")
        result = tool_field_names({"service": 'bad"service', "time_range": "24h"})
        self.assertIn("❌ Error listing field names:", result)
        self.assertIn("💡 **LogsQL Hint (Unclosed Quotes):**", result)

    def test_parse_timeout(self):
        self.assertEqual(parse_timeout({}, default=15), 15)
        self.assertEqual(parse_timeout({"timeout": 45}), 45)
        self.assertEqual(parse_timeout({"timeout": "30"}), 30)
        self.assertEqual(parse_timeout({"timeout": -10}), 1)
        self.assertEqual(parse_timeout({"timeout": 0}), 1)
        self.assertEqual(parse_timeout({"timeout": "invalid"}), 15)
        self.assertEqual(parse_timeout({"timeout": None}, default=20), 20)

    @patch("mcp.server.make_request")
    def test_tool_timeout_forwarding(self, mock_request):
        mock_request.return_value = '{"_time":"2026-10-13T00:00:00Z","level":"info","_msg":"ok"}'

        # 1. query_logs with custom timeout
        tool_query_logs({"query": "*", "timeout": 60})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 60)

        # 2. get_errors with custom timeout
        tool_get_errors({"service": "app", "timeout": 45})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 45)

        # 3. get_context_logs with custom timeout
        tool_get_context_logs({"target_timestamp": "2026-10-13T00:00:00Z", "timeout": 30})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 30)

        # 4. get_log_hits with custom timeout
        mock_request.return_value = '{"hits":[]}'
        tool_get_log_hits({"query": "*", "timeout": 25})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 25)

        # 5. field_names with custom timeout
        mock_request.return_value = '{"values":[]}'
        tool_field_names({"service": "app", "timeout": 50})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 50)

        # 6. field_values with custom timeout
        tool_field_values({"field": "level", "timeout": 35})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 35)

        # 7. health_check with custom timeout
        mock_request.return_value = "OK"
        tool_health_check({"timeout": 10})
        _args, kwargs = mock_request.call_args
        self.assertEqual(kwargs.get("timeout"), 10)

    def test_tools_schema_timeout_presence(self):
        query_tools = [
            "health_check",
            "query_logs",
            "get_errors",
            "get_context_logs",
            "get_log_hits",
            "list_streams",
            "field_names",
            "field_values",
        ]
        tools_dict = {t["name"]: t for t in TOOLS}
        for name in query_tools:
            self.assertIn(name, tools_dict)
            properties = tools_dict[name]["inputSchema"].get("properties", {})
            self.assertIn("timeout", properties, f"Tool '{name}' must include 'timeout' in inputSchema")
            self.assertEqual(properties["timeout"]["type"], "integer")
            self.assertEqual(properties["timeout"]["default"], 15)

    def test_process_jsonrpc_request(self):
        # 1. initialize
        init_req = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
        init_res = process_jsonrpc_request(init_req)
        self.assertIsNotNone(init_res)
        self.assertEqual(init_res["id"], 1)
        self.assertEqual(init_res["result"]["serverInfo"]["name"], "victorialogs-mcp")

        # 2. notifications/initialized
        notif_req = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        self.assertIsNone(process_jsonrpc_request(notif_req))

        # 3. ping
        ping_req = {"jsonrpc": "2.0", "id": 2, "method": "ping"}
        ping_res = process_jsonrpc_request(ping_req)
        self.assertEqual(ping_res, {"jsonrpc": "2.0", "id": 2, "result": {}})

        # 4. tools/list
        list_req = {"jsonrpc": "2.0", "id": 3, "method": "tools/list"}
        list_res = process_jsonrpc_request(list_req)
        self.assertIn("tools", list_res["result"])
        self.assertEqual(len(list_res["result"]["tools"]), 9)

        # 5. tools/call valid
        doc_req = {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "documentation", "arguments": {"query": "filters"}}}
        doc_res = process_jsonrpc_request(doc_req)
        self.assertFalse(doc_res["result"]["isError"])
        self.assertIn("Basic Filters in LogsQL", doc_res["result"]["content"][0]["text"])

        # 6. tools/call unknown
        unk_req = {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "unknown_tool", "arguments": {}}}
        unk_res = process_jsonrpc_request(unk_req)
        self.assertEqual(unk_res["error"]["code"], -32601)

        # 7. unsupported method
        bad_req = {"jsonrpc": "2.0", "id": 6, "method": "unsupported/method"}
        bad_res = process_jsonrpc_request(bad_req)
        self.assertEqual(bad_res["error"]["code"], -32601)

    def test_sse_http_server_endpoints(self):
        import urllib.request
        from http.server import ThreadingHTTPServer
        import threading

        # Start ephemeral test server
        server = ThreadingHTTPServer(("127.0.0.1", 0), MCPSSEHandler)
        server.daemon_threads = True
        port = server.server_address[1]
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()

        base_url = f"http://127.0.0.1:{port}"

        try:
            # 1. GET /health
            req = urllib.request.Request(f"{base_url}/health")
            with urllib.request.urlopen(req, timeout=5) as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(data["status"], "ok")
                self.assertEqual(data["mode"], "sse")
                self.assertEqual(data["tools"], 9)

            # 2. OPTIONS /messages (CORS Preflight)
            req = urllib.request.Request(f"{base_url}/messages", method="OPTIONS")
            with urllib.request.urlopen(req, timeout=5) as resp:
                self.assertEqual(resp.status, 204)
                self.assertEqual(resp.headers.get("Access-Control-Allow-Origin"), "*")

            # 3. Direct POST /messages (Fallback direct JSON-RPC execution)
            post_body = json.dumps({"jsonrpc": "2.0", "id": 10, "method": "ping"}).encode("utf-8")
            req = urllib.request.Request(
                f"{base_url}/messages",
                data=post_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                self.assertEqual(resp.status, 200)
                res_data = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(res_data, {"jsonrpc": "2.0", "id": 10, "result": {}})

            # 4. SSE Stream Handshake and Message Delivery
            sse_req = urllib.request.Request(f"{base_url}/sse")
            sse_resp = urllib.request.urlopen(sse_req, timeout=5)
            self.assertEqual(sse_resp.status, 200)
            self.assertIn("text/event-stream", sse_resp.headers.get("Content-Type", ""))

            # Read initial endpoint event: "event: endpoint\ndata: /messages?sessionId=...\n\n"
            line1 = sse_resp.readline().decode("utf-8")  # event: endpoint\n
            line2 = sse_resp.readline().decode("utf-8")  # data: /messages?sessionId=...\n
            line3 = sse_resp.readline().decode("utf-8")  # \n
            self.assertIn("event: endpoint", line1)
            self.assertIn("data: /messages?sessionId=", line2)

            endpoint_path = line2.replace("data:", "").strip()
            session_id = endpoint_path.split("sessionId=")[1]

            # Send JSON-RPC request to POST /messages?sessionId=...
            rpc_body = json.dumps({
                "jsonrpc": "2.0",
                "id": 99,
                "method": "tools/call",
                "params": {"name": "documentation", "arguments": {"query": "stats"}},
            }).encode("utf-8")

            req = urllib.request.Request(
                f"{base_url}/messages?sessionId={session_id}",
                data=rpc_body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as post_res:
                self.assertEqual(post_res.status, 202)

            # Read event delivered over SSE connection
            event_line = sse_resp.readline().decode("utf-8")  # event: message\n
            data_line = sse_resp.readline().decode("utf-8")   # data: {json}\n
            _blank = sse_resp.readline().decode("utf-8")      # \n

            self.assertIn("event: message", event_line)
            delivered = json.loads(data_line.replace("data:", "").strip())
            self.assertEqual(delivered["id"], 99)
            self.assertFalse(delivered["result"]["isError"])
            self.assertIn("stats", delivered["result"]["content"][0]["text"])

            sse_resp.close()

        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
