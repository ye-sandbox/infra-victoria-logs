# NOTES.md — Decisões, Contexto e Contratos do Projeto

> Guarda o PORQUÊ, não o QUE nem o COMO. Descrições de "o que foi feito" ficam no
> `git log` / commits. Passos de "o que fazer" ficam no `.agent/TASK.md`. Este arquivo é
> para decisões, trade-offs, contratos e armadilhas que **não são óbvias a partir do diff**.

---

## Decisões Arquiteturais e Contexto Técnico

### 2026-09-02 — Escolha de VictoriaLogs + Vector para Homelab
- **Contexto:** Necessidade de centralizar logs de múltiplos containers Docker locais e nós Proxmox VE (LXC/VMs) em um Mini PC com recursos de hardware restritos, garantindo baixo consumo de CPU e RAM (< 150 MB no total).
- **Decisão:** Adotar **VictoriaLogs** como banco de armazenamento e **Vector** como coletor/normalizador.
- **Alternativas consideradas:**
  - *Grafana Loki + Promtail:* Consome entre 400 MB e 800 MB de RAM em repouso, sofre com problemas de alta cardinalidade de labels e exige múltiplos componentes.
  - *ELK (Elasticsearch/Logstash):* Consumo mínimo de 2 GB a 4 GB de RAM devido à JVM, inviável para Mini PCs de homelab.
- **Consequências:** Footprint previsível < 140 MB de RAM, compressão superior (10x-15x) poupando escrita em SSD, e API LogsQL simplificada para agentes de IA realizarem diagnósticos.

### 2026-09-02 — Ingestão via Vector HTTP Sink com Stream Fields
- **Contexto:** O VictoriaLogs indexa registros baseado no conceito de *Streams* (conjunto único de campos que identificam uma fonte contínua de logs).
- **Decisão:** Vector envia logs diretamente para o endpoint `/insert/jsonline` do VictoriaLogs com cabeçalho:
  `VL-Stream-Fields: "host,container_name,service,stream"`.
- **Alternativas consideradas:**
  - *Elasticsearch sink:* Suportado pelo VictoriaLogs, porém adiciona sobrecarga de simulação de API e limita flexibilidade de cabeçalhos de multi-tenancy ou timestamps personalizados.
- **Consequências:** Buscas em tempo de execução são extremamente rápidas ao filtrar por container ou host (`_stream:{container_name="nginx"}`).

### 2026-09-02 — Adoção de Zstandard (zstd), Micro-Batching e Proteção de Queries
- **Contexto:** Necessidade de minimizar o consumo de CPU em Mini PCs durante a compressão/descompressão e evitar picos de I/O por micro-requisições HTTP, além de blindar a stack contra buscas lentas de LLMs/Agentes de IA.
- **Decisão:**
  - Migrar compressão no sink do Vector de `gzip` para `zstd`.
  - Habilitar `-search.maxQueryDuration=30s` e `ulimits: nofile: 65536` com `stop_grace_period: 30s` para desligamento atômico.
- **Consequências:** Menor utilização de CPU por MB ingerido e imunidade contra OOM originado de queries longas.

### 2026-09-02 — Perfis Dinâmicos de Armazenamento (STORAGE_PROFILE=hdd | ssd)
- **Contexto:** Em Homelabs, muitos Mini PCs utilizam HD mecânico (com limitação severa de ~75 a 120 IOPS aleatórios), enquanto outros rodam em SSD/NVMe. O buffer de disco no Vector em HD gerava *Double Write* e *head thrashing*, causando I/O Wait no sistema.
- **Decisão:** Implementar seleção dinâmica via `STORAGE_PROFILE`:
  - **Modo HD (`vector.hdd.yaml`):** Buffer em memória RAM (`type: memory`), lotes de 2 MB / 2s para forçar escritas sequenciais no disco, filtro automático de pings/healthchecks no VRL e concorrência máxima de 2 buscas no VictoriaLogs.
  - **Modo SSD (`vector.ssd.yaml`):** Buffer persistente em disco (`256 MB`), lotes de 1 MB / 1s para baixa latência de consulta e concorrência de 4 buscas.
- **Alternativas consideradas:**
  - *Manter configuração única:* Prejudicaria HDs com alto I/O Wait ou limitaria o potencial de SSDs.
- **Consequências:** Stack adaptável instantaneamente a qualquer hardware de Homelab apenas alterando o `.env`.

