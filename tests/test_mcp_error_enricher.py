#!/usr/bin/env python3
"""
Unit tests for the MCP Server query sanitization, error enrichment, and SRE hints module.
"""

import unittest
from unittest.mock import patch
import sys
import os

# Add root directory to path to import mcp.server
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mcp.server import clean_query, enrich_logsql_error, tool_query_logs


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


if __name__ == "__main__":
    unittest.main()
