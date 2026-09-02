# 🪵 Minimalist Homelab Log Observability (VictoriaLogs + Vector)

[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-v2+-blue.svg)](https://docs.docker.com/compose/)
[![VictoriaLogs](https://img.shields.io/badge/VictoriaLogs-v1.23.0-orange.svg)](https://docs.victoriametrics.com/victorialogs/)
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

Edite o `.env` se desejar customizar portas ou retenção:
```env
HOST_IDENTIFIER=mini-pc-proxmox
RETENTION_PERIOD=30d
VICTORIALOGS_HTTP_PORT=9428
```

### 3. Subir a Stack
```bash
docker compose up -d
```

### 4. Verificar Status e Consumo de Memória
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

## ⚙️ Limites de Recursos e Tuning

As configurações no [`docker-compose.yml`](./docker-compose.yml) foram ajustadas para estabilidade absoluta em ambientes limitados:

| Serviço | Limite de RAM (Max) | Reserva (Mínima) | CPU Limit |
|---|---|---|---|
| **VictoriaLogs** | `80 MB` | `30 MB` | `0.50 core` |
| **Vector** | `60 MB` | `20 MB` | `0.50 core` |
| **Total** | **`140 MB`** | **`50 MB`** | **`1.0 core`** |

- O buffer de fallback do Vector (`disk buffer`) está fixado em `100 MB` no volume persistente, garantindo que picos de logs não causem esgotamento de memória (OOMKilled).
- Caso o volume de logs diário do seu Homelab seja alto (> 20 GB/dia), você pode aumentar `memory: 120M` no VictoriaLogs via `.env` se necessário.

---

## 🛠️ Manutenção e Operações Comuns

- **Ver logs internos da stack:**
  ```bash
  docker compose logs -f
  ```
- **Reiniciar os serviços sem perder dados:**
  ```bash
  docker compose restart
  ```
- **Efetuar backup dos logs persistidos:**
  ```bash
  # Os dados estão salvos no volume Docker 'victorialogs_data'
  tar -czvf backup-logs-$(date +%F).tar.gz /var/lib/docker/volumes/victorialogs_data/_data
  ```

---

## 📄 Licença
Distribuído sob licença MIT. Sinta-se livre para usar, adaptar e evoluir em seu homelab!