### 2026-09-02 — Agregação Multilinha e Automação de Operações (Backup e Smoke Test)
- **Contexto:** Logs de erros com stack traces (Python, Go, Java) estavam sendo fragmentados pelo Docker em múltiplas linhas avulsas, dificultando diagnósticos. Além disso, backups manuais por cópia crua de pastas em HDs mecânicos arriscavam inconsistências de partição.
- **Decisão:**
  - Configurar bloco `multiline` nativo no Vector (`start_pattern: '^[\S]'`, `condition_pattern: '^[\s]'`, `mode: halt_before`) para agregar tracebacks em um único log antes do envio.
  - Implementar `scripts/backup.sh` usando a API atômica de snapshots (`/snapshot/create`) do VictoriaLogs com deleção e rotação posterior.
  - Implementar `scripts/test-pipeline.sh` para smoke test ponta a ponta com injeção sintética e query LogsQL.
  - Suportar autenticação básica HTTP opcional parametrizada em VictoriaLogs e Vector via `${VICTORIALOGS_AUTH_USERNAME:+...}`.
- **Consequências:** Diagnósticos de erros por LLMs/Devs preservam o contexto completo do erro, backups são atômicos e zero-downtime, e a stack ganha validação automatizada.

### 2026-09-03 — Expansão Canônica de Streams com `app` e `env`
- **Contexto:** Padronização da emissão de logs por novos serviços e agentes via skills de Observabilidade. A especificação canônica exige os campos `app` (nome do repositório/serviço) e `env` (ambiente: `production` ou `development`).
- **Decisão:**
  - Incluir `app` e `env` nos transforms VRL do Vector (`remap_docker`, `remap_syslog`, `remap_http`) com fallback seguro para `service` e `container_name`.
  - Expandir o cabeçalho canônico para `VL-Stream-Fields: "host,container_name,service,app,env,stream"`.
- **Consequências:** Buscas rápidas via LogsQL permitem particionamento instantâneo por `_stream:{app="api-gateway",env="production"}` mantendo 100% de retrocompatibilidade com logs legados que utilizavam `service`.

### 2026-09-03 — Dashboard CLI de Telemetria e Saúde via APIs Nativas
- **Contexto:** Necessidade de monitorar a saúde da stack, o consumo de RAM e os picos de erro em tempo real sem subir componentes pesados (Prometheus / Grafana) que violariam a meta de < 150 MB.
- **Decisão:** Desenvolver `scripts/health-dashboard.sh` consumindo endpoints nativos:
  - `/health` (conectividade), `/metrics` (uso de memória do runtime Go e total de linhas), `/select/logsql/hits` (contagem de erros/warnings em 15m/1h) e `/select/logsql/query` (Top 5 containers com mais logs).
- **Alternativas consideradas:**
  - *Subir container Grafana + Prometheus:* Consumiria 200MB+ de RAM adicionais, inviabilizando a meta de operação em Mini PC modesto.
- **Consequências:** Visibilidade instantânea de telemetria sem adicionar nenhum byte extra de consumo de memória em repouso.

### 2026-09-03 — Auto-monitoramento da Stack (Métricas Nativas VictoriaLogs e Vector)
- **Contexto:** Necessidade de coletar telemetria operacional da própria stack (throughput de logs ingeridos, buffer em disco/RAM, concorrência de queries e contagem de erros) sem adicionar containers pesados de monitoramento na mesma máquina.
- **Decisão:**
  - **VictoriaLogs:** Expor o endpoint nativo `/metrics` na porta configurada `9428`.
  - **Vector:** Adicionar a fonte `internal_metrics` e o sink `prometheus_exporter` na porta registrada `9598` (`VECTOR_METRICS_PORT`), servindo telemetria em tempo real no padrão Prometheus sob demanda de scraping.

### 2026-09-03 — Servidor MCP Nativo para Agentes de IA (Pure Python 3 / stdio)
- **Contexto:** Agentes de IA (Claude, Cursor, Antigravity) precisavam de comandos manuais de shell `curl` com queries LogsQL cruas, o que causava alto consumo de tokens de contexto, erros frequentes de escape/URL encoding e necessidade de aprovação de comandos pelo usuário.
- **Decisão:** Implementar `mcp/server.py` em Pure Python 3 (zero dependências externas) utilizando o protocolo MCP sobre `stdio` (JSON-RPC 2.0).
  - Ferramentas expostas: `query_logs`, `get_errors`, `get_log_hits`, `list_streams` e `health_check`.
  - Respostas pré-processadas e formatadas em Markdown compacto para economizar até 80% dos tokens em relação ao JSON bruto.
- **Consequências:** Agentes de IA conectam-se de forma nativa e segura ao VictoriaLogs com invocação direta de funções.

