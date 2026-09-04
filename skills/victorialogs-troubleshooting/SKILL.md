---
name: victorialogs-troubleshooting
description: Playbook de SRE e investigação de incidentes para agentes de IA diagnosticarem erros, falhas e métricas no VictoriaLogs via MCP e LogsQL com máxima economia de tokens e zero perda de contexto.
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
  [Etapa 2: Isolamento do Erro e Traceback com Deduplicação]
  get_errors(service="meu-app", time_range="30m", limit=10)
            │
            ▼ (Extraiu a stack trace intacta e a contagem de ocorrências)
  [Etapa 3: Correlação com o Código-Fonte]
  Ler arquivo do workspace (ex: api/routes.py:L42) -> Propor Correção
```

---

## 🛠️ Catálogo Completo de Ferramentas MCP

O servidor MCP nativo do repositório (`mcp/server.py`) expõe **8 ferramentas otimizadas**, projetadas para entregar à IA exatamente o que ela precisa para resolver bugs sem desperdiçar tokens com metadados irrelevantes:

### 1. `health_check`
- **Quando usar:** No início da sessão para checar a conectividade com o VictoriaLogs.
- **Parâmetros:** `{}`

### 2. `get_log_hits`
- **Quando usar:** Para responder *"quando o problema começou?"* ou *"quantas falhas ocorreram por minuto?"*.
- **Parâmetros:**
  - `query`: `level:error` ou `_stream:{service="pagamentos"} AND level:error`
  - `time_range`: `"30m"`, `"1h"`, `"6h"`, `"24h"`
  - `step`: `"1m"`, `"5m"`, `"1h"`

### 3. `get_errors` ⭐ (Principal para Debugging)
- **Quando usar:** Extrai erros e stack traces multilinha formatadas em blocos de código sem ruído de logs `info`.
- **Deduplicação Inteligente:** Por padrão (`deduplicate=true`), agrupa tempestades de erros repetidos exibindo a quantidade de ocorrências e o intervalo (`[34x] Primeira: 11:20 | Última: 11:25`), mantendo a stack trace integral da causa-raiz.
- **Parâmetros:**
  - `service`: `"nome-do-container"` (opcional; se omitido, busca em todos)
  - `time_range`: `"30m"`, `"1h"` (padrão: `"1h"`)
  - `limit`: `10` ou `20`
  - `deduplicate`: `true` (padrão) ou `false` (para lista sequencial crua)
  - `full`: `false` (padrão, truncando tracebacks gigantes após 1.200 chars) ou `true` (stack trace 100% sem cortes)

### 4. `query_logs`
- **Quando usar:** Consultas flexíveis com LogsQL (ex: buscar um `request_id`, usuário ou texto).
- **Parâmetros:**
  - `query`: `_stream:{container_name="nginx"} AND status:500`
  - `time_range`: `"1h"`
  - `limit`: `20`
  - `format`: `"markdown"` (padrão compacto com ícones) ou `"json"` (ndjson bruto)
  - `full`: `false` (padrão) ou `true` (desativa truncamento de mensagens longas)

### 5. `list_streams`
- **Quando usar:** Para descobrir quais containers, serviços e hosts estão enviando logs ativos.
- **Parâmetros:**
  - `time_range`: `"24h"`

### 6. `field_names`
- **Quando usar:** Para listar todos os campos indexados no VictoriaLogs (ex: `user_id`, `path`, `status`).
- **Parâmetros:**
  - `time_range`: `"24h"`

### 7. `field_values`
- **Quando usar:** Para listar os valores existentes de um campo específico (ex: ver quais `level` ou `service` existem).
- **Parâmetros:**
  - `field`: `"service"` ou `"level"` (obrigatório)
  - `time_range`: `"24h"`
  - `limit`: `20`

### 8. `documentation`
- **Quando usar:** Para consultar a sintaxe do LogsQL (filtros, pipes, stats) sem sair do chat.
- **Parâmetros:**
  - `query`: `"stats"`, `"filtros"`, `"streams"`, `"pipes"` (ou vazio para o guia completo)

---

## 🧠 Garantia de Zero Perda de Contexto para a IA

A compactação realizada pelo nosso MCP foi desenhada por engenheiros de observabilidade para **nunca comprometer a capacidade de diagnóstico da IA**:

1. **O que é descartado (Ruído Inútil):**
   - Labels internas do Docker Compose (`label.com.docker.compose.config-hash`, `label.com.docker.compose.project_dir`, `label.com.docker.compose.version`, etc.).
   - Hashes de imagem SHA256 e IDs brutos de stream (`_stream_id: 000000000000...`).
2. **O que é 100% Preservado (Contexto Vital de SRE):**
   - **Mensagem do Erro e Stack Trace Completa:** O nome da exceção, linha do arquivo (`routes.py:L42`) e cadeia de chamadas.
   - **Identidade do Serviço:** Container (`container_name`), serviço (`service`) e host (`host`).
   - **Dimensão Temporal:** Timestamp exato em UTC, primeira ocorrência e última ocorrência do problema.
   - **Frequência da Falha:** Contagem exata de quantas vezes o erro disparou (`[42x ocorrências]`).
3. **Mecanismo de Escape (`full=true`):**
   - Caso um traceback ou mensagem seja anormalmente longo e a IA precise inspecionar os últimos caracteres truncados, basta chamar com `full=true`.

---

## ⚡ Cheat-Sheet de LogsQL (Padrões Rápidos)

### 1. Filtros por Stream (Indexados em Memória)
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
_time:1h AND level:error | stats by (container_name) count() as total | sort by (total) desc | limit 5
```
