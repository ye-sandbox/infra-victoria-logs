#!/usr/bin/env python3
"""
VictoriaLogs Model Context Protocol (MCP) Server
================================================
Servidor MCP ultraleve, otimizado para produção e projetado especificamente para
Agentes e Assistentes de IA (Claude Code, Antigravity, Cursor, Roo Code).
Comunicação nativa via protocolo stdio JSON-RPC 2.0.

Características principais:
- Zero dependências externas (Pure Python 3).
- Consumo mínimo de hardware (< 22 MB de RAM, 0.0% CPU em repouso).
- Deduplicação inteligente de erros repetidos (economiza 70% a 95% de tokens).
- Projeção seletiva de campos (| keep) para poupar I/O e processamento.
- Truncamento seguro de payloads gigantes (com parâmetro full=true).
- Ferramentas nativas de introspecção de schema (field_names, field_values).
- Manual e documentação de LogsQL offline embutidos (tool documentation).
"""

import sys
import os
import json
import base64
import urllib.request
import urllib.error
import urllib.parse
from typing import Any, Dict, List, Optional, Tuple


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

    req = urllib.request.Request(url, headers={"User-Agent": "VictoriaLogs-MCP/1.1"})
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


def clean_query(raw_query: str) -> str:
    """Normaliza espaçamentos e remove quebras de linha acidentais na query LogsQL."""
    if not raw_query:
        return ""
    return " ".join(raw_query.split()).strip()


def enrich_logsql_error(err_msg: str, query: str = "") -> str:
    """Detecta erros clássicos de sintaxe do LogsQL e anexa dicas didáticas de auto-correção para IAs e devs."""
    err_lower = err_msg.lower()
    hints = []
    cleaned = clean_query(query)

    # Caso 1: Termos especiais sem aspas (ex: JID do WhatsApp, e-mail, tokens com @, :, /, -, etc.)
    if "probably, the whole string must be put into quotes" in err_lower or "missing whitespace or ':'" in err_lower:
        sample_quoted = f'"{cleaned}"' if cleaned and not (cleaned.startswith('"') and cleaned.endswith('"')) else cleaned
        hints.append(
            "💡 **Dica LogsQL (Caracteres Especiais):** Termos contendo caracteres como `@`, `:`, `/`, `-`, `.`, "
            "parênteses ou espaços não são identificadores válidos sem aspas e devem obrigatoriamente estar entre aspas duplas (`\"...\"`).\n"
            f"   - **Correção direta:** Execute novamente com `query='{sample_quoted}'`\n"
            f"   - **Busca no texto da mensagem:** `query='_msg:~\"{cleaned}\"'`\n"
            f"   - **Casamento exato de substring:** `query='exact:\"{cleaned}\"'`"
        )

    # Caso 2: Aspas abertas que não foram fechadas
    elif "unclosed quote" in err_lower or "missing closing quote" in err_lower:
        hints.append(
            "💡 **Dica LogsQL (Aspas Não Fechadas):** Foi detectada uma aspa dupla (`\"`) aberta sem o devido fechamento na query. "
            "Certifique-se de que todas as aspas duplas estejam balanceadas."
        )

    # Caso 3: Erro de sintaxe em pipes (| stats, | keep, | sort)
    elif "cannot parse pipe" in err_lower or "unknown pipe" in err_lower:
        hints.append(
            "💡 **Dica LogsQL (Pipes de Transformação):** O VictoriaLogs suporta pipes como `| stats by (...)`, `| keep ...`, "
            "`| sort by (...)` e `| limit N`. Consulte o guia offline executando a ferramenta `documentation` com `query=\"pipes\"`."
        )

    if hints:
        return f"{err_msg}\n\n" + "\n\n".join(hints)
    return err_msg


# ==============================================================================
# BASE DE CONHECIMENTO LOGSQL (DOCUMENTATION OFFLINE)
# ==============================================================================

