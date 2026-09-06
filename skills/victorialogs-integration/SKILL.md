---
name: victorialogs-integration
description: Integra aplicações da org ye-sandbox ao pipeline VictoriaLogs + Vector. Use ao criar ou alterar logging, docker-compose, stdout JSON, syslog Proxmox ou POST HTTP para o Vector. Define o contrato NDJSON, campos canônicos, stream fields e o que não emitir.
---

# VictoriaLogs Integration Guide (for AI Agents)

Esta skill orienta agentes de IA ao desenvolverem, configurarem ou refatorarem aplicações na organização `ye-sandbox` para que seus logs sejam capturados, normalizados e indexados com perfeição pelo pipeline **VictoriaLogs + Vector**.

Fonte canônica: `ye-sandbox/infra-victoria-logs/skills/victorialogs-integration`. Não copie este arquivo para outros repositórios — atualize-o aqui e, no `AGENTS.md` do app, apenas aponte para esta skill. No Cursor, a descoberta automática vem de um symlink em `~/.cursor/skills/` para esta pasta.

---

## 🏗️ Como a Ingestão Funciona

```text
[ Aplicações / Containers / Scripts ]
                │
                ▼ (Docker socket / Syslog UDP :5140 / HTTP POST :8686/logs)
         ┌─────────────┐
         │   VECTOR    │  <- Normaliza VRL, agrega multilinhas, comprime (zstd)
         └──────┬──────┘
                │ HTTP POST (:9428/insert/jsonline)
                ▼
      ┌───────────────────┐
      │   VICTORIALOGS    │  <- Comprime e indexa internamente (não é um dump JSON)
      └───────────────────┘
```

JSON é o formato de **emissão** da aplicação (stdout ou POST). Não é o formato de armazenamento no disco: o Vector já envia NDJSON comprimido com zstd; o VictoriaLogs guarda no engine próprio. Não “exporte um arquivo JSON para o banco”.

---

## 📜 Contrato Canônico de Campos

Toda aplicação deve preferencialmente emitir **um objeto JSON por linha (NDJSON)** contendo:

| Campo | Tipo | Quem preenche | Descrição |
|---|---|---|---|
| `timestamp` | `string` ISO-8601 UTC | App (senão o Vector usa `now()`) | Ex: `2026-09-03T15:00:00.000Z` |
| `level` | `string` minúscula | App | `debug`, `info`, `warn`, `error` |
| `service` | `string` | App (senão `container_name`) | Nome lógico: `auth-api`, `billing-worker` |
| `app` | `string` | App (senão copia `service`) | Identificador do repositório/serviço |
| `env` | `string` | App (senão `production`) | `production` ou `development` |
| `message` | `string` | App | Texto principal do evento |
| `stack_trace` | `string` opcional | App | Traceback com `\n` no mesmo evento |
| `context` / extras | campos no topo | App | `userId`, `request_id`, `status` — **não** viram stream |

O Vector também injeta `host`, `container_name` e `stream` (`stdout` / `stderr` / `syslog` / `http`). Se a mensagem for JSON válido, o objeto original fica em `structured`.

> **Texto puro:** se a app não emitir JSON, o Vector infere `level` por regex (`error`, `warn`, `debug`) e usa o nome do container como `service`. Funciona, mas LogsQL e o MCP (`get_errors`, filtro por `service`) ficam piores. Prefira JSON nas aplicações; **não** force JSON no syslog do Proxmox.

---

## 📐 Como emitir JSON (e o que não fazer)

### Obrigatório
- **Uma linha = um evento.** `json.dumps(obj)` / `pino` / `slog JSONHandler` escrevem um objeto por linha. Nunca `JSON.stringify([e1, e2], null, 2)` nem pretty-print com quebras no meio do objeto: o Vector faz `parse_json` em cada linha de stdout.
- **`message` no topo do objeto.** Não enterre o texto só dentro de `data.msg` ou de um blob aninhado sem `message`/`msg`.
- **`level` em minúsculas** (`error`, não `ERROR`). O VRL já faz `downcase` quando o JSON parseia.

### Stream fields vs campos do evento
Cabeçalho canônico do sink: `VL-Stream-Fields: "host,container_name,service,app,env,stream"`.

- **Pode ser dimensão de stream:** identidade estável da fonte (`service=auth-api`, `env=production`).
- **Nunca vire stream field:** `userId`, `request_id`, JID de WhatsApp, URL, e-mail, path. Isso é **campo do evento** (ou `context`). Alta cardinalidade em stream explode o índice no Mini PC. Consulte com LogsQL no campo (`"1203…@g.us"`, `userId:123`), não criando uma stream nova.

### Stack traces
- **JSON:** um único evento. Coloque o traceback em `message` (com `\n`) ou em `stack_trace`. O agregador multilinha do Vector **não** junta linhas de um JSON quebrado.
- **Texto puro (stdout indentado):** o Vector agrega linhas que começam com espaço/tab (`^[\\s]`) na linha anterior. Python/Java/Go panic indentados viram um evento. Linhas de traceback na coluna 0 viram eventos soltos.

### O que não emitir (ou não neste formato)
- **Syslog do host / rsyslog / journald:** use UDP `:5140`. Não converta o journal do Proxmox para JSON.
- **Healthchecks e pings** (`GET /health`, `/ping`, `/ready`, kube-probe) no perfil HDD: o Vector **descarta** no edge (salvo se a linha também tiver `error`/`fail`/`warn`). Não conte com esses eventos para auditoria em disco mecânico.
- **Pretty / cores:** `NO_COLOR=1`. Em Node, **não** use `pino-pretty` (nem `transport` para pretty) no container de produção.

---

