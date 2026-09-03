#!/usr/bin/env python3
"""
VictoriaLogs Model Context Protocol (MCP) Server
================================================
Servidor MCP leve e pronto para produção para o VictoriaLogs.
Permite que assistentes e agentes de IA (Claude Code, Antigravity, Cursor, Roo Code)
consultem e investiguem logs nativamente via protocolo stdio JSON-RPC 2.0.

Zero dependências externas (Pure Python 3).
"""

import sys
import os
import json
import base64
import urllib.request
import urllib.error
import urllib.parse
from typing import Any, Dict, List, Optional


def load_env() -> Dict[str, str]:
    """Carrega variáveis de ambiente do .env se existir."""
    env_vars = {}
    current_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(current_dir, ".env"),
        os.path.join(os.path.dirname(current_dir), ".env"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            env_vars[k.strip()] = v.strip().strip("'\"")
            except Exception:
                pass
            break
    return env_vars


ENV = load_env()


def get_config(key: str, default: str = "") -> str:
    return os.environ.get(key) or ENV.get(key, default)


VL_HOST = get_config("VICTORIALOGS_HTTP_HOST", "127.0.0.1")
VL_PORT = get_config("VICTORIALOGS_HTTP_PORT", "9428")
VL_BASE_URL = get_config("VICTORIALOGS_URL", f"http://{VL_HOST}:{VL_PORT}").rstrip("/")
AUTH_USER = get_config("VICTORIALOGS_AUTH_USERNAME", "")
AUTH_PASS = get_config("VICTORIALOGS_AUTH_PASSWORD", "")


def make_request(path: str, params: Optional[Dict[str, Any]] = None, timeout: int = 15) -> str:
    """Executa requisição HTTP para o VictoriaLogs com autenticação opcional."""
    url = f"{VL_BASE_URL}{path}"
    if params:
        query_string = urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
        url = f"{url}?{query_string}"

    req = urllib.request.Request(url, headers={"User-Agent": "VictoriaLogs-MCP/1.0"})
    if AUTH_USER:
        creds = f"{AUTH_USER}:{AUTH_PASS}"
        encoded = base64.b64encode(creds.encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {encoded}")

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else str(e)
        raise RuntimeError(f"HTTP Error {e.code} ao acessar {path}: {body}")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha de conexão com VictoriaLogs em {VL_BASE_URL}: {e.reason}")


# ==============================================================================
# FERRAMENTAS EXPOSTAS PARA O AGENTE DE IA
# ==============================================================================

def tool_health_check(_args: Dict[str, Any]) -> str:
    """Verifica a saúde do VictoriaLogs."""
    try:
        resp = make_request("/health")
        return f"✅ VictoriaLogs está saudável e respondendo em {VL_BASE_URL}.\nStatus: {resp.strip()}"
    except Exception as e:
        return f"❌ VictoriaLogs inacessível em {VL_BASE_URL}.\nErro: {str(e)}"


def tool_query_logs(args: Dict[str, Any]) -> str:
    """Executa consultas LogsQL formatadas e compactas."""
    raw_query = args.get("query", "").strip()
    time_range = args.get("time_range", "1h").strip()
    limit = min(int(args.get("limit", 20)), 100)
    output_format = args.get("format", "markdown").lower()

    if not raw_query:
        return "Erro: parâmetro 'query' obrigatório."

    # Combinar query com janela de tempo se não especificada na query
    query = raw_query
    if time_range and "_time:" not in query:
        query = f"_time:{time_range} AND ({query})"

    try:
        resp = make_request("/select/logsql/query", {"query": query, "limit": limit})
    except Exception as e:
        return f"❌ Erro ao consultar LogsQL: {str(e)}"

    lines = [l.strip() for l in resp.splitlines() if l.strip()]
    if not lines:
        return f"ℹ️ Nenhum log encontrado para a query: `{query}`"

    if output_format == "json":
        return resp

    # Formatar em Markdown limpo para economia de tokens
    out = [f"### 🪵 Resultados para: `{query}` ({len(lines)} registros encontrados)\n"]
    for line in lines:
        try:
            item = json.loads(line)
            ts = item.get("_time") or item.get("timestamp", "")
            if "T" in ts:
                ts = ts.replace("T", " ").split(".")[0]
            lvl = (item.get("level") or "info").upper()
            svc = item.get("service") or item.get("container_name") or "app"
            msg = item.get("_msg") or item.get("message", "")
            
            icon = "🔴" if lvl == "ERROR" else "🟡" if lvl == "WARN" else "⚪"
            out.append(f"{icon} **[{ts}] [{svc}] [{lvl}]** {msg}")
        except Exception:
            out.append(f"- {line}")

    return "\n".join(out)


def tool_get_errors(args: Dict[str, Any]) -> str:
    """Busca rápida de erros e tracebacks multilinha."""
    service = args.get("service", "").strip()
    time_range = args.get("time_range", "1h").strip()
    limit = min(int(args.get("limit", 20)), 50)

    query_parts = ["level:error"]
    if service:
        query_parts.append(f'_stream:{{container_name="{service}"}}')
    if time_range:
        query_parts.append(f"_time:{time_range}")

    query = " AND ".join(query_parts)

    try:
        resp = make_request("/select/logsql/query", {"query": query, "limit": limit})
    except Exception as e:
        return f"❌ Erro ao buscar erros: {str(e)}"

    lines = [l.strip() for l in resp.splitlines() if l.strip()]
    if not lines:
        target = f"no serviço '{service}'" if service else "no homelab"
        return f"✅ Nenhum erro encontrado {target} na janela de {time_range}!"

    out = [f"### 🚨 Erros Detectados ({len(lines)} ocorrências na janela de {time_range})\n"]
    for i, line in enumerate(lines, 1):
        try:
            item = json.loads(line)
            ts = item.get("_time") or item.get("timestamp", "")
            svc = item.get("service") or item.get("container_name") or "app"
            msg = item.get("_msg") or item.get("message", "")

            out.append(f"#### {i}. [{ts}] Serviço: `{svc}`")
            out.append("```text")
            out.append(msg)
            out.append("```\n")
        except Exception:
            out.append(f"- {line}")

    return "\n".join(out)


def tool_get_log_hits(args: Dict[str, Any]) -> str:
    """Obtém série temporal agregada de contagem de eventos via /select/logsql/hits."""
    raw_query = args.get("query", "*").strip()
    time_range = args.get("time_range", "1h").strip()
    step = args.get("step", "5m").strip()

    query = raw_query
    if time_range and "_time:" not in query:
        query = f"_time:{time_range} AND ({query})" if query != "*" else f"_time:{time_range}"

    try:
        resp = make_request("/select/logsql/hits", {"query": query, "step": step})
        data = json.loads(resp)
    except Exception as e:
        return f"❌ Erro ao buscar hits: {str(e)}"

    hits = data.get("hits", [])
    if not hits:
        return f"ℹ️ Nenhum dado retornado para hits com query: `{query}`"

    total_events = sum(h.get("total", 0) for h in hits)
    out = [
        f"### 📈 Histograma de Eventos ({step}/bucket)",
        f"**Query:** `{query}` | **Total:** {total_events} eventos\n",
        "| Intervalo | Contagem |",
        "|---|---:|",
    ]
    for h in hits[-15:]:  # Mostrar até os últimos 15 buckets
        ts = h.get("time", "")
        count = h.get("total", 0)
        out.append(f"| {ts} | {count} |")

    return "\n".join(out)


def tool_list_streams(args: Dict[str, Any]) -> str:
    """Lista os containers, serviços e hosts que estão enviando logs."""
    time_range = args.get("time_range", "24h").strip()
    query = f"_time:{time_range} | stats count() rows by (container_name, service, host) | sort by (rows) desc | limit 25"

    try:
        resp = make_request("/select/logsql/query", {"query": query})
    except Exception as e:
        return f"❌ Erro ao listar streams: {str(e)}"

    lines = [l.strip() for l in resp.splitlines() if l.strip()]
    if not lines:
        return f"ℹ️ Nenhum stream ativo encontrado na janela de {time_range}."

    out = [
        f"### 📡 Streams Ativos (Últimas {time_range})\n",
        "| Container | Serviço | Host | Total de Logs |",
        "|---|---|---|---:|",
    ]
    for line in lines:
        try:
            d = json.loads(line)
            c = d.get("container_name") or "-"
            s = d.get("service") or "-"
            h = d.get("host") or "-"
            r = d.get("rows") or d.get("count", 0)
            out.append(f"| `{c}` | `{s}` | `{h}` | {r} |")
        except Exception:
            pass

    return "\n".join(out)


# Catálogo de ferramentas MCP
TOOLS = [
    {
        "name": "health_check",
        "description": "Verifica se a instância do VictoriaLogs está saudável, conectada e respondendo.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
        "handler": tool_health_check,
    },
    {
        "name": "query_logs",
        "description": "Executa consultas avançadas no VictoriaLogs usando LogsQL. Retorna logs formatados em Markdown compacto para economizar tokens.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Filtro LogsQL. Exemplos: '_stream:{container_name=\"meu-app\"}', 'level:error', 'timeout OR exception'.",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela temporal relativa (ex: '15m', '1h', '24h', '7d'). Padrão: '1h'.",
                    "default": "1h",
                },
                "limit": {
                    "type": "integer",
                    "description": "Limite máximo de registros a retornar (máximo 100, padrão 20).",
                    "default": 20,
                },
                "format": {
                    "type": "string",
                    "enum": ["markdown", "json"],
                    "description": "Formato de saída: 'markdown' (compacto e amigável) ou 'json' (ndjson bruto).",
                    "default": "markdown",
                },
            },
            "required": ["query"],
        },
        "handler": tool_query_logs,
    },
    {
        "name": "get_errors",
        "description": "Busca rápida e estruturada de erros e stack traces de um container/serviço específico ou de todo o homelab.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "service": {
                    "type": "string",
                    "description": "Nome do container ou serviço para filtrar (ex: 'nginx', 'api'). Se omitido, busca em todos.",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela de tempo relativa (ex: '30m', '1h', '24h'). Padrão: '1h'.",
                    "default": "1h",
                },
                "limit": {
                    "type": "integer",
                    "description": "Máximo de erros a retornar (padrão 20).",
                    "default": 20,
                },
            },
        },
        "handler": tool_get_errors,
    },
    {
        "name": "get_log_hits",
        "description": "Retorna uma série temporal agregada de contagem de logs ou erros por intervalo de tempo (/select/logsql/hits).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Filtro LogsQL (ex: 'level:error' ou '*'). Padrão: '*'.",
                    "default": "*",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela de tempo (ex: '1h', '24h'). Padrão: '1h'.",
                    "default": "1h",
                },
                "step": {
                    "type": "string",
                    "description": "Tamanho do intervalo de agregação (ex: '1m', '5m', '1h'). Padrão: '5m'.",
                    "default": "5m",
                },
            },
        },
        "handler": tool_get_log_hits,
    },
    {
        "name": "list_streams",
        "description": "Lista containers, serviços e hosts ativos enviando logs para o VictoriaLogs nas últimas horas.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "time_range": {
                    "type": "string",
                    "description": "Janela de tempo para buscar streams ativos. Padrão: '24h'.",
                    "default": "24h",
                },
            },
        },
        "handler": tool_list_streams,
    },
]

