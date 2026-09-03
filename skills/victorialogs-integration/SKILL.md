---
name: victorialogs-integration
description: Guia de referência para agentes de IA configurarem e integrarem novas aplicações, containers Docker, microsserviços e scripts ao pipeline VictoriaLogs + Vector.
---

# VictoriaLogs Integration Guide (for AI Agents)

Esta skill orienta agentes de IA ao desenvolverem, configurarem ou refatorarem aplicações na organização `ye-sandbox` para que seus logs sejam capturados, normalizados e indexados com perfeição pelo pipeline **VictoriaLogs + Vector**.

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
      │   VICTORIALOGS    │  <- Armazena em disco sequencial e indexa com LogsQL
      └───────────────────┘
```

---

## 📜 Contrato Canônico de Campos

Toda aplicação deve preferencialmente emitir logs em formato JSON contendo os seguintes campos:

| Campo | Tipo | Descrição | Valores Sugeridos |
|---|---|---|---|
| `timestamp` | `string` | Data/hora no padrão ISO-8601 UTC | `2026-09-03T15:00:00.000Z` |
| `level` | `string` | Nível de severidade do log | `debug`, `info`, `warn`, `error` |
| `service` | `string` | Nome lógico da aplicação/serviço | `auth-api`, `billing-worker`, `backup-zfs` |
| `message` | `string` | Mensagem principal ou descrição do evento | `"Falha ao conectar no banco de dados"` |

> **Nota:** Se a aplicação emitir texto puro (raw text), o Vector automaticamente extrai o nível por heurística (`ERROR`, `WARN`, `INFO`) e atribui o nome do container ao campo `service`.

---

## 🐳 Padrão 1: Containers Docker via Docker Compose

Ao criar ou editar um `docker-compose.yml` para qualquer projeto:

```yaml
services:
  meu-servico:
    image: minha-imagem:latest
    container_name: meu-servico          # O Vector usa container_name como 'service'
    environment:
      LOG_FORMAT: "json"                 # Se suportado pela sua aplicação
      NO_COLOR: "1"                      # Desativa cores ANSI que poluem logs
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Regra de Ouro para Stack Traces (Multilinha):
O Vector está configurado para agregar linhas secundárias que começam com espaços ou tabulações (`^[\\s]`).
- **Correto:** Exceções do Python, Go ou Java indentadas com 2 ou 4 espaços são mantidas como **um único log**.
- **Evite:** Quebrar o traceback em várias linhas que comecem sem indentação na margem esquerda.

---

## 🐍 Padrão 2: Aplicações Python (`py-*`)

Utilize a biblioteca padrão `logging` com formatação JSON ou `structlog`:

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
            "message": record.getMessage(),
        }
        if record.exc_info:
            log_entry["message"] += "\n" + self.formatException(record.exc_info)
        return json.dumps(log_entry, ensure_ascii=False)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])

# Uso:
logger = logging.getLogger("app")
logger.info("Servidor iniciado com sucesso")
try:
    1 / 0
except Exception:
    logger.error("Erro no processamento da requisição", exc_info=True)
```

---

## 🟨 Padrão 3: Aplicações Node.js / TypeScript (`js-*`)

Utilize o logger de alta performance `pino`:

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
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

// Uso:
logger.info('Serviço escutando na porta 3000');
logger.error(new Error('Falha de conexão com a API externa'), 'Erro de integração');
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
    })

    logger := slog.New(handler)
    logger.Info("Worker Go inicializado")
    logger.Error("Conexão recusada ao banco", "db_host", "192.168.1.50")
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
      \"level\": \"${level}\",
      \"message\": \"${message}\"
    }" > /dev/null || true
}

# Uso no script:
send_log "info" "Iniciando snapshot ZFS no pool tanque"
send_log "error" "Falha ao sincronizar réplica remota"
```

---

## 🖥️ Padrão 6: Hosts Proxmox VE / LXCs / Switches (Syslog UDP)

Para encaminhar logs do nó Proxmox (`journald` / `rsyslog`):

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

Antes de concluir qualquer tarefa de integração, execute mentalmente ou via terminal:

- [ ] A aplicação emite logs em `stdout`/`stderr` sem cores ANSI (`NO_COLOR=1`).
- [ ] O `container_name` ou o atributo `service` está preenchido com clareza.
- [ ] O nível de log (`level`) segue `debug`, `info`, `warn` ou `error`.
- [ ] As stack traces de erro estão indentadas com espaços (multilinha compatível).
- [ ] Validado no VictoriaLogs:
  ```bash
  curl -s -G "http://localhost:9428/select/logsql/query" \
    --data-urlencode 'query=_stream:{service="meu-servico"} AND _time:5m'
  ```
