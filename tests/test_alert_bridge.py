#!/usr/bin/env python3
"""Unit tests for VictoriaLogs Alert Bridge."""

import json
import os
import sys
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

# Add alert-bridge directory to module search path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../alert-bridge")))

import server  # type: ignore


class TestAlertBridge(unittest.TestCase):
    def setUp(self):
        # Reset state before each test
        with server._STATE_LOCK:
            server.ALERT_CACHE.clear()
            server.RECENT_ALERTS.clear()
            for k in server.STATS:
                server.STATS[k] = 0

    def test_parse_duration_to_seconds(self):
        self.assertEqual(server.parse_duration_to_seconds("30s"), 30)
        self.assertEqual(server.parse_duration_to_seconds("15m"), 900)
        self.assertEqual(server.parse_duration_to_seconds("2h"), 7200)
        self.assertEqual(server.parse_duration_to_seconds("1d"), 86400)
        self.assertEqual(server.parse_duration_to_seconds("60"), 60)
        self.assertEqual(server.parse_duration_to_seconds("", default_sec=1800), 1800)
        self.assertEqual(server.parse_duration_to_seconds("invalid", default_sec=1800), 1800)

    def test_get_alert_fingerprint(self):
        alert = {
            "status": "firing",
            "labels": {
                "alertname": "ContainerOOMKilled",
                "service": "api-service",
                "container_name": "api-1",
            },
        }
        fp = server.get_alert_fingerprint(alert)
        self.assertEqual(fp, "firing:ContainerOOMKilled:api-service:api-1")

    def test_deduplication_and_suppression(self):
        server.REPEAT_INTERVAL_SEC = 10
        server.DEDUPLICATE_ALERTS = True

        fp = "firing:HighErrorRate:web-service:web-1"
        self.assertFalse(server.should_suppress_alert(fp))
        # Second call immediately after should be suppressed
        self.assertTrue(server.should_suppress_alert(fp))

        # When deduplication is disabled
        server.DEDUPLICATE_ALERTS = False
        self.assertFalse(server.should_suppress_alert(fp))

    def test_build_vmui_url(self):
        alert_oom = {
            "labels": {
                "alertname": "ContainerOOMKilled",
                "container_name": "worker-heavy",
            }
        }
        url = server.build_vmui_url(alert_oom)
        self.assertIn("/select/vmui/?#/?g0.expr=", url)
        self.assertIn("worker-heavy", url)

    def test_format_plain_message(self):
        alert = {
            "status": "firing",
            "labels": {
                "alertname": "ContainerOOMKilled",
                "severity": "critical",
                "service": "batch-worker",
                "container_name": "worker-1",
                "host": "mini-pc",
            },
            "annotations": {
                "summary": "Container worker-1 died with OOM",
                "description": "Kernel invoked OOM killer (Exit Code 137).",
            },
            "startsAt": "2026-10-13T03:00:00Z",
        }
        title, body = server.format_plain_message(alert)
        self.assertIn("🚨 [CRITICAL] ContainerOOMKilled", title)
        self.assertIn("Summary: Container worker-1 died with OOM", body)
        self.assertIn("Severity: critical", body)
        self.assertIn("Container: worker-1", body)
        self.assertIn("Host: mini-pc", body)
        self.assertIn("VMUI:", body)

    def test_format_html_message(self):
        alert = {
            "status": "firing",
            "labels": {
                "alertname": "HighErrorRate",
                "severity": "warning",
                "service": "auth-service",
            },
            "annotations": {
                "summary": "Error spike <10% >50%",
                "description": "Elevated 500 error count & failures.",
            },
        }
        html_msg = server.format_html_message(alert)
        self.assertIn("<b>⚠️ [WARNING] HighErrorRate</b>", html_msg)
        # Verify XML/HTML characters were properly escaped
        self.assertIn("&lt;10% &gt;50%", html_msg)
        self.assertIn("&amp; failures.", html_msg)
        self.assertIn('<a href="', html_msg)

    @patch("urllib.request.urlopen")
    def test_dispatch_ntfy(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        server.NTFY_URL = "https://ntfy.sh/test-topic"
        server.NTFY_AUTH_TOKEN = "test-token"

        alert = {
            "status": "firing",
            "labels": {"alertname": "TestAlert", "severity": "critical"},
            "annotations": {"summary": "Critical issue"},
        }

        success = server.dispatch_ntfy(alert)
        self.assertTrue(success)
        mock_urlopen.assert_called_once()
        req = mock_urlopen.call_args[0][0]
        self.assertEqual(req.get_full_url(), "https://ntfy.sh/test-topic")
        self.assertEqual(req.headers["Priority"], "5")
        self.assertEqual(req.headers["Authorization"], "Bearer test-token")

    @patch("urllib.request.urlopen")
    def test_dispatch_telegram(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        server.TELEGRAM_BOT_TOKEN = "123456:FAKE_TOKEN"
        server.TELEGRAM_CHAT_ID = "-100123456"

        alert = {
            "status": "firing",
            "labels": {"alertname": "TestAlert", "severity": "warning"},
            "annotations": {"summary": "Warning issue"},
        }

        success = server.dispatch_telegram(alert)
        self.assertTrue(success)
        mock_urlopen.assert_called_once()
        req = mock_urlopen.call_args[0][0]
        self.assertIn("api.telegram.org/bot123456:FAKE_TOKEN/sendMessage", req.get_full_url())
        payload = json.loads(req.data.decode("utf-8"))
        self.assertEqual(payload["chat_id"], "-100123456")
        self.assertEqual(payload["parse_mode"], "HTML")

    @patch("urllib.request.urlopen")
    def test_dispatch_webhook(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        server.WEBHOOK_URL = "https://webhook.example.com/alerts"

        alert = {
            "status": "firing",
            "labels": {"alertname": "TestAlert", "severity": "info"},
            "annotations": {"summary": "Informational"},
        }

        success = server.dispatch_webhook(alert)
        self.assertTrue(success)
        mock_urlopen.assert_called_once()
        req = mock_urlopen.call_args[0][0]
        self.assertEqual(req.get_full_url(), "https://webhook.example.com/alerts")
        payload = json.loads(req.data.decode("utf-8"))
        self.assertIn("title", payload)
        self.assertIn("content", payload)


class TestAlertBridgeServerLive(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = 19093
        server.PORT = cls.port
        server.NTFY_URL = ""
        server.TELEGRAM_BOT_TOKEN = ""
        server.WEBHOOK_URL = ""
        server.DEDUPLICATE_ALERTS = False

        cls.httpd = server.http.server.ThreadingHTTPServer(("", cls.port), server.AlertHandler)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        time.sleep(0.2)

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def test_health_endpoint(self):
        import urllib.request

        url = f"http://127.0.0.1:{self.port}/health"
        with urllib.request.urlopen(url, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            data = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(data["status"], "healthy")
            self.assertIn("stats", data)

    def test_post_alerts_endpoint(self):
        import urllib.request

        url = f"http://127.0.0.1:{self.port}/api/v2/alerts"
        payload = [
            {
                "status": "firing",
                "labels": {
                    "alertname": "ContainerOOMKilled",
                    "severity": "critical",
                    "container_name": "mock-app",
                },
                "annotations": {
                    "summary": "Mock app killed by OOM",
                    "description": "Exit code 137 triggered",
                },
            }
        ]
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            result = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(result["status"], "success")
            self.assertEqual(result["processed"], 1)

        # Check GET /alerts
        alerts_url = f"http://127.0.0.1:{self.port}/alerts"
        with urllib.request.urlopen(alerts_url, timeout=2) as resp:
            self.assertEqual(resp.status, 200)
            result = json.loads(resp.read().decode("utf-8"))
            self.assertGreaterEqual(result["count"], 1)
            self.assertEqual(result["alerts"][0]["labels"]["alertname"], "ContainerOOMKilled")


if __name__ == "__main__":
    unittest.main()
