---
name: observability-logging
description: >-
  Padrão de observabilidade e logs estruturados (JSON) para criação de novos serviços e runbook para investigação de erros e timeouts consultando o VictoriaLogs via LogsQL. Use ao configurar logging em qualquer aplicação do homelab ou diagnosticar falhas no sistema.
---

# Skill: Observabilidade & Logging (VictoriaLogs / Vector)

## Missão
Garantir que qualquer novo serviço gere logs estruturados padronizados e investigar problemas consultando os logs centrais no VictoriaLogs.

---

## Padrão de Schema (JSON)

Todo log emitido por aplicações deve ser formatado em JSON na raiz (uma linha por evento - NDJSON) contendo obrigatoriamente os seguintes campos canônicos:

| Campo | Tipo | Valores Válidos / Formato | Descrição |
|---|---|---|---|
| `timestamp` | `string` | ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SS.sssZ`) | Momento exato da ocorrência |
| `level` | `string` | `"debug"` \| `"info"` \| `"warn"` \| `"error"` | Nível de criticidade do log |
| `app` | `string` | Minúsculo, kebab-case (ex: `api-gateway`, `auth-service`) | Nome do repositório ou serviço |
| `env` | `string` | `"production"` \| `"development"` | Ambiente de execução |
| `message` | `string` | Texto descritivo simples e conciso | Descrição legível do evento |

### Metadados e Contexto Extra
- Campos contextuais arbitrários (ex: `user_id`, `request_id`, `http_status`, `duration_ms`) devem ser adicionados diretamente como chaves na raiz do objeto ou agrupados dentro de um objeto `"context"`.
- Erros ou exceções devem incluir `error` (mensagem da exceção) e `stack_trace` (rastreamento completo da pilha em string).

### Exemplo Canônico
```json
{
  "timestamp": "2026-09-03T15:30:00.123Z",
  "level": "error",
  "app": "payment-gateway",
  "env": "production",
  "message": "Falha na comunicação com gateway de pagamento",
  "context": {
    "order_id": "ord_98741",
    "http_status": 504,
    "attempt": 3
  },
  "error": "GatewayTimeout: Gateway did not respond within 5000ms",
  "stack_trace": "GatewayTimeout: ...\n    at PaymentClient.process (/app/src/payment.js:42:15)"
}
```

---

## Regras de Configuração de Código

### 1. Aplicações em Containers (Docker / Docker Compose)
> **Regra Primária:** Priorize emissão para `stdout` / `stderr` em JSON. O coletor Vector local faz o scraping contínuo via socket do Docker (`/var/run/docker.sock`), normaliza e enriquece os streams automaticamente.

#### Diretrizes por Linguagem:
- **Node.js / TypeScript:**
  Use **Pino** (recomendado pelo alto desempenho) ou Winston configurado com `format.json()`:
  ```typescript
  import pino from 'pino';
  export const logger = pino({
    level: process.env.LOG_LEVEL || 'info',
    timestamp: pino.stdTimeFunctions.isoTime,
    base: {
      app: process.env.APP_NAME || 'my-service',
      env: process.env.NODE_ENV || 'production'
    },
    messageKey: 'message'
  });
  ```
- **Python:**
  Use `structlog` ou configure o `logging` nativo com formatador JSON (ex: `python-json-logger`):
  ```python
  import logging
  import json
  from datetime import datetime, timezone

  class VictoriaJsonFormatter(logging.Formatter):
      def format(self, record):
          log_data = {
              "timestamp": datetime.now(timezone.utc).isoformat(),
              "level": record.levelname.lower(),
              "app": "my-service",
              "env": "production",
              "message": record.getMessage(),
          }
          if record.exc_info:
              log_data["stack_trace"] = self.formatException(record.exc_info)
          return json.dumps(log_data)
  ```
- **Go:**
  Use o pacote nativo `log/slog`:
  ```go
  opts := &slog.HandlerOptions{Level: slog.LevelInfo}
  logger := slog.New(slog.NewJSONHandler(os.Stdout, opts)).With(
      slog.String("app", "my-service"),
      slog.String("env", "production"),
  )
  ```

#### Configuração de Logging no Docker Compose:
Mantenha o driver `json-file` padrão com rotação:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

---

### 2. Aplicações Nativas / Bare-Metal (systemd)
> **Regra Primária:** Se a aplicação roda direto no host ou em máquina virtual sem agente Vector local, adicione um transport HTTP assíncrono com fallback resiliente enviando para o endpoint `/insert/jsonline` do VictoriaLogs.

- **Endpoint de Ingestão:**
  ```text
  http://<IP_DO_MINI_PC>:9428/insert/jsonline?_stream_fields=app,env,level,service,host&_msg_field=message&_time_field=timestamp
  ```
- **Requisitos do Transport:**
  - Assíncrono / não-bloqueante (nunca bloqueie o loop da aplicação se o VictoriaLogs estiver indisponível).
  - Timeout de envio HTTP curto (máximo `2s`).
  - Fallback local: se a conexão falhar, descarregue o log em `stdout` / arquivo local para não perder rastreabilidade.

---

## Investigação de Erros (Runbook LogsQL)

Ao investigar falhas, exceções ou timeouts relatados pelo usuário:
1. **SEMPRE** consulte os logs centrais antes de tentar alterar o código.
2. Execute requisições HTTP GET na API de consulta do VictoriaLogs:

```bash
curl -s -G "http://<IP_DO_MINI_PC>:9428/select/logsql/query" \
  --data-urlencode "query=<LogsQL>" \
  --data-urlencode "limit=50"
```

### Consultas LogsQL Frequentes

1. **Buscar erros recentes de um serviço específico:**
   ```logsql
   _stream:{app="api-gateway"} AND level:"error"
   ```

2. **Buscar logs com timeouts ou conexões recusadas:**
   ```logsql
   _stream:{app="meu-servico"} AND ("timeout" OR "connection refused")
   ```

3. **Filtrar por ambiente e período específico:**
   ```logsql
   _stream:{env="production"} AND level:("error" OR "warn") AND _time:5m
   ```

4. **Inspecionar stack traces completos:**
   ```bash
   curl -s -G "http://<IP_DO_MINI_PC>:9428/select/logsql/query" \
     --data-urlencode 'query=_stream:{app="api-gateway"} AND level:"error"' \
     --data-urlencode 'limit=10' | jq -r '._msg, .stack_trace // empty'
   ```

5. **Localizar requisição por Request ID / Trace ID:**
   ```logsql
   "req_123456789"
   ```
