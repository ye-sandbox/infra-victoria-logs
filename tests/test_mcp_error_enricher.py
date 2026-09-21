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
    tool_field_names,
    tool_get_context_logs,
    tool_get_errors,
    tool_get_log_hits,
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


if __name__ == "__main__":
    unittest.main()
