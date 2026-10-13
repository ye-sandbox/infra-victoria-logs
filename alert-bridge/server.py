#!/usr/bin/env python3
"""Lightweight Alertmanager-compatible Notification Bridge for vmalert.

Zero external dependencies (pure Python 3 standard library).
Receives Prometheus Alertmanager alert payloads from vmalert (POST /api/v2/alerts)
and dispatches human-readable alerts to:
- ntfy (push notifications for mobile / desktop)
- Telegram (bot messages formatted as HTML cards)
- Generic Webhook (Discord, Slack, n8n, Home Assistant)

Features:
- Configurable channel routing and auto-discovery via environment variables.
- Alert deduplication and anti-flap rate limiting.
- VictoriaLogs VMUI deep links for instant log triage.
- Healthcheck endpoint (GET /health) for container orchestration.
- Audit history inspection (GET /alerts).
"""

from __future__ import annotations

import html
import http.server
import json
import logging
import os
import re
import signal
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s [%(levelname)s] [alert-bridge] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("alert-bridge")

# Global Configuration
PORT = int(os.getenv("ALERT_BRIDGE_HTTP_PORT", os.getenv("PORT", "9093")))
VICTORIALOGS_URL = os.getenv("VICTORIALOGS_URL", "http://127.0.0.1:9428").rstrip("/")

NTFY_URL = os.getenv("NTFY_URL", "").strip()
NTFY_AUTH_TOKEN = os.getenv("NTFY_AUTH_TOKEN", "").strip()
NTFY_USER = os.getenv("NTFY_USER", "").strip()
NTFY_PASSWORD = os.getenv("NTFY_PASSWORD", "").strip()

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "").strip()

WEBHOOK_URL = os.getenv("WEBHOOK_URL", "").strip()

# Channels filter (comma separated, e.g. "ntfy,telegram,webhook"). Empty = auto-detect
CONFIGURED_CHANNELS = [
    c.strip().lower() for c in os.getenv("ALERT_CHANNELS", "").split(",") if c.strip()
]


def parse_duration_to_seconds(val: str, default_sec: int = 1800) -> int:
    """Parses strings like '30s', '15m', '2h', or integer seconds into integer seconds."""
    if not val:
        return default_sec
    val = val.strip().lower()
    m = re.match(r"^(\d+)([smhd]?)$", val)
    if not m:
        try:
            return int(val)
        except ValueError:
            return default_sec
    num, unit = int(m.group(1)), m.group(2)
    multipliers = {"s": 1, "m": 60, "h": 3600, "d": 86400, "": 1}
    return num * multipliers.get(unit, 1)


REPEAT_INTERVAL_SEC = parse_duration_to_seconds(
    os.getenv("ALERT_REPEAT_INTERVAL", "30m"), default_sec=1800
)
DEDUPLICATE_ALERTS = os.getenv("ALERT_DEDUPLICATE", "true").lower() in ("1", "true", "yes")

# State & In-Memory Store
START_TIME = time.time()
_STATE_LOCK = threading.Lock()
RECENT_ALERTS: List[Dict[str, Any]] = []
ALERT_CACHE: Dict[str, float] = {}  # fingerprint -> timestamp
STATS = {
    "received": 0,
    "sent_ntfy": 0,
    "sent_telegram": 0,
    "sent_webhook": 0,
    "suppressed_duplicates": 0,
    "dispatch_errors": 0,
}


def build_vmui_url(alert: Dict[str, Any]) -> str:
    """Builds a direct link to VictoriaLogs VMUI query view based on alert labels."""
    labels = alert.get("labels", {})
    service = labels.get("service") or labels.get("app")
    container = labels.get("container_name")

    query_parts = []
    if container:
        query_parts.append(f'_stream:{{container_name="{container}"}}')
    elif service:
        query_parts.append(f'_stream:{{service="{service}"}}')

    alertname = labels.get("alertname", "")
    if "oom" in alertname.lower():
        query_parts.append('oom_killed:"true" OR exit_code:"137"')
    elif "error" in alertname.lower():
        query_parts.append('level:"error"')
    elif "crash" in alertname.lower():
        query_parts.append('action:"die"')

    query = " AND ".join(query_parts) if query_parts else 'level:"error"'
    encoded_query = urllib.parse.quote(query)
    return f"{VICTORIALOGS_URL}/select/vmui/?#/?g0.expr={encoded_query}"