## 🐳 Padrão 1: Containers Docker via Docker Compose

Ao criar ou editar um `docker-compose.yml` para qualquer projeto:

```yaml
services:
  meu-servico:
    image: minha-imagem:latest
    container_name: meu-servico          # O Vector usa container_name como fallback de service
    environment:
      LOG_FORMAT: "json"                 # Se suportado pela sua aplicação
      NO_COLOR: "1"                      # Desativa cores ANSI que poluem logs
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

`logging.driver: json-file` é o **driver do Docker** (arquivo de log do daemon), não o formato da aplicação. A aplicação ainda deve escrever JSON no stdout.

---

## 🐍 Padrão 2: Aplicações Python (`py-*`)

Utilize a biblioteca padrão `logging` com formatação JSON ou `structlog`. Um objeto por linha; traceback no mesmo evento:

```python
import json
import logging
import sys
from datetime import datetime, timezone

class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "service": "minha-app-python",
            "app": "minha-app-python",
            "env": "production",
            "message": record.getMessage(),
        }
        if record.exc_info:
            log_entry["stack_trace"] = self.formatException(record.exc_info)
            log_entry["message"] += "\n" + log_entry["stack_trace"]
        reserved = {
            "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
            "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
            "created", "msecs", "relativeCreated", "thread", "threadName",
            "processName", "process", "message", "taskName",
        }
        for key, value in record.__dict__.items():
            if key not in reserved and key not in log_entry:
                log_entry[key] = value
        return json.dumps(log_entry, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])

logger = logging.getLogger("app")
logger.info("Servidor iniciado com sucesso")
try:
    1 / 0
except Exception:
    logger.error("Erro no processamento da requisição", extra={"request_id": "abc"}, exc_info=True)
```

---

## 🟨 Padrão 3: Aplicações Node.js / TypeScript (`js-*`)

Utilize `pino` em JSON puro. **Não** configure `pino-pretty` em produção.

```typescript
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  formatters: {
    level: (label) => ({ level: label }),
  },
  base: {
    service: 'minha-app-node',
    app: 'minha-app-node',
    env: process.env.NODE_ENV === 'development' ? 'development' : 'production',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

logger.info('Serviço escutando na porta 3000');
logger.error({ err: new Error('Falha de conexão com a API externa'), request_id: 'abc' }, 'Erro de integração');
```

---

## 🔵 Padrão 4: Aplicações Go

Utilize o pacote padrão `log/slog` com JSONHandler:

```go
package main

import (
    "log/slog"
    "os"
)

func main() {
    handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
            if a.Key == slog.MessageKey {
                a.Key = "message"
            }
            if a.Key == slog.LevelKey {
                a.Key = "level"
            }
            if a.Key == slog.TimeKey {
                a.Key = "timestamp"
            }
            return a
        },
    }).WithAttrs([]slog.Attr{
        slog.String("service", "meu-servico-go"),
        slog.String("app", "meu-servico-go"),
        slog.String("env", "production"),
    })

    logger := slog.New(handler)
    logger.Info("Worker Go inicializado")
    logger.Error("Conexão recusada ao banco", "db_host", "192.168.1.50", "request_id", "abc")
}
```

---

## 📡 Padrão 5: Scripts Shell, Crons e Microsserviços (HTTP POST Direto)

Se a aplicação rodar fora do Docker (ex: script de backup no Proxmox):

```bash
send_log() {
  local level="${1:-info}"
  local message="${2}"
  local service="${3:-meu-script-bash}"
  local vector_host="${VECTOR_HOST:-localhost}"
  local vector_port="${VECTOR_HTTP_PORT:-8686}"

  curl -s -X POST "http://${vector_host}:${vector_port}/logs" \
    -H "Content-Type: application/json" \
    -d "{
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"service\": \"${service}\",
      \"app\": \"${service}\",
      \"env\": \"production\",
      \"level\": \"${level}\",
      \"message\": \"${message}\"
    }" > /dev/null || true
}

send_log "info" "Iniciando snapshot ZFS no pool tanque"
send_log "error" "Falha ao sincronizar réplica remota"
```

O POST já é um objeto JSON (não um array). Um POST = um evento.

---

## 🖥️ Padrão 6: Hosts Proxmox VE / LXCs / Switches (Syslog UDP)

Para encaminhar logs do nó Proxmox (`journald` / `rsyslog`) **sem** reformatar em JSON:

1. Crie `/etc/rsyslog.d/60-vector.conf`:
   ```text
   *.* @<IP_DO_MINI_PC>:5140
   ```
2. Reinicie o rsyslog:
   ```bash
   systemctl restart rsyslog
   ```

---

## ✅ Checklist do Agente de IA ao Integrar uma Aplicação

Antes de concluir qualquer tarefa de integração:

- [ ] A aplicação emite **NDJSON** em `stdout`/`stderr` (um objeto por linha), sem cores (`NO_COLOR=1`) e sem pretty-printer.
- [ ] Campos no topo: `timestamp`, `level` minúsculo, `service` (e de preferência `app`/`env`), `message`.
- [ ] IDs de alta cardinalidade (`userId`, `request_id`, JID, URL) são campos do evento, não dimensões de stream.
- [ ] Stack traces JSON vão no mesmo evento (`message`/`stack_trace` com `\n`); texto puro continua indentado para o agregador do Vector.
- [ ] Syslog de host usa `:5140`; scripts fora do Docker usam POST `:8686/logs`.
- [ ] Validado no VictoriaLogs (ajuste o host se a stack não estiver em localhost):
  ```bash
  curl -s -G "http://localhost:9428/select/logsql/query" \
    --data-urlencode 'query=_stream:{service="meu-servico"} AND _time:5m'
  ```
