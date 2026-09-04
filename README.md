# 🪵 Minimalist Homelab Log Observability (VictoriaLogs + Vector)

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2+-blue.svg)](https://docs.docker.com/compose/)
[![VictoriaLogs](https://img.shields.io/badge/VictoriaLogs-latest-orange.svg)](https://docs.victoriametrics.com/victorialogs/)
[![Vector](https://img.shields.io/badge/Vector-0.45.0--alpine-purple.svg)](https://vector.dev/)
[![Footprint](https://img.shields.io/badge/RAM%20Usage-%3C%20150MB-success.svg)]()

Stack de observabilidade e centralização de logs minimalista, projetada para **Homelabs (Mini PCs, Intel NUCs e servidores Proxmox VE rodando Docker)**.

Focada em **baixíssimo consumo de CPU e RAM (< 150 MB no total)**, esta solução substitui com folga pilhas pesadas como Grafana Loki/Promtail ou Elastic/Logstash, sendo otimizada tanto para inspeção humana (Web UI nativa) quanto para **consultas automatizadas por Agentes de IA** (Claude Code, Antigravity, Cursor, Roo Code) durante diagnósticos de erros e incidentes.

---

## 🏗️ Arquitetura e Fluxo de Dados

```mermaid
flowchart LR
    subgraph Sources["Fontes de Logs (Homelab)"]
        D[Docker Containers locais\n/var/run/docker.sock]
        P[Proxmox VE / LXCs / VMs\nSyslog UDP 5140]
        A[Apps / Scripts externos\nHTTP JSON 8686]
    end

    subgraph Collector["Coletor & Roteador"]
        V[Vector Agent\n(~40-60 MB RAM)]
    end

    subgraph Storage["Armazenamento & Query"]
        VL[VictoriaLogs\n(~60-80 MB RAM)]
    end

    subgraph Consumers["Consumidores"]
        UI[Desenvolvedores\nVMUI Web :9428]
        AI[Agentes de IA & Scripts\nLogsQL HTTP API :9428]
    end

    D --> V
    P --> V
    A --> V
    V -- "HTTP POST (zstd ndjson)\nVL-Stream-Fields" --> VL
    VL --> UI
    VL --> AI
```

### Por que VictoriaLogs + Vector?
- **Footprint Minúsculo:** Ambos compilados para código nativo (VictoriaLogs em Go, Vector em Rust). Totalmente isentos de JVM, Python ou runtimes pesados.
- **Armazenamento Ultra-Compactado:** VictoriaLogs comprime logs em até 10x-15x em relação ao texto original, poupando SSDs de Mini PCs.
- **LogsQL:** Linguagem de consulta expressiva, intuitiva e estruturada, ideal para LLMs/Agentes de IA gerarem queries sem alucinações.
- **Auto-descoberta Docker:** O Vector mapeia automaticamente metadados de qualquer novo container iniciado na máquina local.

---

## 📁 Estrutura do Repositório

```text
.
├── docker-compose.yml       # Orquestração com limites de RAM rígidos (140 MB somados)
├── vector/
│   └── vector.yaml          # Configuração do Vector (Docker, Syslog, HTTP -> VictoriaLogs)
├── .env.example             # Variáveis de ambiente e parâmetros de retenção
├── .gitignore               # Ignora dados locais, volumes e segredos
├── AGENTS.md                # Diretrizes de engenharia e regras de atuação dos agentes
├── .agent/                  # Documentação de contexto (TASK.md, NOTES.md, ADRs)
└── README.md                # Guia de operação da stack
```

---

## 🚀 Guia de Início Rápido (Quickstart)

### 1. Pré-requisitos
- Docker Engine 24+ e Docker Compose v2+ instalados no host (ex: Debian/Ubuntu dentro de uma VM ou LXC no Proxmox).

### 2. Configuração do Ambiente
Clone o repositório e crie o arquivo `.env`:
```bash
cp .env.example .env
```

Edite o `.env` selecionando o perfil de armazenamento do seu hardware:
```env
# Defina 'hdd' para disco mecânico ou 'ssd' para SSD/NVMe
STORAGE_PROFILE=hdd

HOST_IDENTIFIER=mini-pc-proxmox
RETENTION_PERIOD=30d
VICTORIALOGS_HTTP_PORT=9428
```

### 3. Subir a Stack
```bash
docker compose up -d
```

### 4. Executar Teste Ponta a Ponta (Smoke Test)
Valide a ingestão e a busca de logs em menos de 5 segundos com o script automatizado:
```bash
./scripts/test-pipeline.sh
```

### 5. Verificar Status e Consumo de Memória
```bash
docker compose ps
docker stats --no-stream
```
*Você observará que a soma da memória de `victorialogs` e `vector` permanece confortavelmente abaixo de 150 MB.*

---

## 🔍 Como Consultar Logs

### 1. Interface Web (Desenvolvedores)
Acesse no seu navegador:
```text
http://<IP_DO_MINI_PC>:9428/select/vmui/
```
A VMUI oferece visualização gráfica, histogramas de frequência e filtros em tempo real.

---

### 2. Consultas para Agentes de IA (Via HTTP API / Curl)

Os agentes de IA podem executar chamadas diretas via terminal usando a API HTTP do VictoriaLogs (`/select/logsql/query`).

#### Exemplo 1: Buscar os últimos 20 erros de qualquer container
```bash
curl -s -G "http://localhost:9428/select/logsql/query" \
  --data-urlencode 'query=_time:1h AND level:error' \
  --data-urlencode 'limit=20'
```

#### Exemplo 2: Filtrar logs de um serviço específico com mensagem contendo "timeout" ou "panic"
```bash
curl -s -G "http://localhost:9428/select/logsql/query" \
  --data-urlencode 'query=_stream:{container_name="meu-backend"} AND (timeout OR panic)' \
  --data-urlencode 'limit=50'
```

#### Exemplo 3: Contagem de erros nos últimos 30 minutos (Hits)
```bash
curl -s -G "http://localhost:9428/select/logsql/hits" \
  --data-urlencode 'query=_time:30m AND level:error' \
  --data-urlencode 'step=5m'
```

---

## 📡 Ingestão de Outras Fontes do Homelab

### 1. Encaminhar Logs do Host Proxmox VE (Syslog)
Para enviar os logs de sistema do nó Proxmox (`/var/log/syslog` / `journald`) para a stack:
1. No host Proxmox, edite `/etc/rsyslog.d/60-vector.conf`:
   ```text
   *.* @<IP_DO_MINI_PC>:5140
   ```
2. Reinicie o rsyslog no Proxmox:
   ```bash
   systemctl restart rsyslog
   ```

### 2. Enviar Logs via HTTP (Aplicações / Scripts)
Qualquer script em Python, Bash ou microsserviço pode emitir eventos diretamente para o Vector:
```bash
curl -X POST http://<IP_DO_MINI_PC>:8686/logs \
  -H "Content-Type: application/json" \
  -d '{
    "service": "backup-script",
    "level": "info",
    "message": "Backup do pool ZFS concluido com sucesso em 42s"
  }'
```

---

## 💾 Perfis de Armazenamento: Modo HD vs Modo SSD

O projeto inclui perfis dinâmicos selecionáveis através da variável `STORAGE_PROFILE` no `.env`. Essa escolha calibra automaticamente o pipeline para a mídia de armazenamento do seu Mini PC / servidor:

| Recurso / Comportamento | 💾 Modo HD (`STORAGE_PROFILE=hdd`) | ⚡ Modo SSD (`STORAGE_PROFILE=ssd`) |
|---|---|---|
| **Foco Operacional** | **Minimizar IOPS e evitar I/O Wait** | **Baixa latência de busca e persistência** |
| **Buffer do Vector** | `memory` (RAM, máx 10.000 eventos) — *Zero escrita dupla no HD mecânico* | `disk` (256 MB persistentes no volume) — *Máxima resiliência contra quedas* |
| **Lotes de Envio (`batch`)** | `2 MB` / `2s` — *Gera gravações sequenciais longas no disco* | `1 MB` / `1s` — *Logs disponíveis para busca quase instantaneamente* |
| **Filtro de Ruído no Edge** | **Ativo** — *Descarta pings vazios (`/health`, `/ping`) para poupar disco* | **Desativado** — *Ingestão de 100% dos logs* |
| **Concorrência de Busca (VL)**| `2 buscas simultâneas` (`VL_MAX_CONCURRENT_REQUESTS=2`) | `4 buscas simultâneas` (`VL_MAX_CONCURRENT_REQUESTS=4`) |

> **Dica para usuários de HD mecânico:** Mantenha o modo `hdd` ativo para evitar que a agulha do disco sofra com *head thrashing* por concorrência entre o buffer e o banco.

---

## ⚙️ Limites de Recursos e Tuning

As configurações no [`docker-compose.yml`](./docker-compose.yml) foram ajustadas para estabilidade absoluta em ambientes limitados:

| Serviço | Limite de RAM (Max) | Reserva (Mínima) | CPU Limit |
|---|---|---|---|
| **VictoriaLogs** | `80 MB` | `30 MB` | `0.50 core` |
| **Vector** | `60 MB` | `20 MB` | `0.50 core` |
| **Total** | **`140 MB`** | **`50 MB`** | **`1.0 core`** |

- No **modo SSD**, o buffer em disco do Vector fica em `256 MB` no volume `vector_data`.
- No **modo HD**, o buffer reside em memória RAM (limitado dentro dos `60 MB`), garantindo que o HD só receba escritas sequenciais consolidadas.
- Caso o volume de logs diário do seu Homelab seja alto (> 20 GB/dia), você pode aumentar `memory: 120M` no VictoriaLogs se necessário.

---

## 🔒 Segurança e Autenticação Básica (Opcional)

Se o seu homelab for exposto externamente ou você desejar proteger a VMUI e as APIs, basta descomentar e configurar no [`.env`](./.env.example):
```env
VICTORIALOGS_AUTH_USERNAME=admin
VICTORIALOGS_AUTH_PASSWORD=coloque_sua_senha_segura
```
O VictoriaLogs exigirá HTTP Basic Auth para todas as consultas e o Vector se autenticará automaticamente.

---

## 📑 Suporte a Logs Multilinha (Stack Traces)

O coletor Vector possui agregação multilinha configurada nativamente para containers Docker:
- Linhas que começam com espaços ou tabulações (como tracebacks do Python, *panics* do Go ou exceções Java) são agrupadas no mesmo evento do log original.
- Evita que um único erro seja fatiado em dezenas de registros desconexos.

---

## 🛠️ Manutenção e Operações Comuns

- **Validar saúde do pipeline:**
  ```bash
  ./scripts/test-pipeline.sh
  ```
- **Backup atômico consistente (sem parar o banco):**
  ```bash
  # Utiliza a API nativa de snapshot do VictoriaLogs e rotaciona as cópias
  ./scripts/backup.sh
  ```
- **Ver logs internos da stack:**
  ```bash
  docker compose logs -f
  ```
- **Reiniciar os serviços:**
  ```bash
  docker compose restart
  ```

---

## 📊 Auto-monitoramento com Prometheus & Grafana

Ambos os serviços expõem métricas nativas prontas para coleta pelo Prometheus ou Grafana Agent sem a necessidade de exporters externos:

| Componente | Endpoint de Métricas | Porta Padrão | Variável no `.env` |
|---|---|---|---|
| **VictoriaLogs** | `http://<IP>:9428/metrics` | `9428` | `VICTORIALOGS_HTTP_PORT` |
| **Vector** | `http://<IP>:9598/metrics` | `9598` | `VECTOR_METRICS_PORT` |

### Exemplo de Configuração no `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'victorialogs'
    scrape_interval: 15s
    static_configs:
      - targets: ['<IP_DO_MINI_PC>:9428']

  - job_name: 'vector'
    scrape_interval: 15s
    static_configs:
      - targets: ['<IP_DO_MINI_PC>:9598']
```

### Principais Métricas a Monitorar:
- **VictoriaLogs:**
  - `vl_bytes_ingested_total{type="jsonline"}`: Total de bytes de log ingeridos.
  - `vl_concurrent_select_current`: Quantidade de buscas LogsQL rodando simultaneamente.
  - `vl_http_requests_total`: Total de requisições recebidas por rota HTTP.
  - `process_memory_limit_bytes`: Limite de RAM imposto ao processo (governança).
- **Vector:**
  - `vector_component_received_events_total`: Vazão de eventos recebidos por source/transform/sink.
  - `vector_buffer_byte_size`: Ocupação atual do buffer (em RAM ou SSD).
  - `vector_component_errors_total`: Contagem de erros internos de parsing ou roteamento.

---

## 🤖 Skill de Observabilidade para Agentes de IA

Este repositório inclui a skill padronizada [`skills/observability-logging/SKILL.md`](./skills/observability-logging/SKILL.md) (e [`.agent/skills/observability-logging/SKILL.md`](./.agent/skills/observability-logging/SKILL.md)), ensinando agentes de IA e desenvolvedores a:
1. Formatar logs no padrão canônico JSON (`timestamp`, `level`, `app`, `env`, `message`, `context`).
2. Configurar roteamento correto em aplicações Docker (`stdout`) ou bare-metal (HTTP assíncrono).
3. Utilizar o runbook de investigação via LogsQL para diagnóstico de falhas antes de propor correções.

---

## 🔌 VictoriaLogs MCP Server (Model Context Protocol)

Para permitir que assistentes de IA (Antigravity, Claude Desktop, Cursor, VS Code, Roo Code) realizem diagnósticos de logs nativamente pelo chat com LogsQL, este repositório disponibiliza suporte direto ao **MCP Server oficial da VictoriaMetrics** ([`VictoriaMetrics/mcp-victorialogs`](https://github.com/VictoriaMetrics/mcp-victorialogs)).

### 1. Instalação Automatizada
Execute o script instalador para baixar o binário estático Go oficial compilado para o seu ambiente:
```bash
./scripts/setup-mcp.sh
```
O executável ficará disponível em `./bin/mcp-victorialogs` (e em `~/.local/bin/mcp-victorialogs`).

### 2. Ferramentas (Tools) Disponibilizadas pelo MCP
- **`query`**: Executa queries LogsQL nativas no VictoriaLogs (ex: `_stream:{app="api-gateway"} AND level:"error"`).
- **`hits`**: Retorna distribuição e contagem de ocorrências por buckets temporais.
- **`streams`**: Lista os streams e fontes ativas no storage.
- **`field_names` / `field_values`**: Inspeciona dinamicamente os campos estruturados e metadados indexados.
- **`facets`**: Valores mais frequentes por campo de log.
- **`documentation`**: Motor de busca semântica embutido na documentação oficial do VictoriaLogs (offline).

### 3. Como Configurar no seu Assistente de IA

#### A. Google Antigravity
Adicione ao seu arquivo global `~/.gemini/config/mcp_config.json`:
```json
{
  "mcpServers": {
    "victorialogs": {
      "command": "/caminho/para/infra-victoria-logs/bin/mcp-victorialogs",
      "env": {
        "VL_INSTANCE_ENTRYPOINT": "http://192.168.0.201:9428"
      }
    }
  }
}
```

#### B. Claude Desktop
Adicione ao arquivo `claude_desktop_config.json` (`Settings -> Developer -> Edit config`):
```json
{
  "mcpServers": {
    "victorialogs": {
      "command": "/caminho/para/infra-victoria-logs/bin/mcp-victorialogs",
      "env": {
        "VL_INSTANCE_ENTRYPOINT": "http://192.168.0.201:9428"
      }
    }
  }
}
```

#### C. Cursor
Adicione em `~/.cursor/mcp.json` (`Settings -> Cursor Settings -> MCP`):
```json
{
  "mcpServers": {
    "victorialogs": {
      "command": "/caminho/para/infra-victoria-logs/bin/mcp-victorialogs",
      "env": {
        "VL_INSTANCE_ENTRYPOINT": "http://192.168.0.201:9428"
      }
    }
  }
}
```

#### D. Claude Code (CLI)
```bash
claude mcp add victorialogs -- /caminho/para/infra-victoria-logs/bin/mcp-victorialogs \
  -e VL_INSTANCE_ENTRYPOINT=http://192.168.0.201:9428
```

---

## 📄 Licença
Distribuído sob licença MIT. Sinta-se livre para usar, adaptar e evoluir em seu homelab!