def format_timestamp(iso_str: Optional[str]) -> str:
    """Formats ISO timestamp string to readable UTC format."""
    if not iso_str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    try:
        clean_str = iso_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(clean_str)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        return iso_str


def get_alert_fingerprint(alert: Dict[str, Any]) -> str:
    """Generates unique fingerprint for alert deduplication."""
    status = alert.get("status", "firing")
    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    service = labels.get("service", "")
    container = labels.get("container_name", "")
    return f"{status}:{alertname}:{service}:{container}"


def should_suppress_alert(fingerprint: str) -> bool:
    """Checks if alert should be suppressed due to repeat interval."""
    if not DEDUPLICATE_ALERTS:
        return False
    now = time.time()
    with _STATE_LOCK:
        last_sent = ALERT_CACHE.get(fingerprint)
        if last_sent and (now - last_sent) < REPEAT_INTERVAL_SEC:
            return True
        ALERT_CACHE[fingerprint] = now
        # Prune old cache items
        if len(ALERT_CACHE) > 1000:
            threshold = now - (REPEAT_INTERVAL_SEC * 2)
            expired = [k for k, ts in ALERT_CACHE.items() if ts < threshold]
            for k in expired:
                del ALERT_CACHE[k]
        return False


def format_plain_message(alert: Dict[str, Any]) -> Tuple[str, str]:
    """Returns (title, text_body) for plain text formats like ntfy and Webhook."""
    status = alert.get("status", "firing").lower()
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})

    severity = labels.get("severity", "warning").lower()
    alertname = labels.get("alertname", "VictoriaLogsAlert")
    summary = annotations.get("summary") or annotations.get("message") or alertname
    description = annotations.get("description", "")
    starts_at = format_timestamp(alert.get("startsAt"))
    vmui_url = build_vmui_url(alert)

    if status == "resolved":
        emoji = "✅"
        badge = "RESOLVED"
    elif severity == "critical":
        emoji = "🚨"
        badge = "CRITICAL"
    elif severity == "warning":
        emoji = "⚠️"
        badge = "WARNING"
    else:
        emoji = "ℹ️"
        badge = "INFO"

    title = f"{emoji} [{badge}] {alertname}"

    lines = [
        f"{title}",
        "────────────────────────────────────────",
        f"Summary: {summary}",
    ]
    if description and description != summary:
        lines.append(f"Description: {description}")

    lines.append("")
    lines.append(f"• Severity: {severity}")
    if "service" in labels:
        lines.append(f"• Service: {labels['service']}")
    if "container_name" in labels:
        lines.append(f"• Container: {labels['container_name']}")
    if "host" in labels:
        lines.append(f"• Host: {labels['host']}")
    lines.append(f"• Time: {starts_at}")

    lines.append("")
    lines.append(f"🔍 VMUI: {vmui_url}")

    return title, "\n".join(lines)


def format_html_message(alert: Dict[str, Any]) -> str:
    """Formats alert into rich HTML card for Telegram."""
    status = alert.get("status", "firing").lower()
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})

    severity = labels.get("severity", "warning").lower()
    alertname = labels.get("alertname", "VictoriaLogsAlert")
    summary = annotations.get("summary") or annotations.get("message") or alertname
    description = annotations.get("description", "")
    starts_at = format_timestamp(alert.get("startsAt"))
    vmui_url = build_vmui_url(alert)

    if status == "resolved":
        emoji = "✅"
        badge = "RESOLVED"
    elif severity == "critical":
        emoji = "🚨"
        badge = "CRITICAL"
    elif severity == "warning":
        emoji = "⚠️"
        badge = "WARNING"
    else:
        emoji = "ℹ️"
        badge = "INFO"

    esc_alertname = html.escape(str(alertname))
    esc_summary = html.escape(str(summary))
    esc_desc = html.escape(str(description))
    esc_severity = html.escape(str(severity))
    esc_starts_at = html.escape(str(starts_at))

    lines = [
        f"<b>{emoji} [{badge}] {esc_alertname}</b>",
        "───────────────────────────",
        f"<b>Summary:</b> {esc_summary}",
    ]
    if description and description != summary:
        lines.append(f"<b>Description:</b> {esc_desc}")

    lines.append("")
    lines.append(f"• <b>Severity:</b> <code>{esc_severity}</code>")
    if "service" in labels:
        lines.append(f"• <b>Service:</b> <code>{html.escape(str(labels['service']))}</code>")
    if "container_name" in labels:
        lines.append(f"• <b>Container:</b> <code>{html.escape(str(labels['container_name']))}</code>")
    if "host" in labels:
        lines.append(f"• <b>Host:</b> <code>{html.escape(str(labels['host']))}</code>")
    lines.append(f"• <b>Time:</b> {esc_starts_at}")

    lines.append("")
    lines.append(f'🔗 <a href="{html.escape(vmui_url)}">Open Query in VictoriaLogs VMUI</a>')

    return "\n".join(lines)