### 2026-09-04 — Padronização e Otimização Extrema do Servidor MCP em Python
- **Contexto:** Testes de benchmarking em hardware real revelaram que o MCP oficial em Go consumia 1.36 MB / ~350.000 tokens por consulta (estourando a janela de contexto de LLMs), enquanto o processo em Python consumia apenas 21.6 MB de RAM física (metade dos 46.7 MB do Go) e respondia em menos de 1 ms. Além disso, o binário Go acrescentava 33 MB ao repositório.
- **Decisão:**
  - Padronizar 100% no servidor MCP nativo em Python (`mcp/server.py`), descartando o binário Go de 33 MB.
  - Implementar deduplicação inteligente de erros repetidos (agrupando por assinatura da falha com contagem de ocorrências e timestamps de início/fim), preservando 100% da causa-raiz e economizando de 70% a 95% de tokens adicionais.
  - Adicionar projeção seletiva com `| keep` para não trafegar labels de Docker Compose na rede local.
  - Adicionar ferramentas de introspecção (`field_names`, `field_values`) e documentação offline de LogsQL (`documentation`), atingindo paridade total com o Go.
- **Consequências:** A stack ganha o servidor MCP mais leve, eficiente e contextualizado do ecossistema de observabilidade para agentes de IA, com zero dependências externas e zero binários pesados.

### 2026-09-03 — Governança e Versionamento de Skills para Agentes de IA
- **Contexto:** Desenvolvedores e agentes de IA que atuam em outros repositórios da organização `ye-sandbox` precisam de instruções padronizadas para integrar novas aplicações (Python, Node, Go, Docker) e consumir logs sem reescrever configurações do zero.
- **Decisão:**
  - Criar a skill `skills/victorialogs-integration/SKILL.md` com padrões de código, docker-compose e snippets JSON.
  - Instituir como regra inegociável no `AGENTS.md` (DoD) que qualquer alteração na arquitetura de ingestão ou consumo deve sincronizar imediatamente as SKILLs correspondentes.
- **Consequências:** Interoperabilidade contínua entre agentes de IA na organização `ye-sandbox`.

### 2026-09-03 — Regra de Coerência Contínua com o README.md
- **Contexto:** À medida que novas ferramentas (MCP, scripts operacionais, skills, perfis dinâmicos de HD/SSD) são adicionadas, a documentação pública do repositório pode sofrer divergência caso não seja atualizada em tandem.
- **Decisão:**
  - Tornar cláusula explícita no DoD (`AGENTS.md`) que o `README.md` (árvore de arquivos, comandos, tabelas e guias) DEVE ser atualizado a cada nova entrega ou ajuste arquitetural.
  - Atualizada a árvore estrutural do `README.md` refletindo os diretórios `mcp/`, `scripts/`, `skills/` e perfis de armazenamento.
- **Consequências:** O `README.md` reflete rigorosamente a verdade operacional da stack em qualquer commit.

---

## Contratos de Dados Vigentes

### Schema Canônico de Evento de Log

Todo log processado pelo Vector e ingerido no VictoriaLogs segue a seguinte estrutura canônica:

| Campo | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `timestamp` | `string (ISO8601)` | Timestamp da ocorrência do log em UTC | `2026-09-03T15:00:00.000Z` |
| `level` | `string` | Nível do log (`error`, `warn`, `info`, `debug`) | `info` |
| `app` | `string` | Identificador do repositório ou serviço | `api-gateway` |
| `env` | `string` | Ambiente de execução (`production`, `development`) | `production` |
| `message` | `string` | Mensagem do log (texto principal legível) | `Server started on port 8080` |
| `service` | `string` | Nome do serviço (mantido sincronizado com `app`) | `api-gateway` |
| `container_name`| `string` | Nome do container Docker ou fonte | `api-gateway` |
| `host` | `string` | Identificador do host/nó físico ou virtual | `mini-pc-proxmox` |
| `stream` | `string` | Canal de origem (`stdout`, `stderr`, `syslog`, `http`) | `stdout` |
| `context` | `object (opcional)`| Objeto com chaves extras de contexto ou metadados | `{"userId": 123}` |
| `structured` | `object (opcional)`| Objeto com chaves extras caso a mensagem seja JSON | `{"userId": 123}` |
| `stack_trace` | `string (opcional)`| Rastreamento da pilha em caso de erro | `Error: ...\n at ...` |

---

## Armadilhas e Comportamentos Não-Óbvios