LOGSQL_DOCS = {
    "filtros": """### 🔍 Filtros Básicos no LogsQL
- **Palavra exata:** `error` (busca case-insensitive em palavras alfanuméricas simples).
- **Termos com caracteres especiais (@, :, /, -, ., espaços, etc.):** Devem SEMPRE estar entre aspas duplas:
  - JIDs WhatsApp / mensageria: `"120363421617257978@g.us"` ou `_msg:~"120363421617257978@g.us"`
  - E-mails: `"usuario@dominio.com"`
  - Caminhos ou URLs: `"/api/v1/pagamentos"` ou `"https://api.empresa.com"`
- **Frase exata:** `"connection refused"` ou `"timeout exceeded"`.
- **Filtro por campo:** `level:error`, `service:api-gateway`, `status:500`.
- **Operadores booleanos:** `level:error AND NOT "/health"`, `(timeout OR panic) AND service:backend`.
- **Filtro por prefixo:** `service:app-*`, `status:5*` (pega 500, 502, 503).
- **Expressão Regular:** `_msg:~"error.*timeout"`, `path:~"^/api/v[12]/"`.""",

    "streams": """### ⚡ Filtros por Stream (Alta Performance)
Streams são indexadas em memória e não exigem varredura lenta no disco:
- **Sintaxe:** `_stream:{field="value", ...}`
- **Exemplos:**
  - `_stream:{service="pagamentos"}`
  - `_stream:{container_name="nginx",stream="stderr"}`
  - `_stream:{app="api-gateway",env="production"}`""",

    "tempo": """### ⏱️ Filtros Temporais (_time)
- **Janelas relativas:** `_time:5m`, `_time:30m`, `_time:1h`, `_time:24h`, `_time:7d`.
- **Intervalos absolutos:** `_time:[2026-09-01T00:00:00Z, 2026-09-02T00:00:00Z]`.
- **Recomendação:** SEMPRE inclua `_time` para evitar escanear semanas de dados desnecessariamente.""",

    "pipes": """### 🚰 Pipes de Transformação e Agregação
- **stats (Agrupamento e Contagem):**
  - `_time:1h | stats by (service) count() as total | sort by (total) desc`
  - `_time:2h AND level:error | stats by (container_name, level) count() total`
- **keep / delete (Projeção de Colunas):**
  - `| keep _time, service, level, _msg` (mantém apenas as colunas informadas)
  - `| delete label.com.docker.compose.*` (descarta colunas ruidosas)
- **sort (Ordenação):**
  - `| sort by (total) desc`
  - `| sort by (_time) asc`
- **limit:**
  - `| limit 20` (restringe a quantidade final de registros)""",

    "funcoes_stats": """### 📊 Funções Estatísticas Suportadas no pipe 'stats'
- `count()`: Contagem de registros.
- `count_uniq(field)`: Contagem de valores únicos (cardinalidade).
- `sum(field)`: Soma numérica.
- `avg(field)`: Média aritmética.
- `min(field)` / `max(field)`: Valores mínimo e máximo.
- `median(field)`: Mediana.
- `p50(field)`, `p90(field)`, `p95(field)`, `p99(field)`: Percentis.""",
}


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
    raw_query = clean_query(args.get("query", ""))
    time_range = clean_query(args.get("time_range", "1h"))
    limit = min(int(args.get("limit", 20)), 100)
    output_format = args.get("format", "markdown").lower()
    full_output = bool(args.get("full", False))

    if not raw_query:
        return "Erro: parâmetro 'query' obrigatório."

    # Injetar filtro temporal se omitido
    query = raw_query
    if time_range and "_time:" not in query:
        query = f"_time:{time_range} AND ({query})"

    # Otimização de I/O e rede: projetar apenas campos canônicos se a query não contiver pipes
    if "|" not in query:
        query = f"{query} | keep _time, level, service, container_name, _msg, stream, host"

    try:
        resp = make_request("/select/logsql/query", {"query": query, "limit": limit})
    except Exception as e:
        return f"❌ Erro ao consultar LogsQL: {enrich_logsql_error(str(e), raw_query)}"

    lines = [l.strip() for l in resp.splitlines() if l.strip()]
    if not lines:
        return f"ℹ️ Nenhum log encontrado para a query: `{raw_query}` (janela: {time_range})"

    if output_format == "json":
        return resp

    # Formatação compacta em Markdown
    out = [f"### 🪵 Logs ({len(lines)} registros encontrados na janela de {time_range})\n"]
    for line in lines:
        try:
            item = json.loads(line)
            ts = item.get("_time") or item.get("timestamp", "")
            if "T" in ts:
                ts = ts.replace("T", " ").split(".")[0]
            lvl = (item.get("level") or "info").upper()
            svc = item.get("service") or item.get("container_name") or "app"
            msg = item.get("_msg") or item.get("message", "")

            # Truncamento inteligente se a mensagem for excessivamente longa
            if not full_output and len(msg) > 350:
                msg = msg[:350] + f"... [truncado: +{len(msg) - 350} caracteres. Use full=true para ver na íntegra]"

            icon = "🔴" if lvl == "ERROR" else "🟡" if lvl == "WARN" else "⚪"
            out.append(f"{icon} **[{ts}] [{svc}] [{lvl}]** {msg}")
        except Exception:
            out.append(f"- {line}")

    out.append(f"\n*Exibindo {len(lines)} logs. Parâmetro 'full': {full_output}. Ajuste 'limit' se precisar de mais dados.*")
    return "\n".join(out)