# Dispatchers


def dispatch_ntfy(alert: Dict[str, Any]) -> bool:
    """Sends notification to ntfy server via HTTP POST."""
    if not NTFY_URL:
        return False

    title, body = format_plain_message(alert)
    status = alert.get("status", "firing").lower()
    severity = alert.get("labels", {}).get("severity", "warning").lower()
    vmui_url = build_vmui_url(alert)

    headers = {
        "Title": title,
        "Click": vmui_url,
    }

    if status == "resolved":
        headers["Priority"] = "2"
        headers["Tags"] = "white_check_mark,resolved"
    elif severity == "critical":
        headers["Priority"] = "5"
        headers["Tags"] = "rotating_light,fire"
    elif severity == "warning":
        headers["Priority"] = "4"
        headers["Tags"] = "warning"
    else:
        headers["Priority"] = "3"
        headers["Tags"] = "information_source"

    if NTFY_AUTH_TOKEN:
        headers["Authorization"] = f"Bearer {NTFY_AUTH_TOKEN}"
    elif NTFY_USER and NTFY_PASSWORD:
        import base64

        userpass = f"{NTFY_USER}:{NTFY_PASSWORD}".encode()
        headers["Authorization"] = f"Basic {base64.b64encode(userpass).decode()}"

    req = urllib.request.Request(
        NTFY_URL,
        data=body.encode("utf-8"),
        headers=headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in (200, 201, 204):
                logger.info("Notification successfully sent to ntfy: %s", title)
                return True
            logger.error("ntfy returned unexpected status %s", resp.status)
    except urllib.error.URLError as e:
        logger.error("Failed to send notification to ntfy (%s): %s", NTFY_URL, e)
    return False


def dispatch_telegram(alert: Dict[str, Any]) -> bool:
    """Sends notification to Telegram via Bot API sendMessage."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False

    text = format_html_message(alert)
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"

    payload = {
        "chat_id": TELEGRAM_CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": False,
    }
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                logger.info("Notification successfully sent to Telegram chat %s", TELEGRAM_CHAT_ID)
                return True
            logger.error("Telegram returned unexpected status %s", resp.status)
    except urllib.error.URLError as e:
        logger.error("Failed to send notification to Telegram: %s", e)
    return False


def dispatch_webhook(alert: Dict[str, Any]) -> bool:
    """Sends notification to generic webhook URL (Discord, Slack, n8n, etc.)."""
    if not WEBHOOK_URL:
        return False

    title, body = format_plain_message(alert)
    vmui_url = build_vmui_url(alert)

    payload = {
        "title": title,
        "content": body,  # Discord compatibility
        "text": body,  # Slack compatibility
        "vmui_url": vmui_url,
        "alert": alert,
    }
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        WEBHOOK_URL,
        data=data,
        headers={"Content-Type": "application/json", "User-Agent": "victoria-logs-alert-bridge"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in (200, 201, 204):
                logger.info("Notification successfully sent to generic Webhook: %s", title)
                return True
            logger.error("Webhook returned unexpected status %s", resp.status)
    except urllib.error.URLError as e:
        logger.error("Failed to send notification to Webhook: %s", e)
    return False


def process_single_alert(alert: Dict[str, Any]) -> None:
    """Processes, deduplicates, and routes an individual alert to configured channels."""
    fingerprint = get_alert_fingerprint(alert)
    title, plain_msg = format_plain_message(alert)

    if should_suppress_alert(fingerprint):
        logger.info("Suppressed duplicate alert within repeat interval: %s", fingerprint)
        with _STATE_LOCK:
            STATS["suppressed_duplicates"] += 1
        return

    channels_to_use = []
    if CONFIGURED_CHANNELS:
        channels_to_use = CONFIGURED_CHANNELS
    else:
        # Auto-discovery
        if NTFY_URL:
            channels_to_use.append("ntfy")
        if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
            channels_to_use.append("telegram")
        if WEBHOOK_URL:
            channels_to_use.append("webhook")

    if not channels_to_use:
        logger.info(
            "(NO_CHANNELS_CONFIGURED) Logged alert locally:\n%s",
            plain_msg,
        )
        return

    sent_any = False
    for ch in channels_to_use:
        if ch == "ntfy":
            if dispatch_ntfy(alert):
                with _STATE_LOCK:
                    STATS["sent_ntfy"] += 1
                sent_any = True
        elif ch == "telegram":
            if dispatch_telegram(alert):
                with _STATE_LOCK:
                    STATS["sent_telegram"] += 1
                sent_any = True
        elif ch == "webhook":
            if dispatch_webhook(alert):
                with _STATE_LOCK:
                    STATS["sent_webhook"] += 1
                sent_any = True

    if not sent_any:
        with _STATE_LOCK:
            STATS["dispatch_errors"] += 1


class AlertHandler(http.server.BaseHTTPRequestHandler):
    """HTTP Request Handler implementing Alertmanager v2/v1 endpoints."""

    def log_message(self, format: str, *args: Any) -> None:
        """Redirects default HTTP logging to python logger."""
        logger.debug("%s - - [%s] %s", self.address_string(), self.log_date_time_string(), format % args)

    def _send_json(self, status_code: int, data: Dict[str, Any]) -> None:
        response_body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)

    def do_GET(self) -> None:
        parsed_path = urllib.parse.urlparse(self.path).path

        if parsed_path in ("/health", "/healthz"):
            uptime = int(time.time() - START_TIME)
            with _STATE_LOCK:
                stats_copy = dict(STATS)
            self._send_json(
                200,
                {
                    "status": "healthy",
                    "uptime_seconds": uptime,
                    "stats": stats_copy,
                    "active_channels": {
                        "ntfy": bool(NTFY_URL),
                        "telegram": bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID),
                        "webhook": bool(WEBHOOK_URL),
                    },
                },
            )
            return

        if parsed_path == "/alerts":
            with _STATE_LOCK:
                alerts_copy = list(RECENT_ALERTS)
            self._send_json(200, {"count": len(alerts_copy), "alerts": alerts_copy})
            return

        self._send_json(404, {"error": "Not found", "path": self.path})

    def do_POST(self) -> None:
        parsed_path = urllib.parse.urlparse(self.path).path

        if parsed_path in ("/api/v2/alerts", "/api/v1/alerts", "/alerts"):
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length <= 0:
                self._send_json(400, {"error": "Empty request body"})
                return

            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
            except Exception as e:
                self._send_json(400, {"error": f"Invalid JSON payload: {e}"})
                return

            alerts_list: List[Dict[str, Any]] = []
            if isinstance(data, list):
                alerts_list = [item for item in data if isinstance(item, dict)]
            elif isinstance(data, dict):
                # Handle single alert or wrapper object
                if "alerts" in data and isinstance(data["alerts"], list):
                    alerts_list = [item for item in data["alerts"] if isinstance(item, dict)]
                else:
                    alerts_list = [data]

            with _STATE_LOCK:
                STATS["received"] += len(alerts_list)
                for alert in alerts_list:
                    RECENT_ALERTS.insert(0, alert)
                if len(RECENT_ALERTS) > 50:
                    del RECENT_ALERTS[50:]

            # Dispatch alerts asynchronously or in loop
            for alert in alerts_list:
                try:
                    process_single_alert(alert)
                except Exception as e:
                    logger.exception("Error processing alert: %s", e)
                    with _STATE_LOCK:
                        STATS["dispatch_errors"] += 1

            self._send_json(200, {"status": "success", "processed": len(alerts_list)})
            return

        self._send_json(404, {"error": "Not found", "path": self.path})


def run_server(port: int = PORT) -> None:
    server_address = ("", port)
    httpd = http.server.ThreadingHTTPServer(server_address, AlertHandler)
    logger.info("VictoriaLogs Alert Bridge started on port %s", port)
    logger.info("Configured channels: ntfy=%s, telegram=%s, webhook=%s", bool(NTFY_URL), bool(TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID), bool(WEBHOOK_URL))
    logger.info("Repeat interval: %ss, VictoriaLogs URL: %s", REPEAT_INTERVAL_SEC, VICTORIALOGS_URL)

    def shutdown_handler(signum: int, frame: Any) -> None:
        logger.info("Received termination signal (%s). Shutting down server...", signum)
        threading.Thread(target=httpd.shutdown).start()

    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)

    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
        logger.info("Alert Bridge stopped cleanly.")


if __name__ == "__main__":
    run_server()
