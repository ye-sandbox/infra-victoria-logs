---
name: victorialogs-troubleshooting
description: Playbook de SRE e investigação de incidentes para agentes de IA diagnosticarem erros, falhas e métricas no VictoriaLogs via MCP e LogsQL com máxima economia de tokens.
---

# VictoriaLogs Troubleshooting & Investigation Playbook (for AI Agents)

Esta skill orienta agentes de IA (Claude, Antigravity, Cursor, Roo Code) a atuarem como **especialistas em SRE** para diagnosticar erros, quedas e anomalias no homelab consumindo a stack **VictoriaLogs + Vector**.

---

## 🎯 Protocolo de Investigação de Incidentes em 3 Etapas

Quando o usuário relatar um erro ("a API caiu", "o worker parou", "estou recebendo erro 500"):

```text
  [Etapa 1: Triagem Temporal]
  get_log_hits(query="level:error", time_range="1h", step="5m")
            │
            ▼ (Identificou o pico exato de erros)
  [Etapa 2: Isolamento do Erro e Traceback]
  get_errors(service="meu-app", time_range="30m", limit=10)
            │
            ▼ (Extraiu a stack trace e a mensagem de erro)
  [Etapa 3: Correlação com o Código-Fonte]
  Ler arquivo do workspace (ex: api/routes.py:L42) -> Propor Correção
```

---

## 🛠️ Como Usar as Ferramentas MCP (Recomendado)

Se o servidor MCP estiver configurado, utilize as chamadas de ferramentas diretamente (economizam até 80% dos tokens):

### 1. `health_check`
- **Quando usar:** Primeiro comando ao iniciar uma sessão de diagnóstico para verificar se a stack VictoriaLogs está operacional.
- **Exemplo:**
  ```json
  {}
  ```

### 2. `get_log_hits`
- **Quando usar:** Para responder "quando começou o problema?" ou "quantas falhas ocorreram?".
- **Parâmetros:**
  - `query`: `level:error` ou `_stream:{service="pagamentos"} AND level:error`
  - `time_range`: `"1h"`, `"6h"`, `"24h"`
  - `step`: `"5m"`, `"15m"`, `"1h"`

### 3. `get_errors`
- **Quando usar:** A ferramenta mais rápida para extrair os erros mais recentes com stack trace multilinha sem poluição de logs de `info`.
- **Parâmetros:**
  - `service`: `"nome-do-container"` (opcional; se omitido, busca em todos)
  - `time_range`: `"30m"`, `"1h"`
  - `limit`: `10` ou `20`

### 4. `query_logs`
- **Quando usar:** Quando você precisa de consultas flexíveis com LogsQL (ex: buscar um `request_id`, transação ou texto específico).
- **Parâmetros:**
  - `query`: `_stream:{container_name="nginx"} AND status:500`
  - `time_range`: `"1h"`
  - `limit`: `20`
  - `format`: `"markdown"` (padrão compacto) ou `"json"`

### 5. `list_streams`
- **Quando usar:** Para descobrir quais containers ou hosts estão enviando logs se você não souber o nome exato do serviço.
- **Parâmetros:**
  - `time_range`: `"24h"`

---

## ⚡ Cheat-Sheet de LogsQL (Padrões Avançados)

Caso precise executar queries via `query_logs` ou `curl` direto:

### 1. Filtros por Stream (Extremamente Rápidos no HD/SSD)
Os campos de stream (`host`, `container_name`, `service`, `stream`) utilizam índices dedicados:
```text
_stream:{service="meu-backend"}
_stream:{container_name="vector"}
_stream:{host="mini-pc-proxmox"}
```

### 2. Filtros de Severidade e Negação
```text
level:error
level:(error OR warn)
level:error AND NOT "/health"
```

### 3. Busca por Frases e Palavras-Chave
```text
"connection refused"
"out of memory" OR "OOMKilled"
timeout AND NOT "keepalive"
```

### 4. Pipes de Agregação e Estatísticas
Contar erros agrupados por container na última hora:
```text
_time:1h AND level:error | stats count() total by (container_name) | sort by (total) desc | limit 5
```

Descobrir quais rotas HTTP geraram status 5xx:
```text
_time:2h AND status:5* | stats count() total by (path) | sort by (total) desc
```

---

## 🧠 Regras de Ouro de Economia de Tokens para Agentes de IA

1. **NUNCA faça consultas sem filtro temporal (`_time`):**
   - ❌ Errado: `level:error` (pode escanear 30 dias de logs e estourar o limite de memória).
   - ✅ Correto: `_time:30m AND level:error` ou passe `time_range="30m"` na tool MCP.
2. **Limite a quantidade de registros:**
   - Para entender a causa-raiz de um bug, **3 a 5 stack traces idênticas bastam**. Nunca solicite `limit=500`. Comece com `limit=10`.
3. **Filtre ruído repetitivo na própria query:**
   - Se um container fica dando healthcheck falho ou warning inofensivo, use negação: `level:error AND NOT "ping"`.

---

## 💻 Fallback via Curl (Quando o MCP não estiver ativo)

Se o ambiente do agente não tiver o cliente MCP configurado, execute comandos via shell com codificação de URL:

```bash
# 1. Checar saúde
curl -s -f http://localhost:9428/health

# 2. Buscar últimos 10 erros com LogsQL
curl -s -G "http://localhost:9428/select/logsql/query" \
  --data-urlencode 'query=_time:30m AND level:error' \
  --data-urlencode 'limit=10'

# 3. Série temporal de contagem de erros
curl -s -G "http://localhost:9428/select/logsql/hits" \
  --data-urlencode 'query=_time:1h AND level:error' \
  --data-urlencode 'step=5m'
```
*Se a stack tiver autenticação ativada no `.env`, passe `-u "$VICTORIALOGS_AUTH_USERNAME:$VICTORIALOGS_AUTH_PASSWORD"`.*