TOOLS_BY_NAME = {t["name"]: t for t in TOOLS}


def send_response(response: Dict[str, Any]) -> None:
    """Envia mensagem JSON-RPC para stdout com flush garantido."""
    payload = json.dumps(response, ensure_ascii=False)
    sys.stdout.write(payload + "\n")
    sys.stdout.flush()


def handle_request(req: Dict[str, Any]) -> None:
    """Processa requisições JSON-RPC 2.0 do cliente MCP."""
    req_id = req.get("id")
    method = req.get("method", "")
    params = req.get("params", {})

    # 1. Handshake inicial
    if method == "initialize":
        send_response({
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "victorialogs-mcp",
                    "version": "1.0.0",
                    "description": "Servidor MCP para VictoriaLogs Homelab Stack"
                }
            }
        })
        return

    # Notificação pós-inicialização do cliente (não requer resposta)
    if method == "notifications/initialized":
        return

    # Ping de liveness
    if method == "ping":
        send_response({"jsonrpc": "2.0", "id": req_id, "result": {}})
        return

    # 2. Catálogo de ferramentas
    if method == "tools/list":
        tools_list = []
        for t in TOOLS:
            tools_list.append({
                "name": t["name"],
                "description": t["description"],
                "inputSchema": t["inputSchema"],
            })
        send_response({
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "tools": tools_list
            }
        })
        return

    # 3. Execução de ferramenta
    if method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})

        if tool_name not in TOOLS_BY_NAME:
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32601,
                    "message": f"Ferramenta '{tool_name}' não encontrada.",
                }
            })
            return

        tool = TOOLS_BY_NAME[tool_name]
        try:
            result_text = tool["handler"](arguments)
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": result_text,
                        }
                    ],
                    "isError": False,
                }
            })
        except Exception as e:
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": f"Erro interno ao executar a ferramenta '{tool_name}': {str(e)}",
                        }
                    ],
                    "isError": True,
                }
            })
        return

    # Método desconhecido
    if req_id is not None:
        send_response({
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {
                "code": -32601,
                "message": f"Método '{method}' não suportado pelo servidor MCP.",
            }
        })


def main() -> None:
    """Loop principal de leitura de mensagens JSON-RPC via stdin."""
    # Garante stdin/stdout com codificação UTF-8
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(encoding="utf-8")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            handle_request(msg)
        except json.JSONDecodeError:
            send_response({
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": "Erro de parse JSON.",
                }
            })
        except Exception as e:
            sys.stderr.write(f"Erro inesperado no servidor MCP: {e}\n")
            sys.stderr.flush()


if __name__ == "__main__":
    main()
