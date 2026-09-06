# 🪵 Minimalist Homelab Log Observability (VictoriaLogs + Vector)

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2+-blue.svg)](https://docs.docker.com/compose/)
[![VictoriaLogs](https://img.shields.io/badge/VictoriaLogs-latest-orange.svg)](https://docs.victoriametrics.com/victorialogs/)
[![Vector](https://img.shields.io/badge/Vector-0.45.0--alpine-purple.svg)](https://vector.dev/)
[![Footprint](https://img.shields.io/badge/RAM%20Usage-%3C%20150MB-success.svg)]()

Stack de observabilidade e centralização de logs minimalista, projetada para **Homelabs (Mini PCs, Intel NUCs e servidores Proxmox VE rodando Docker)**.

Focada em **baixíssimo consumo de CPU e RAM (< 150 MB no total)**, esta solução substitui com folga pilhas pesadas como Grafana Loki/Promtail ou Elastic/Logstash, sendo otimizada tanto para inspeção humana (Web UI nativa) quanto para **consultas automatizadas por Agentes de IA** (Claude Code, Antigravity, Cursor, Roo Code) durante diagnósticos de erros e incidentes.

> 🔗 **Coabitação de Host:** esta stack roda no mesmo host Docker que o repositório de infraestrutura
> [`yegear1/homelab`](https://github.com/yegear1/homelab), que provisiona os demais serviços (Portainer, Dockge, Uptime Kuma, Homepage).
> As portas `9428`, `5140/udp`, `8686` e `9598`, os volumes `victorialogs_data` e `vector_data` e os nomes de contêiner
> `victorialogs` e `vector` estão **reservados na seção 2 do `.agent/SERVICES.md` daquele repositório**.
> Ao adicionar, remover ou renumerar qualquer porta ou volume aqui, atualize aquela seção no mesmo ciclo para evitar colisão de bind no host.

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
│   ├── vector.hdd.yaml      # Perfil HD mecânico (buffer em RAM, 2MB batch, filtro de pings)
│   ├── vector.ssd.yaml      # Perfil SSD/NVMe (buffer em disco, 1MB batch, 100% retenção)
│   └── vector.yaml          # Perfil base / fallback de configuração
├── .cursor/
│   └── mcp.json             # MCP do Cursor apontando para a VM Proxmox (192.168.0.201:9428)
├── mcp/
│   └── server.py            # Servidor MCP stdio nativo para integração direta com Agentes de IA
├── scripts/
│   ├── backup.sh            # Backup atômico via API de snapshots com rotação de cópias
│   ├── health-dashboard.sh  # Dashboard CLI colorido de telemetria ao vivo via APIs nativas
│   ├── test-pipeline.sh     # Smoke test ponta a ponta de ingestão e LogsQL em 1 comando
│   ├── test-mcp.sh          # Teste automatizado do protocolo MCP JSON-RPC 2.0
│   ├── tune-docker-host.sh  # Otimização do Docker daemon (modo non-blocking para HD)
│   └── tune-disk-host.sh    # Assistente de diagnóstico e tuning de HD (noatime, scheduler)
├── skills/
│   ├── victorialogs-integration/      # Skill ensinando IA a plugar aplicações (Python, Node, Go, Docker)
│   └── victorialogs-troubleshooting/  # Skill ensinando IA o playbook de investigação de erros/SRE
├── tests/
│   └── test_mcp_error_enricher.py     # Testes unitários de sanitização e dicas contextuais do MCP
├── .env.example             # Template documentado de variáveis de ambiente e segurança
├── .gitignore               # Ignora dados locais, volumes, backups e segredos
├── AGENTS.md                # Diretrizes de engenharia, governança e regras dos agentes
├── .agent/                  # Documentação de contexto do agente (TASK.md, NOTES.md)
└── README.md                # Guia técnico e operacional completo da stack
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

### 3. Consultas Nativas para Agentes de IA via MCP (Model Context Protocol)

O projeto inclui um **Servidor MCP nativo** ([`mcp/server.py`](./mcp/server.py)) em Pure Python 3 (zero dependências extras, < 22 MB de RAM). Ele permite que Claude Code, Cursor, Roo Code ou Antigravity investiguem logs diretamente sem rodar comandos manuais, com deduplicação de erros e economizando até 99.8% dos tokens em relação a APIs brutas:

#### Ferramentas MCP Disponíveis (8 Ferramentas Especializadas):
- `get_errors`: Extrai erros e stack traces limpas com **deduplicação inteligente** de falhas repetidas, filtro de escopo por aplicação (`service`) e dicas proativas de SRE em consultas globais.
- `query_logs`: Executa buscas flexíveis com LogsQL com suporte a filtro por aplicação (`service`), sanitização de quebras de linha, dicas contextuais de sintaxe e saída compacta em Markdown (`| keep`).
- `get_log_hits`: Gráfico temporal/histograma de eventos agrupados por minuto/hora para triagem de anomalias.
- `list_streams`: Lista containers, serviços e hosts ativos instantaneamente via endpoint nativo do VictoriaLogs.
- `field_names`: Descobre os nomes de campos indexados no storage (ex: `service`, `userId`, `status`).
- `field_values`: Lista os valores mais frequentes de qualquer campo.
- `documentation`: Manual e guia de referência offline de LogsQL (filtros, pipes, stats e regex) embutido no servidor.
- `health_check`: Testa a conexão com o VictoriaLogs.

#### Como Configurar no seu Cliente de IA:

**Cursor (recomendado neste repositório):** o arquivo [`.cursor/mcp.json`](./.cursor/mcp.json) já registra o servidor `victorialogs` e aponta para a VM Proxmox (`http://192.168.0.201:9428`). Recarregue a janela do Cursor (`Developer: Reload Window`) e confira o status verde em **Customize → MCP**.

Para disponibilizar as mesmas ferramentas em **todos** os projetos, copie a configuração para `~/.cursor/mcp.json` (WSL) ou para `%USERPROFILE%\.cursor\mcp.json` (Windows, via `wsl.exe`).

**Claude Desktop (`claude_desktop_config.json`) / outros clientes stdio:**
```json
{
  "mcpServers": {
    "victorialogs": {
      "type": "stdio",
      "command": "/usr/bin/python3",
      "args": ["/caminho/absoluto/para/infra-victoria-logs/mcp/server.py"],
      "env": {
        "VICTORIALOGS_URL": "http://192.168.0.201:9428"
      }
    }
  }
}
```

**Testar o servidor MCP manualmente:**
```bash
./scripts/test-mcp.sh
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
| **Lotes de Envio (`batch`)** | `2 MB` / `15s` — *Gera gravações sequenciais consolidadas e corta I/O contínuo* | `1 MB` / `1s` — *Logs disponíveis para busca quase instantaneamente* |
| **Filtro de Ruído no Edge** | **Ativo** — *Descarta pings vazios (`/health`, `/ping`) para poupar disco* | **Desativado** — *Ingestão de 100% dos logs* |
| **Flush em Memória (VL)** | `15s` (`VL_INMEMORY_FLUSH_INTERVAL=15s`) — *Reduz merges e fragmentação no HD* | `5s` (`VL_INMEMORY_FLUSH_INTERVAL=5s`) — *Disponibilização rápida no disco* |
| **Concorrência de Busca (VL)**| `2 buscas simultâneas` (`VL_MAX_CONCURRENT_REQUESTS=2`) | `4 buscas simultâneas` (`VL_MAX_CONCURRENT_REQUESTS=4`) |

> **Dica para usuários de HD mecânico:** Mantenha o modo `hdd` ativo para evitar que a agulha do disco sofra com *head thrashing* por concorrência entre o buffer e o banco.

### 🔧 Otimização do Host Docker para HD Mecânico (Modo Non-Blocking)

Em servidores onde todo o sistema operacional e containers rodam no mesmo HD mecânico (como Proxmox em disco único), o daemon do Docker por padrão tenta gravar logs de container de forma síncrona bloqueante (`blocking`). Em picos de I/O Wait (backups, tarefas de disco de VMs), **seus containers podem congelar** esperando o disco.

Para desacoplar a execução dos containers da velocidade do HD mecânico, configure o Docker para operar com ring-buffer assíncrono em RAM (`non-blocking` com 4 MB por container):

#### Opção A: Executar script assistido do repositório
```bash
# 1. Verificar status atual do Docker daemon
sudo ./scripts/tune-docker-host.sh --check

# 2. Aplicar configuração otimizada (cria backup automático)
sudo ./scripts/tune-docker-host.sh --apply

# 3. Recarregar o daemon do Docker sem reiniciar containers
sudo systemctl reload docker
```

#### Opção B: Configuração manual em `/etc/docker/daemon.json`
Edite `/etc/docker/daemon.json` no Proxmox adicionando as opções de buffer:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "mode": "non-blocking",
    "max-buffer-size": "4m"
  }
}
```
E recarregue o serviço:
```bash
sudo systemctl reload docker
```

### 💽 Otimizações de Kernel e Disco no Host (noatime, I/O Scheduler e APM)

Em hosts Proxmox VE onde o sistema operacional e os containers operam no mesmo HD mecânico rotacional, três configurações no sistema operacional evitam desgaste mecânico e lentidão severa:

1. **`noatime,nodiratime`:** Elimina a gravação de data/hora de acesso toda vez que um arquivo de log é lido em consultas da VMUI ou de agentes de IA.
2. **I/O Scheduler (`mq-deadline`):** Faz o kernel ordenar as requisições por elevador contínuo, impedindo que a agulha pule aleatoriamente pelo disco (*head thrashing*).
3. **APM (`hdparm -B 254`):** Mantém a rotação estável 24/7, evitando ciclos destrutivos de desliga/liga da agulha (*spindown*).

#### Diagnóstico e Assistência com o Script:
```bash
# 1. Inspecionar discos, schedulers e montagens ativas (não altera nada)
sudo ./scripts/tune-disk-host.sh --check

# 2. Configurar mq-deadline persistente para todos os HDs mecânicos (regra udev)
sudo ./scripts/tune-disk-host.sh --generate-udev

# 3. Aplicar noatime imediatamente na raiz ou partição de logs (sem reiniciar)
sudo ./scripts/tune-disk-host.sh --remount-noatime /
```

#### Tornar o `noatime` permanente após reiniciar (`/etc/fstab`):
Edite `/etc/fstab` no Proxmox e inclua `noatime,nodiratime` nas opções da partição do HD:
```text
# Exemplo no /etc/fstab do Proxmox:
UUID=xxxx-xxxx-xxxx  /  ext4  errors=remount-ro,noatime,nodiratime  0  1
```

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

- **Dashboard CLI de Saúde e Telemetria (ao vivo):**
  ```bash
  # Execução pontual
  ./scripts/health-dashboard.sh

  # Modo contínuo (atualização a cada 5s)
  ./scripts/health-dashboard.sh --watch
  ```
- **Validar saúde do pipeline (Smoke Test):**
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

## 🤖 Skills para Agentes de IA (`skills/`)

O repositório inclui duas SKILLs completas e reutilizáveis, preparadas para serem consumidas por assistentes de IA (Claude, Antigravity, Cursor, Roo Code) em qualquer repositório da organização `ye-sandbox`:

1. **[`skills/victorialogs-integration`](./skills/victorialogs-integration/SKILL.md):**
   - Ensina a IA a plugar e configurar novas aplicações para enviarem logs para o pipeline.
   - Contém snippets prontos para **Docker Compose**, **Python** (`logging`/`structlog`), **Node.js** (`pino`), **Go** (`slog`), **Bash** (`curl`) e **Proxmox** (`rsyslog`).
2. **[`skills/victorialogs-troubleshooting`](./skills/victorialogs-troubleshooting/SKILL.md):**
   - Playbook de SRE e investigação de incidentes para a IA diagnosticar falhas no homelab via servidor MCP e LogsQL com **máxima economia de tokens**.

---

## 📄 Licença
Distribuído sob licença MIT. Sinta-se livre para usar, adaptar e evoluir em seu homelab!