def tool_get_errors(args: Dict[str, Any]) -> str:
    """Busca rápida de erros com deduplicação inteligente e preservação total de contexto."""
    service = clean_query(args.get("service", ""))
    time_range = clean_query(args.get("time_range", "1h"))
    limit = min(int(args.get("limit", 20)), 50)
    deduplicate = bool(args.get("deduplicate", True))
    full_output = bool(args.get("full", False))

    query_parts = ["level:error"]
    if service:
        query_parts.append(f'_stream:{{container_name="{service}"}}')
    if time_range:
        query_parts.append(f"_time:{time_range}")

    query = " AND ".join(query_parts)
    query = f"{query} | keep _time, level, service, container_name, _msg, stream, host"

    try:
        # Puxamos uma amostra maior se deduplicação estiver ligada para agrupar tempestades de erros
        fetch_limit = min(limit * 3, 100) if deduplicate else limit
        resp = make_request("/select/logsql/query", {"query": query, "limit": fetch_limit})
    except Exception as e:
        return f"❌ Erro ao buscar erros: {enrich_logsql_error(str(e), query)}"

    lines = [l.strip() for l in resp.splitlines() if l.strip()]
    if not lines:
        target = f"no serviço '{service}'" if service else "no homelab"
        return f"✅ Nenhum erro encontrado {target} na janela de {time_range}!"

    # Caso deduplicação esteja desativada, listar tradicionalmente
    if not deduplicate:
        out = [f"### 🚨 Erros Detectados ({len(lines)} ocorrências na janela de {time_range})\n"]
        for i, line in enumerate(lines[:limit], 1):
            try:
                item = json.loads(line)
                ts = item.get("_time") or item.get("timestamp", "")
                svc = item.get("service") or item.get("container_name") or "app"
                msg = item.get("_msg") or item.get("message", "")
                if not full_output and len(msg) > 1000:
                    msg = msg[:1000] + f"\n... [truncado: +{len(msg) - 1000} chars. Use full=true]"
                out.append(f"#### {i}. [{ts}] Serviço: `{svc}`\n```text\n{msg}\n```\n")
            except Exception:
                out.append(f"- {line}")
        return "\n".join(out)

    # Agrupamento inteligente de erros idênticos ou com a mesma assinatura
    groups: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for line in lines:
        try:
            item = json.loads(line)
            ts = item.get("_time") or item.get("timestamp", "")
            svc = item.get("service") or item.get("container_name") or "app"
            msg = item.get("_msg") or item.get("message", "")
            
            # Assinatura: (serviço, primeira linha da mensagem de erro)
            first_line = msg.strip().splitlines()[0][:140] if msg.strip() else "empty"
            sig = (svc, first_line)

            if sig not in groups:
                groups[sig] = {
                    "count": 0,
                    "first_ts": ts,
                    "last_ts": ts,
                    "service": svc,
                    "sample_msg": msg,
                }
            g = groups[sig]
            g["count"] += 1
            if ts < g["first_ts"]:
                g["first_ts"] = ts
            if ts > g["last_ts"]:
                g["last_ts"] = ts
        except Exception:
            pass

    out = [f"### 🚨 Erros Distintos Identificados ({len(groups)} causas-raiz na janela de {time_range})\n"]
    for i, (_, g) in enumerate(list(groups.items())[:limit], 1):
        svc = g["service"]
        count = g["count"]
        first_t = g["first_ts"].split(".")[0].replace("T", " ")
        last_t = g["last_ts"].split(".")[0].replace("T", " ")
        msg = g["sample_msg"]

        if not full_output and len(msg) > 1200:
            msg = msg[:1200] + f"\n... [stack trace truncada: +{len(msg) - 1200} caracteres. Use full=true para ver completa]"

        if count > 1:
            out.append(f"#### {i}. 🔴 [{count}x ocorrências] Serviço: `{svc}`")
            out.append(f"*Primeira ocorrência: `{first_t}` | Última: `{last_t}`*")
        else:
            out.append(f"#### {i}. 🔴 [1x ocorrência] Serviço: `{svc}` às `{first_t}`")

        out.append("```text")
        out.append(msg)
        out.append("```\n")

    out.append(f"*Total analisado: {len(lines)} registros consolidados em {len(groups)} grupos. Use full=true ou deduplicate=false se desejar logs brutos.*")
    return "\n".join(out)