- **Prevenção de Loop de Logs (Vector):**
  - *Armadilha:* Se o Vector coletar logs de todos os containers via `/var/run/docker.sock` sem excluir a si mesmo, qualquer erro ou log emitido pelo Vector será recoletado, gerando uma tempestade recursiva de logs e esgotando CPU.
  - *Mitigação:* A fonte `docker_logs` no `vector.yaml` obrigatoriamente inclui `exclude_containers: ["vector"]`.
- **Mapeamento de Memória do VictoriaLogs:**
  - *Armadilha:* O VictoriaLogs detecta a memória total da máquina se não configurado com `-memory.allowedPercent`.
  - *Mitigação:* Usamos a flag `-memory.allowedPercent=60` combinada com o limite Docker `deploy.resources.limits.memory: 80M`.
- **Buffer em Disco do Vector:**
  - *Armadilha:* Buffers em memória (`memory buffer`) podem sofrer crash OOM se o VictoriaLogs estiver reiniciando ou sob carga pesada.
  - *Mitigação:* Configuramos `buffer.type: disk` com `max_size: 104857600` (100 MB) apontando para o volume persistente `/var/lib/vector`.
- **Permissões do Docker Socket:**
  - *Armadilha:* No Linux, o `/var/run/docker.sock` exige permissões de leitura.
  - *Mitigação:* O container do Vector monta o socket em modo somente leitura (`:ro`).
- **Tag da Imagem Docker do VictoriaLogs:**
  - *Armadilha:* O Docker Hub não possui a tag `victoriametrics/victoria-logs:v1.23.0` (versões legadas utilizavam o sufixo `-victorialogs`, ex: `v1.23.0-victorialogs`, e versões modernas utilizam `v1.25.0+` ou `latest`). Tentar subir com `v1.23.0` causa erro do daemon `failed to resolve reference ... not found`.
  - *Mitigação:* Usar `latest` (ou `${VICTORIALOGS_VERSION:-latest}`) no `docker-compose.yml` e `.env.example`.
- **Healthcheck em Imagem Distroless (VictoriaLogs):**
  - *Armadilha:* A imagem do VictoriaLogs é construída a partir de `scratch` e não contém `/bin/sh`, `wget` ou `curl`. Usar `CMD-SHELL` faz o Docker falhar com erro de runtime OCI (`exec: "/bin/sh": stat /bin/sh: no such file or directory`) e marca o container como `unhealthy`.
  - *Mitigação:* Configurar a forma exec pura testando o binário estático: `test: ["CMD", "/victoria-logs-prod", "-version"]`.
- **Framing NDJSON no Sink HTTP do Vector:**
  - *Armadilha:* No sink HTTP do Vector, se `framing:` for colocado indentado dentro de `encoding:`, o Vector ignora o delimitador e encapsula o lote de eventos em um array JSON `[...]`. O endpoint `/insert/jsonline` do VictoriaLogs rejeita a carga com erro: `value doesn't contain object; it contains array`.
  - *Mitigação:* Manter `framing:` no mesmo nível hierárquico (irmão) de `encoding:` na configuração dos sinks do Vector.
- **API de Snapshot e Backup no VictoriaLogs:**
  - *Armadilha:* VictoriaLogs organiza dados em partições diárias e não suporta `/snapshot/create` do VictoriaMetrics. Tentar chamá-lo resulta em `unsupported path requested`. Além disso, a ausência de utilitários como `tar` dentro do container impede arquivamento in-loco.
  - *Mitigação:* Usar os endpoints `/internal/partition/snapshot/create` e `/internal/partition/snapshot/delete?path=...`, extraindo os dados via streaming com `docker cp "victorialogs:${path}"` para empacotar externamente.
- **Tokens com Caracteres Especiais no LogsQL (JIDs WhatsApp, E-mails, URLs):**
  - *Armadilha:* O parser do LogsQL não aceita tokens sem aspas contendo caracteres especiais (`@`, `:`, `/`, `-`, `.`, espaços). Por exemplo, consultar `120363421617257978@g.us` diretamente faz o VictoriaLogs interpretar `120363421617257978` como identificador esperando um separador `:`, falhando com HTTP 400 (`probably, the whole string must be put into quotes`).
  - *Mitigação:* Queries com caracteres especiais devem obrigatoriamente ser envolvidas em aspas duplas (`"120363421617257978@g.us"` ou `_msg:~"120363421617257978@g.us"`). Além disso, o servidor MCP (`mcp/server.py`) normaliza quebras de linha e detecta esse erro automaticamente, injetando uma dica contextual (`💡 Dica LogsQL`) para que agentes de IA se auto-corrijam imediatamente na chamada seguinte.