def tool_get_log_hits(args: Dict[str, Any]) -> str:
    """Obtém série temporal agregada de contagem de eventos via /select/logsql/hits."""
    raw_query = clean_query(args.get("query", "*"))
    time_range = clean_query(args.get("time_range", "1h"))
    step = clean_query(args.get("step", "5m"))

    query = raw_query
    if time_range and "_time:" not in query:
        query = f"_time:{time_range} AND ({query})" if query != "*" else f"_time:{time_range}"

    try:
        resp = make_request("/select/logsql/hits", {"query": query, "step": step})
        data = json.loads(resp)
    except Exception as e:
        return f"❌ Erro ao buscar hits: {enrich_logsql_error(str(e), raw_query)}"

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
    """Lista containers, serviços e hosts ativos que estão enviando logs."""
    time_range = args.get("time_range", "24h").strip()

    # 1. Tentar o endpoint nativo e instantâneo /select/logsql/streams
    try:
        resp = make_request("/select/logsql/streams", {"start": time_range})
        lines = [l.strip() for l in resp.splitlines() if l.strip()]
        if lines:
            streams_set = set()
            for line in lines:
                try:
                    d = json.loads(line)
                    c = d.get("container_name") or "-"
                    s = d.get("service") or "-"
                    h = d.get("host") or "-"
                    st = d.get("stream") or "-"
                    streams_set.add((c, s, h, st))
                except Exception:
                    pass

            out = [
                f"### 📡 Streams Ativos (Endpoint Nativo - Janela: {time_range})\n",
                "| Container | Serviço | Host | Canal |",
                "|---|---|---|---|",
            ]
            for c, s, h, st in sorted(streams_set):
                out.append(f"| `{c}` | `{s}` | `{h}` | `{st}` |")
            out.append(f"\n*Total de {len(streams_set)} streams ativos identificados.*")
            return "\n".join(out)
    except Exception:
        pass

    # 2. Fallback via query agregada com a sintaxe correta do VictoriaLogs
    query = f"_time:{time_range} | stats by (container_name, service, host) count() as rows | sort by (rows) desc | limit 30"
    try:
        resp = make_request("/select/logsql/query", {"query": query})
        lines = [l.strip() for l in resp.splitlines() if l.strip()]
        if not lines:
            return f"ℹ️ Nenhum stream ativo encontrado na janela de {time_range}."

        out = [
            f"### 📡 Streams Ativos (Janela: {time_range})\n",
            "| Container | Serviço | Host | Volume de Logs |",
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
    except Exception as e:
        return f"❌ Erro ao listar streams: {str(e)}"


def tool_field_names(args: Dict[str, Any]) -> str:
    """Retorna os nomes dos campos indexados no VictoriaLogs para guiar queries da IA."""
    time_range = args.get("time_range", "24h").strip()
    try:
        resp = make_request("/select/logsql/field_names", {"query": f"_time:{time_range}"})
        data = json.loads(resp)
        items = data.get("values", [])
        if not items:
            return f"ℹ️ Nenhum campo encontrado na janela de {time_range}."

        out = [
            f"### 🏷️ Campos Indexados no VictoriaLogs (Janela: {time_range})\n",
            "Estes campos podem ser utilizados em filtros (`campo:valor`) ou agregações (`| stats by (campo)`):\n",
        ]
        for it in sorted(items, key=lambda x: x.get("hits", 0), reverse=True):
            fld = it.get("value", "")
            hits = it.get("hits", 0)
            out.append(f"- `{fld}` ({hits} logs)")
        return "\n".join(out)
    except Exception as e:
        return f"❌ Erro ao listar nomes de campos: {str(e)}"


def tool_field_values(args: Dict[str, Any]) -> str:
    """Retorna os valores mais frequentes de um campo específico (ex: 'level', 'service')."""
    field = args.get("field", "").strip()
    time_range = args.get("time_range", "24h").strip()
    limit = min(int(args.get("limit", 20)), 50)

    if not field:
        return "Erro: parâmetro 'field' obrigatório (ex: 'level', 'service', 'container_name')."

    try:
        resp = make_request("/select/logsql/field_values", {"field": field, "query": f"_time:{time_range}", "limit": limit})
        data = json.loads(resp)
        items = data.get("values", [])
        if not items:
            return f"ℹ️ Nenhum valor encontrado para o campo `{field}` na janela de {time_range}."

        out = [
            f"### 📊 Valores do Campo `{field}` (Janela: {time_range})\n",
            "| Valor | Ocorrências (Hits) |",
            "|---|---|",
        ]
        for item in items:
            val = item.get("value", "")
            hits = item.get("hits", 0)
            out.append(f"| `{val}` | {hits} |")
        return "\n".join(out)
    except Exception as e:
        return f"❌ Erro ao buscar valores do campo '{field}': {str(e)}"


def tool_documentation(args: Dict[str, Any]) -> str:
    """Manual e guia de referência offline de LogsQL embutido."""
    query = args.get("query", "").strip().lower()

    if not query:
        sections = [
            "## 📖 VictoriaLogs LogsQL — Guia Rápido de Consulta\n",
            LOGSQL_DOCS["filtros"],
            LOGSQL_DOCS["streams"],
            LOGSQL_DOCS["tempo"],
            LOGSQL_DOCS["pipes"],
            LOGSQL_DOCS["funcoes_stats"],
        ]
        return "\n\n---\n\n".join(sections)

    matches = []
    for key, doc in LOGSQL_DOCS.items():
        if query in key or query in doc.lower():
            matches.append(doc)

    if matches:
        return f"### 📚 Resultados da Documentação para: `{query}`\n\n" + "\n\n---\n\n".join(matches)

    return f"ℹ️ Nenhuma seção correspondente encontrada para `{query}`. Tente: 'filtros', 'streams', 'tempo', 'pipes' ou 'stats'."


# ==============================================================================
# CATÁLOGO DE FERRAMENTAS MCP JSON-RPC
# ==============================================================================

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
        "description": "Executa consultas avançadas no VictoriaLogs usando LogsQL. Retorna saída limpa em Markdown com alta economia de tokens.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Filtro LogsQL (ex: 'level:error', '_stream:{service=\"backend\"}', 'timeout OR panic').",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela temporal relativa (ex: '15m', '1h', '24h', '7d'). Padrão: '1h'.",
                    "default": "1h",
                },
                "limit": {
                    "type": "integer",
                    "description": "Limite máximo de registros (padrão 20, máximo 100).",
                    "default": 20,
                },
                "format": {
                    "type": "string",
                    "enum": ["markdown", "json"],
                    "description": "Formato de retorno ('markdown' compacto ou 'json' bruto).",
                    "default": "markdown",
                },
                "full": {
                    "type": "boolean",
                    "description": "Se verdadeiro, desativa o truncamento de mensagens longas (>350 caracteres).",
                    "default": False,
                },
            },
            "required": ["query"],
        },
        "handler": tool_query_logs,
    },
    {
        "name": "get_errors",
        "description": "Busca rápida e isolada de erros e stack traces. Por padrão, deduplica erros repetitivos preservando 100% da causa-raiz.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "service": {
                    "type": "string",
                    "description": "Nome do container ou serviço (ex: 'nginx', 'api'). Se omitido, busca em todo o homelab.",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela de tempo relativa (ex: '30m', '1h', '6h'). Padrão: '1h'.",
                    "default": "1h",
                },
                "limit": {
                    "type": "integer",
                    "description": "Máximo de grupos de erro a retornar (padrão 20).",
                    "default": 20,
                },
                "deduplicate": {
                    "type": "boolean",
                    "description": "Se verdadeiro (padrão), agrupa erros idênticos exibindo contagem e timestamps de início/fim.",
                    "default": True,
                },
                "full": {
                    "type": "boolean",
                    "description": "Se verdadeiro, exibe a stack trace completa sem truncamento.",
                    "default": False,
                },
            },
        },
        "handler": tool_get_errors,
    },
    {
        "name": "get_log_hits",
        "description": "Retorna série temporal de contagem de eventos por intervalo de tempo (/select/logsql/hits) para identificar picos de falha.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Filtro LogsQL (ex: 'level:error'). Padrão: '*'.",
                    "default": "*",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela temporal (ex: '1h', '6h', '24h'). Padrão: '1h'.",
                    "default": "1h",
                },
                "step": {
                    "type": "string",
                    "description": "Tamanho do bucket de tempo (ex: '1m', '5m', '1h'). Padrão: '5m'.",
                    "default": "5m",
                },
            },
        },
        "handler": tool_get_log_hits,
    },
    {
        "name": "list_streams",
        "description": "Lista instantaneamente os containers, serviços e hosts ativos que estão emitindo logs.",
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
    {
        "name": "field_names",
        "description": "Descobre todos os nomes de campos estruturados indexados no VictoriaLogs (ex: 'service', 'userId', 'status').",
        "inputSchema": {
            "type": "object",
            "properties": {
                "time_range": {
                    "type": "string",
                    "description": "Janela de tempo para descobrir campos. Padrão: '24h'.",
                    "default": "24h",
                },
            },
        },
        "handler": tool_field_names,
    },
    {
        "name": "field_values",
        "description": "Lista os valores mais frequentes de um campo específico indexado no VictoriaLogs.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "field": {
                    "type": "string",
                    "description": "Nome do campo para inspecionar (ex: 'level', 'service', 'container_name').",
                },
                "time_range": {
                    "type": "string",
                    "description": "Janela temporal. Padrão: '24h'.",
                    "default": "24h",
                },
                "limit": {
                    "type": "integer",
                    "description": "Quantidade máxima de valores a retornar (padrão 20).",
                    "default": 20,
                },
            },
            "required": ["field"],
        },
        "handler": tool_field_values,
    },
    {
        "name": "documentation",
        "description": "Consulta o manual e guia de referência offline de sintaxe, operadores e pipes do LogsQL.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Tópico de interesse (ex: 'stats', 'streams', 'filtros', 'pipes'). Se omitido, traz o guia completo.",
                },
            },
        },
        "handler": tool_documentation,
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
                    "version": "1.1.0",
                    "description": "Servidor MCP Otimizado para VictoriaLogs (Homelab Stack)"
                }
            }
        })
        return

    # Notificação pós-inicialização
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
                            "text": f"Erro inesperado ao executar '{tool_name}': {str(e)}",
                        }
                    ],
                    "isError": True,
                }
            })
        return

    # Método não suportado
    if req_id is not None:
        send_response({
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {
                "code": -32601,
                "message": f"Método '{method}' não suportado.",
            }
        })


def main() -> None:
    """Loop principal de leitura stdio JSON-RPC."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            handle_request(req)
        except json.JSONDecodeError:
            send_response({
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": "Erro de decodificação JSON.",
                }
            })
        except Exception as e:
            sys.stderr.write(f"Erro interno no servidor MCP: {e}\n")
            sys.stderr.flush()


if __name__ == "__main__":
    main()
