# NOTES.md — Decisões, Contexto e Contratos do Projeto

> Guarda o PORQUÊ, não o QUE nem o COMO. Descrições de "o que foi feito" ficam no
> `git log` / commits. Passos de "o que fazer" ficam no `.agent/TASK.md`. Este arquivo é
> para decisões, trade-offs, contratos e armadilhas que **não são óbvias a partir do diff**.

---

## Decisões Arquiteturais e Contexto Técnico

### 2026-09-21 — Parâmetro service em field_names para Escopo por Aplicação no Servidor MCP
- **Contexto:** A ferramenta `field_names` do servidor MCP nativo (`/select/logsql/field_names`) provê introspecção de esquema para orientar agentes de IA e desenvolvedores sobre quais campos estruturados estão indexados no cluster. Anteriormente, a ferramenta aceitava apenas o parâmetro `time_range`, realizando busca global irrestrita em todos os containers e fluxos ativos. Em um cluster heterogêneo de homelab, essa abordagem retornava dezenas de campos irrelevantes (métricas de `docker-stats`, dumps de `cadvisor`, labels de infraestrutura e atributos aninhados de outras aplicações), poluindo a janela de contexto de LLMs e dificultando identificar quais campos realmente pertenciam à aplicação sob diagnóstico.
- **Decisão:**
  1. *Parâmetro Opcional `service`:* Permitir que agentes e desenvolvedores informem `service="app-name"` para delimitar a descoberta de campos estritamente aos logs daquela aplicação. Quando informado, o LogsQL injeta `_stream:{container_name="{service}"} OR _stream:{service="{service}"}` na query de `/select/logsql/field_names`. Quando omitido, a introspecção permanece 100% global e irrestrita, preservando retrocompatibilidade total.
  2. *Feedback Didático e Tratamento Defensivo:* Atualizar o cabeçalho de resposta para indicar o escopo (`### 🏷️ Indexed Fields in VictoriaLogs for `{service}` (Window: {time_range})`), exibir mensagem limpa caso o serviço não possua campos no período (`ℹ️ No fields found for service `{service}` in {time_range} window.`), e integrar `enrich_logsql_error` para fornecer dicas em caso de erros de sintaxe LogsQL.
  3. *Sincronização Canônica:* Atualizar o schema JSON-RPC no servidor MCP, a suíte de testes unitários (`tests/test_mcp_error_enricher.py`), o script de validação (`scripts/test-mcp.sh`), a skill canônica (`skills/victorialogs-troubleshooting/SKILL.md`), as diretrizes em `AGENTS.md` e a documentação pública (`README.md` e `README.pt-br.md`).
- **Consequências:** Descoberta cirúrgica de campos específicos de microsserviços, economia imediata de contexto para agentes de IA e zero ruído de outras aplicações durante a inspeção de esquema.

### 2026-09-21 — Parâmetro max_buckets e Aviso de Truncamento em get_log_hits no Servidor MCP
- **Contexto:** A ferramenta `get_log_hits` do servidor MCP nativo (`/select/logsql/hits`) é a porta de entrada da Fase 1 do funil de SRE para triagem temporal de picos de erro com zero payload de corpo de log. No entanto, a implementação anterior truncava silenciosamente o histograma nos últimos 15 buckets (`hits[-15:]`), sem qualquer parâmetro para o agente ou desenvolvedor solicitar maior histórico e sem qualquer indicador de que os primeiros intervalos haviam sido omitidos. Em janelas longas ou steps pequenos (ex: `time_range="24h"`, `step="5m"` -> 288 buckets), o agente de IA visualizava apenas 1h15m mais recentes e podia diagnosticar falsamente que o erro só havia iniciado naquele instante.
- **Decisão:**
  1. *Parâmetro Configurável:* Adicionar `max_buckets` (inteiro, padrão `15`) ao schema e à função `tool_get_log_hits`, permitindo que agentes expandam o número de intervalos conforme necessário para investigações amplas, preservando o padrão econômico de 15 buckets para consultas rotineiras.
  2. *Aviso Explícito de Truncamento:* Quando `len(hits) > max_buckets`, exibir aviso explícito ao final da tabela (`*Showing last {max_buckets} of {total_buckets} time buckets. Use 'max_buckets' to expand or adjust 'step' / 'time_range'.*`). Quando todos os buckets couberem, informar claramente (`*Showing all {total_buckets} time buckets.*`).
  3. *Sincronização Canônica:* Atualizar a documentação da ferramenta na skill `skills/victorialogs-troubleshooting/SKILL.md` e nos guias de SRE do `README.md` e `README.pt-br.md`.
- **Consequências:** Transparência diagnóstica total para agentes de IA durante a Fase 1 do funil de SRE, eliminação de conclusões precipitadas em incidentes distribuídos no tempo e governança estrita de tokens mantida por padrão.

### 2026-09-21 — Clamping Preventivo de 8 KB no remap_syslog (Paridade com Docker e HTTP)
- **Contexto:** Na Tarefa 41.0, o teto preventivo de 8 KB (`truncate(msg_str, 8192)`) foi aplicado aos transforms `remap_docker` e `remap_http` para conter mensagens anômalas não-críticas (dumps acidentais de memória, payloads base64 ou HTML/JSON extensos) que degradavam buffers em RAM e esgotavam janelas de contexto de LLMs. No entanto, o transform `remap_syslog` (porta UDP 5140) permaneceu sem essa salvaguarda, criando uma disparidade no pipeline de ingestão caso hosts externos (ex: nós Proxmox, roteadores ou switches) enviassem rajadas de syslog com payloads volumosos de debug/info.
- **Decisão:** Implementar a salvaguarda de teto de 8 KB no transform `remap_syslog` em todos os perfis (`vector.yaml`, `vector.hdd.yaml`, `vector.ssd.yaml`, `vector.geoip.yaml`). Para logs com `.level != "error"` cuja mensagem exceder 8192 caracteres, o Vector trunca o texto anexando ` ... [truncated by collector: N bytes total]` e marca `.truncated = true`. Logs com `.level == "error"` e tracebacks permanecem 100% preservados sem truncamento.
- **Consequências:** Paridade arquitetural completa nos três vetores de ingestão da stack (Docker, Syslog e HTTP), blindagem uniforme contra sobrecarga de memória e integridade garantida em análises forenses de erros.

### 2026-09-21 — Alinhamento do Fallback de Retenção Padrão (30d → 1y) e Diagnóstico do Healthcheck Distroless
- **Contexto:** Na Tarefa 24.0, a política de governança de retenção de logs foi formalmente estabelecida para 1 ano (`RETENTION_PERIOD=1y`), refletida no `.env.example` e nos scripts operacionais (`manage-partitions.sh`). No entanto, o `docker-compose.yml` ainda continha o fallback legado `-retentionPeriod=${RETENTION_PERIOD:-30d}`, e a documentação pública (`README.md` e `README.pt-br.md`) ainda sugeria `30d` no exemplo de `.env`. Caso o operador inicializasse o Docker Compose sem carregar o `.env`, o banco de dados truncaria logs após 30 dias em vez de manter o ciclo anual pretendido. Além disso, a proposta de substituir o healthcheck do VictoriaLogs por `wget /health` (antigo item 44.0) foi reanalisada e comprovada inviável: a imagem oficial `victoriametrics/victoria-logs` é estritamente distroless (`gcr.io/distroless/static`), contendo apenas `/victoria-logs-prod` e nenhum shell ou cliente HTTP (`wget`/`curl`), o que causaria erro de runtime OCI e deixaria o container em estado `unhealthy` permanente.
- **Decisão:**
  1. *Alinhamento de Fallback:* Atualizar `docker-compose.yml` para `-retentionPeriod=${RETENTION_PERIOD:-1y}`, garantindo conformidade com a política de 1 ano mesmo na ausência de `.env`.
  2. *Sincronização da Documentação:* Corrigir `README.md` e `README.pt-br.md` para exibir `RETENTION_PERIOD=1y` no setup inicial.
  3. *Manutenção do Healthcheck Exec no VictoriaLogs:* Manter o healthcheck atômico `["CMD", "/victoria-logs-prod", "-version"]` para a imagem distroless do VictoriaLogs, reservando `wget` apenas para serviços com base Linux/Alpine que possuem o utilitário nativo (como `vmalert`).
- **Consequências:** Coerência absoluta de retenção em todo o ecossistema (Compose, `.env`, documentação e rotinas de partição), eliminando risco de descarte precoce de histórico e preservando a estabilidade do container do VictoriaLogs.

### 2026-09-21 — Governança de Orçamento de Tokens nas SKILLs e Playbook de SRE
- **Contexto:** Embora o servidor MCP e o coletor Vector tenham sido otimizados (colapso de repetições, limpeza ANSI, projeção `fields` e teto preventivo no VRL), agentes de IA em incidentes de produção frequentemente executavam chamadas ingênuas (ex: `query_logs(query="error", limit=50)` sem escopo de aplicação ou `get_context_logs` com janelas excessivas). Esse comportamento consumia desnecessariamente até dezenas de milhares de tokens, levando a truncamentos de contexto do LLM, perda de foco em causa-raiz e custos elevados de inferência.
- **Decisão:** Formalizar e padronizar a governança de orçamento de tokens em toda a organização `ye-sandbox`:
  1. *Funil de Triagem de SRE em 3 Fases:* Obrigatoriedade do fluxo Fase 1 (`get_log_hits` para isolar início e taxa de erros com zero payload de corpo de log, ~50–150 tokens) ➔ Fase 2 (`get_errors` com `limit=5..10` e deduplicação ativa para extrair assinaturas e tracebacks sem ruído, ~300–800 tokens) ➔ Fase 3 (`get_context_logs` com janela e limite estritos `10..15`, ou `query_logs` projetando apenas atributos essenciais com `fields="http_status,duration_ms,request_id"`, ~200–500 tokens).
  2. *Amostragem Conservadora Padronizada:* Redução dos limites recomendados para agentes de IA para `limit=5..10`, permitindo expansão pontual apenas se identificado padrão de erro heterogêneo não categorizado.
  3. *Alinhamento Multilateral:* Sincronização explícita das diretrizes mandatórias no `AGENTS.md` (Diretiva 4), na skill canônica `skills/victorialogs-troubleshooting/SKILL.md` (seção de Governança de Tokens e anti-patterns) e na documentação pública bilíngue (`README.md` e `README.pt-br.md`).
- **Consequências:** Operação de agentes de IA com economia previsível superior a 90% em tokens por incidente, zero perda de capacidade diagnóstica forense e garantia de aderência uniforme a boas práticas de SRE.

### 2026-09-21 — Economia de Tokens no Servidor MCP (Colapso Consecutivo, Limpeza ANSI e Projeção fields)
- **Contexto:** Consultas forenses executadas por agentes de IA via MCP (`query_logs`, `get_context_logs`) frequentemente retornavam rajadas consecutivas de logs repetitivos (heartbeats, loops de polling, healthchecks periódicos) e sequências de escape de cores/formatação ANSI emitidas por runtimes modernos (Node.js, Python, Go). Cada sequência ANSI consumia de 4 a 6 tokens BPE extras sem agregar valor semântico, enquanto centenas de linhas repetidas esgotavam o orçamento de contexto do modelo. Além disso, agentes que necessitavam auditar campos específicos (ex: `http_status`, `duration_ms`, `request_id`) precisavam receber o JSON completo ou linhas longas com `_msg`.
- **Decisão:** Implementar três otimizações determinísticas no Servidor MCP nativo (`mcp/server.py`):
  1. *Higienização ANSI (`strip_ansi`):* Remoção automática via regex de todas as sequências de escape ANSI (cores, 256-cores, resets e códigos de cursor) nas mensagens extraídas e em todas as respostas de texto JSON-RPC antes da transmissão. Parsing resiliente via `json.loads(..., strict=False)` para tolerar caracteres de controle em strings brutas.
  2. *Colapso de Eventos Consecutivos Repetidos:* Agrupamento linear de eventos consecutivos com assinatura idêntica em `tool_query_logs` e `tool_get_context_logs`, preservando a primeira ocorrência e anotando com `(repeats Nx until HH:MM:SS)`. Em `get_context_logs`, o destaque visual do incidente (`🎯 [TARGET / INCIDENT]`) é preservado caso qualquer membro do grupo case com o segundo do alvo.
  3. *Projeção de Colunas e Renderização Ultra-Compacta (`fields`):* Parâmetro opcional `fields` em `tool_query_logs` que injeta `| keep _time, <fields>` no LogsQL e formata cada registro como linha chave-valor concisa (`**[HH:MM:SS]** (repeats Nx until HH:MM:SS) key1=val1 key2=val2`).
- **Consequências:** Redução de 70% a 95% no consumo de tokens em triagens forenses, eliminação total de ruído ANSI nas respostas para LLMs, preservação rigorosa da precisão temporal e zero quebra de compatibilidade com clientes MCP legados.

### 2026-09-21 — Otimização de Ingestão no Vector (Descarte de Scrapes /metrics e Teto Preventivo de Tamanho)
- **Contexto:** Logs de acesso de rotina a endpoints de métricas (`GET /metrics`) originados de scrapes regulares de Prometheus e vmalert representavam volume considerável de eventos desprovidos de valor diagnóstico forense quando bem-sucedidos (`200 OK`). Além disso, logs anômalos de tamanho excessivo (dumps acidentais de JSON/HTML ou payloads em base64) consumiam desproporcionalmente buffers de memória e janelas de contexto de agentes de IA quando emitidos em níveis informativos.
- **Decisão:** Implementar duas salvaguardas nos transforms VRL do Vector (`remap_docker` e `remap_http`) em todos os perfis (`vector.yaml`, `vector.hdd.yaml`, `vector.ssd.yaml`, `vector.geoip.yaml`):
  1. *Supressão de Scrapes de Métricas:* Descarte imediato via `abort` de logs casando com `r'(?i)\b(healthcheck|kube-probe|GET /health|GET /ping|GET /ready|GET /metrics|scrape)\b'` quando ausentes indícios de erro/falha (`r'(?i)\b(error\w*|fail\w*|warn\w*|401|403|500|502|503|504)\b'`) e fora dos níveis `error`/`warn`.
  2. *Clamping Preventivo de 8 KB:* Truncamento determinístico via `truncate(msg_str, 8192)` em `.message` quando `.level != "error"` e o tamanho excede 8192 caracteres, inserindo o marcador ` ... [truncated by collector: N bytes total]` e a flag booleana `.truncated = true`. Logs com `.level == "error"` e tracebacks nunca sofrem truncamento, preservando a capacidade de análise de causa-raiz.
- **Consequências:** Redução drástica de ruído de telemetria repetitiva no armazenamento do VictoriaLogs, proteção contra buffer overflows e estouro de contexto em modelos de linguagem, mantendo 100% de integridade e detalhe em logs de erro.

### 2026-09-21 — Supressão Padrão de Ruído de Telemetria (docker-stats e cadvisor) em Buscas Globais no MCP
- **Contexto:** Em auditorias da stack via VictoriaLogs, constatou-se que ~87% a 90% do volume total de logs ingeridos no cluster corresponde a telemetria periódica (`docker-stats` coletando CPU/RAM a cada 60s por container) e spam contínuo de advertências inofensivas do cAdvisor (`handler.go:422] Cannot read smaps files for any PID from CONTAINER`, decorrente da falta de privilégios de root para leitura de `/proc/<PID>/smaps`). Quando agentes de IA executavam consultas globais (`query_logs`, `get_errors`, `get_log_hits` ou `get_context_logs` sem o parâmetro `service`), os resultados eram dominados por esse ruído de métricas, gerando desperdício massivo de tokens de contexto do LLM e ofuscando erros reais de aplicações.
- **Decisão:** Implementar filtro canônico transparente no Servidor MCP (`mcp/server.py`):
  `DEFAULT_NOISE_EXCLUSION = 'NOT service:in("docker-stats", "cadvisor") AND NOT container_name:"cadvisor"'`.
  Esse filtro é injetado automaticamente em consultas globais quando `service` não é fornecido e a query não faz menção explícita a esses serviços. Caso o operador ou agente necessite auditar métricas de recursos ou o cAdvisor, basta passar explicitamente `service="docker-stats"` ou `service="cadvisor"`. As ferramentas de descoberta (`list_streams`, `field_names`, `field_values`) permanecem 100% irrestritas.
- **Consequências:** Economia drástica de tokens (consultas globais retornam instantaneamente apenas logs reais de aplicações e proxies), preservação integral da capacidade de diagnóstico forense e zero perda de dados históricos armazenados.

### 2026-09-15 — Tradução de AGENTS.md, Servidor MCP e Ferramentas Correlacionadas para Inglês
- **Contexto:** Após a internacionalização das SKILLs (Tarefa 38.0), o arquivo `AGENTS.md` e os esquemas/mensagens do Servidor MCP nativo (`mcp/server.py`) permaneciam em português. Modelos de linguagem modernos (Claude, Gemini, GPT) processam instruções e chamadas de ferramentas de forma substancialmente mais rápida, barata (30% a 50% menos tokens na tokenização BPE) e precisa quando o vocabulário de sistema e os schemas JSON-RPC são em inglês técnico idiomático.
- **Decisão:** Traduzir integralmente `AGENTS.md` (diretrizes do agente, protocolo de execução, tech stack, regras do servidor MCP e comandos de validação), `mcp/server.py` (esquemas JSON-RPC de todas as 9 ferramentas, parâmetros, mensagens de erro enriquecidas `enrich_logsql_error`, dicas de SRE, docstrings e saídas formatadas), a suíte de testes unitários `tests/test_mcp_error_enricher.py` e o script de integração `scripts/test-mcp.sh` para o inglês técnico conciso. Nomes das ferramentas e chaves de parâmetros foram rigorosamente preservados para manter 100% de retrocompatibilidade de API.
- **Consequências:** Paridade semântica completa com o `README.md` internacional e as SKILLs, economia de contexto na invocação de ferramentas MCP por LLMs e zero fricção para desenvolvedores e agentes de IA que operam no ecossistema open-source.

### 2026-09-15 — Tradução Canônica 1:1 das SKILLs para Inglês com Foco em Economia de Tokens
- **Contexto:** Agentes de IA modernos utilizam tokenização baseada em subpalavras (BPE) treinadas predominantemente em inglês. SKILLs escritas em português consomem de 30% a 50% mais tokens de contexto e sofrem maior dispersão interpretativa por LLMs (Claude, Gemini, GPT).
- **Decisão:** Traduzir integralmente e de forma 1:1 todas as skills canônicas do repositório (`skills/github-bug-issue/SKILL.md`, `skills/victorialogs-troubleshooting/SKILL.md`, `skills/victorialogs-integration/SKILL.md`, `skills/victorialogs-integration/examples/README.md`) e os comentários/docstrings de seus templates para o inglês técnico conciso e de alta densidade semântica. Nomes de pastas e arquivos foram mantidos idênticos para total retrocompatibilidade com symlinks locais.
- **Consequências:** Máxima preservação da janela de contexto de agentes de IA em toda a organização `ye-sandbox`, cumprimento mais rigoroso de instruções imperativas de SRE e zero perda de contexto de engenharia.

### 2026-09-13 — Alinhamento das Diretrizes de MCP no AGENTS.md e Sincronização de Skills
- **Contexto:** O `AGENTS.md` continha menções periféricas a MCP e uma referência desatualizada a compressão `gzip` (quando o sink utiliza `zstd`), e a skill `victorialogs-troubleshooting` continha uma discrepância na contagem de ferramentas (8 vs 9) e numeração duplicada. Agentes de IA operando no repositório precisam de diretrizes claras sobre o servidor MCP nativo e as regras operacionais de consulta.
- **Decisão:** Atualizar o `AGENTS.md` documentando explicitamente o servidor MCP nativo (`mcp/server.py`), suas 9 ferramentas otimizadas, e fixando as 3 diretrizes essenciais de SRE: escopo obrigatório por aplicação (`service="nome-do-app"`), aspas duplas obrigatórias em identificadores com caracteres especiais (`@`, `:`, `/`, `.`) no LogsQL e referência à skill canônica `victorialogs-troubleshooting`. A contagem e numeração em `skills/victorialogs-troubleshooting/SKILL.md` foram devidamente corrigidas para 9 ferramentas.
- **Consequências:** Coerência absoluta entre código real, documentação técnica (`AGENTS.md`, `README.md`) e skills de agentes em toda a organização `ye-sandbox`.

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

### 2026-09-05 — Calibração de Lote no Vector para HD Único no Proxmox (batch.timeout_secs = 15s)
- **Contexto:** Em servidores Proxmox onde todo o sistema operacional, Docker e containers residem no mesmo e único disco rígido mecânico (HD), a concorrência na agulha mecânica é severa. O timeout anterior de 2 segundos disparava micro-lotes constantes (até 30 escritas por minuto), mesmo com baixíssimo tráfego de logs.
- **Decisão:** Elevar `batch.timeout_secs` de 2s para 15s no perfil de HD (`vector.hdd.yaml` e `vector.yaml`).
- **Consequências:** Redução de até ~87% na frequência de I/O em disco (de 30 para no máximo 4 gravações por minuto em períodos ociosos), permitindo consolidação em memória RAM antes da escrita sequencial contínua no VictoriaLogs sem impacto perceptível na experiência de observabilidade.

### 2026-09-05 — Calibração de Flush em Memória do VictoriaLogs (-inmemoryDataFlushInterval = 15s)
- **Contexto:** VictoriaLogs organiza dados em formato LSM-tree e periodicamente descarrega da RAM para o disco. O intervalo padrão rápido (1s-5s) em HDs mecânicos gera uma proliferação de pequenas peças que forçam o engine a rodar rotinas contínuas de *merge* (compactação em segundo plano), provocando alta contenção na cabeça de leitura/gravação.
- **Decisão:** Adicionar a flag `-inmemoryDataFlushInterval=${VL_INMEMORY_FLUSH_INTERVAL:-15s}` no `docker-compose.yml`, sincronizada com o intervalo de 15s do Vector.
- **Consequências:** VictoriaLogs retém os logs na RAM por 15s antes de descarregar peças em disco, gerando peças já compactadas e diminuindo drasticamente os merges. O volume acumulado em 15s de tráfego de homelab (~300 KB a 2 MB) é desprezível e cabe com folga no teto de 80 MB, contando ainda com o circuit-breaker nativo de `-memory.allowedPercent=60` para descarte imediato em caso de picos anômalos.

### 2026-09-05 — Docker Host Non-Blocking Logging para Proteção contra I/O Wait em HD
- **Contexto:** Em hosts Proxmox onde todo o sistema operacional, Docker e containers compartilham um único HD mecânico, o driver padrão `json-file` do Docker grava em modo síncrono bloqueante (`blocking`). Qualquer pico de I/O no disco físico (ex: backup noturno do Proxmox) causa lentidão e congelamentos temporários nas aplicações Docker locais devido a syscalls de escrita bloqueadas.
- **Decisão:** Desenvolver `scripts/tune-docker-host.sh` e documentar a configuração de `/etc/docker/daemon.json` com `mode: non-blocking` e `max-buffer-size: 4m`.
- **Consequências:** O Docker descarrega logs em ring-buffers na RAM (4 MB por container) e segue processando requisições sem esperar o HD mecânico responder. Em caso de saturação extrema prolongada de I/O, o Docker descarta logs excedentes no ring-buffer mais antigo em vez de travar a aplicação, priorizando a estabilidade e a disponibilidade dos serviços do homelab.

### 2026-09-05 — Otimizações de Kernel e Filesystem no Host Proxmox (noatime, mq-deadline e APM)
- **Contexto:** Ambientes de Homelab rodando em disco mecânico único sofrem severamente com três características padrão do Linux moderno: (1) `relatime/atime` gerando escritas de metadados durante leituras de logs, (2) I/O scheduler `none` (herança de NVMe) enviando I/O caótico para a agulha móvel sem algoritmo de elevador, e (3) políticas de gerenciamento de energia que forçam ciclos contínuos de aceleração/parada do motor (*spin-up/spindown*).
- **Decisão:** Desenvolver `scripts/tune-disk-host.sh` para diagnóstico não-invasivo de discos, suporte a geração de regras udev para fixar `mq-deadline` em discos rotacionais (`queue/rotational == 1`) e documentação de `noatime,nodiratime` para `/etc/fstab`.
- **Consequências:** Leituras e consultas LogsQL tornam-se puramente passivas sem alterar metadados em disco, a cabeça de leitura move-se linearmente em trilhas contíguas (evitando *head thrashing*), e o motor opera estável 24/7 sem estresse mecânico no braço ativador.

### 2026-09-12 — Detecção de Virtualização e Prevenção de Duplo Agendamento no tune-disk-host.sh
- **Contexto:** Ao executar `tune-disk-host.sh` dentro de máquinas virtuais (ex: VM QEMU/KVM no Proxmox), o script tratava discos virtuais (`/dev/sda` com `rotational == 1`) como HDs físicos mecânicos, emitindo alertas incorretos de APM/spindown (`hdparm`) e recomendando `mq-deadline`.
- **Decisão:** Refatorar `scripts/tune-disk-host.sh` para detectar automaticamente ambientes virtualizados (`systemd-detect-virt`, DMI sysfs, modelo do disco contendo QEMU/VBOX/VMware/VIRTIO/Virtual ou prefixos `vd*`/`xvd*`):
  - Em discos virtuais: recomendar `none` (NOOP/passthrough) para evitar sobrecarga de duplo agendamento de I/O com o hipervisor host.
  - Omitir completamente verificações e recomendações de `hdparm` (APM e spindown) em VMs, delegando o gerenciamento do hardware físico ao host Proxmox.
  - Manter e priorizar `noatime,nodiratime` para todos os ambientes (físicos e virtuais), eliminando escritas inúteis de metadados em consultas.
- **Consequências:** Diagnósticos 100% precisos tanto no host Proxmox bare-metal quanto em VMs convidadas, evitando desconfiguração de I/O schedulers em ambientes virtualizados.

### 2026-09-02 — Agregação Multilinha e Automação de Operações (Backup e Smoke Test)
- **Contexto:** Logs de erros com stack traces (Python, Go, Java) estavam sendo fragmentados pelo Docker em múltiplas linhas avulsas, dificultando diagnósticos. Além disso, backups manuais por cópia crua de pastas em HDs mecânicos arriscavam inconsistências de partição.
- **Decisão:**
  - Configurar bloco `multiline` nativo no Vector (`start_pattern: '^[\S]'`, `condition_pattern: '^[\s]'`, `mode: continue_through`) para agregar tracebacks indentados em um único log antes do envio.
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

### 2026-09-06 — MCP do Cursor é config local; IP de LAN não entra no Git
- **Contexto:** O VictoriaLogs frequentemente roda numa VM (Proxmox) enquanto o Cursor roda na workstation. Consultas MCP a `127.0.0.1:9428` a partir do WSL/Windows falham porque a stack não está no host do cliente. Um `.cursor/mcp.json` versionado com o IP da LAN vazaria topologia de rede e, no futuro, credenciais de Basic Auth.
- **Decisão:** Ignorar `.cursor/` no Git. O `VICTORIALOGS_URL` real vive só em arquivos locais (`.env`, `.cursor/mcp.json`, `~/.cursor/mcp.json`). O `.env.example` e o README usam placeholders (`127.0.0.1` / `<IP_DO_MINI_PC>`).
- **Consequências:** Quem clona o repositório precisa criar o `mcp.json` local apontando para o host onde *ele* alcança a porta 9428. Se o IP da VM mudar, atualizar apenas `.env` e o `mcp.json` local — nunca o template público.

### 2026-09-06 — Skills canônicas neste repo; Cursor descobre via symlink pessoal
- **Contexto:** O Cursor só carrega skills de `.cursor/skills/` ou `~/.cursor/skills/`. A pasta `skills/` na raiz não dispara sozinha. Copiar o SKILL.md para cada app da `ye-sandbox` dessincroniza o contrato quando o Vector muda.
- **Decisão:** Manter as skills canônicas neste repositório (`victorialogs-integration`, `victorialogs-troubleshooting`, `github-bug-issue`). Não criar uma skill irmã de “JSON logging” — isso é contrato da integration. Outros repos apontam no `AGENTS.md`. Descoberta no Cursor: `ln -sfn` de `~/.cursor/skills/<nome>` para `skills/<nome>` deste clone.
- **Consequências:** Atualizar NDJSON/stream fields neste Git atualiza todos os agentes que usam o symlink. `.cursor/` continua gitignored por causa do `mcp.json` local.

### 2026-09-07 — Multiline `continue_through` (não `halt_before`) para NDJSON
- **Contexto:** `halt_before` com `condition_pattern: '^[\s]'` acumula **todas** as linhas que não são indentadas até `timeout_ms`. Rajadas NDJSON (`{...}` por linha) no mesmo segundo viravam um único `_msg` com `}\n{`; `parse_json` falhava e a heurística de `level` herdava `error`/`warn` de um membro qualquer da rajada ([issue #1](https://github.com/ye-sandbox/infra-victoria-logs/issues/1)).
- **Decisão:** Nos três perfis (`vector.yaml`, `vector.hdd.yaml`, `vector.ssd.yaml`), `mode: continue_through`. Linhas indentadas continuam anexadas à linha-mãe (traceback); a próxima linha não-indentada fecha o grupo imediatamente.

### 2026-09-10 — Telemetria de Recursos via `ship-docker-stats.sh`
- **Contexto:** Diagnóstico de incidentes por agentes de IA necessita de visibilidade de CPU, RAM e limites dos containers sem incorrer no consumo de memória de Prometheus/Grafana (< 150 MB total da stack).
- **Decisão:** Desenvolver `scripts/ship-docker-stats.sh` convertendo a saída de `docker stats --no-stream` em eventos estruturados no stream `service="docker-stats"` e enviando em lote para o endpoint HTTP do Vector (`:8686/logs`). No Vector, o source `http_logs` espera formato `encoding: json` (aceitando array JSON `[...]` para lote pontual).
- **Consequências:** Agentes de IA correlacionam quedas e lentidões diretamente no LogsQL (`_stream:{service="docker-stats",container_name="..."}` ou `mem_percent:>85`) com impacto nulo na memória da stack.

### 2026-09-10 — Captura de Ciclo de Vida do Daemon Docker (`ship-docker-events.sh`)
- **Contexto:** Mortes de containers por OOM (`SIGKILL` / Exit Code 137) ou terminação anômala do processo não geram logs em `stdout`. Os agentes executavam `get_errors()` e concluíam incorretamente que não havia ocorrido erro na aplicação.
- **Decisão:** Desenvolver `scripts/ship-docker-events.sh` escutando o stream de eventos do Docker Engine (`docker events --filter 'type=container'`) e normalizando ações críticas (`die`, `oom`, `kill`, `restart`) no stream `service="docker-events"`. Eventos de `die` com código 137 ou ação `oom` são automaticamente elevados a `level: "error"` com `oom_killed: true`.
- **Consequências:** Agentes de IA diagnosticam instantaneamente quedas silenciosas e estouro de memória sem ambiguidade.

### 2026-09-10 — Promoção Canônica de Campos de Correlação no VRL
- **Contexto:** Aplicações emitem identificadores distribuídos e métricas HTTP com nomes heterogêneos (`traceId`, `statusCode`, `correlation_id`, `duration`), confinando esses dados no objeto aninhado `.structured` e impossibilitando filtros numéricos ou comparativos diretos no LogsQL (`http_status:>=500` ou `duration_ms:>1000`).
- **Decisão:** Nos 3 perfis do Vector (`vector.hdd.yaml`, `vector.ssd.yaml`, `vector.yaml`), promover no primeiro nível: `trace_id`, `request_id`, `http_status` e `duration_ms` a partir de suas variantes mais comuns, mantendo-os fora do `VL-Stream-Fields` para evitar alta cardinalidade. Refinada também a severidade de `remap_syslog` com fallback de regex de falhas.
- **Consequências:** Agentes rastreiam transações em 1 query pontual (`request_id:"..."`) e filtram latências e erros HTTP numericamente sem consumir tokens de leitura de strings brutas.

### 2026-09-10 — Ferramenta Forense `get_context_logs` no MCP
- **Contexto:** Ao isolar uma falha via `get_errors()`, a IA frequentemente precisa entender o que aconteceu nos instantes anteriores ao erro (logs `info` e `debug` da mesma transação ou do mesmo container). Calcular janelas de tempo manualmente no LogsQL é propenso a erros de formatação de data UTC e gasta chamadas de ferramentas desnecessárias.
- **Decisão:** Implementar a 9ª ferramenta `get_context_logs(target_timestamp, service, window_seconds=15)` no MCP Server, calculando `_time:[start, end]` automaticamente, ordenando cronologicamente (`_time asc`) e aplicando marcação visual (`🎯 [ALVO / INCIDENTE]`) no segundo exato da ocorrência.
- **Consequências:** Diagnóstico de causa-raiz imediato em 1 passo após a detecção de um traceback.

### 2026-09-10 — Sincronização Automatizada de SKILLs via `install-agent-skills.sh`
- **Contexto:** A interoperabilidade de outros repositórios da `ye-sandbox` depende de as skills canônicas deste repositório estarem disponíveis nos diretórios globais de IA do desenvolvedor (`~/.cursor/skills`, `~/.gemini/antigravity/skills`). Fazer symlinks manuais por terminal a cada atualização gerava atrito e risco de apontamentos quebrados.
- **Decisão:** Desenvolver `scripts/install-agent-skills.sh` com suporte a `--all`, `--cursor`, `--antigravity` e `--dry-run`, criando symlinks idempotentes (`ln -sfn`) para todas as pastas de `skills/`.
- **Consequências:** Com 1 único comando, qualquer cliente de IA passa a enxergar as 3 skills canônicas atualizadas em tempo real a partir deste clone.

### 2026-09-10 — Serviço Daemon e Automação no Host dos Coletores de Recursos e Eventos
- **Contexto:** Os scripts `ship-docker-stats.sh` e `ship-docker-events.sh` coletam telemetria essencial de CPU/RAM e eventos de ciclo de vida (OOM kills/restarts). Se executados apenas em sessões manuais ou screen/tmux, qualquer reboot do host Proxmox ou encerramento acidental interrompia a coleta de métricas e auditoria.
- **Decisão:** Criar `scripts/install-host-collectors.sh` para gerenciar o ciclo de vida systemd (`victoria-docker-stats.service` e `victoria-docker-events.service`), com opções de instalação (`--install`), remoção (`--uninstall`), status (`--status`) e simulação segura (`--dry-run`). As unidades configuram `Restart=always`, `RestartSec=5s`, e isolamento de segurança básico com path absoluto inferido automaticamente.

- **Consequências:** Coleta 24/7 resiliente a reinicializações no Proxmox/Mini PC com footprint de CPU e memória desprezível (< 10 MB para os dois processos combinados).

### 2026-09-10 — Templates de Logging Canônico Plug-and-Play (Loguru, Pino, Slog)
- **Contexto:** Desenvolvedores e agentes de IA integrando novos microsserviços na organização `ye-sandbox` implementavam pipelines de logging com formatos inconsistentes (quebras de linha avulsas em traceback quebrando o parser JSON do Vector, níveis de log em maiúsculas, chaves de rastreamento com nomes divergentes como `cid`, `traceId`, `statusCode`).
- **Decisão:** Criar biblioteca de templates plug-and-play em `skills/victorialogs-integration/examples/` para Python (**Loguru** com sink customizado e stdlib pura), Node.js (**Pino**) e Go (**slog**). Todos garantem NDJSON rigoroso (1 linha JSON), timestamps UTC ISO-8601, injeção de `service`/`app`/`env`, e os campos canônicos promovidos (`trace_id`, `request_id`, `http_status`, `duration_ms`).
- **Consequências:** Eliminação de erros de parsing no coletor e máxima agilidade para novas aplicações gerarem logs compatíveis com o ecossistema e ferramentas forenses do MCP em 1 clique.

### 2026-09-10 — Suporte a Alertas Nativos via vmalert Conectado ao VictoriaLogs
- **Contexto:** Necessidade de alertas automatizados em tempo real (picos de erro, containers finalizados por OOM, mortes anômalas, latência HTTP elevada) sem incorrer no consumo de memória de stacks pesadas de monitoramento, preservando a restrição rígida de hardware do homelab (< 150 MB de RAM).
- **Decisão:** Incorporar o binário ultra-leve `vmalert` como serviço opcional no `docker-compose.yml` utilizando Docker Compose Profiles (`profiles: ["alerting"]`), com limite estrito de `memory: 25M` e `cpus: 0.20`. O `vmalert` consome regras nativas em LogsQL (`type: vlogs`) em `vmalert/rules.yaml` consultando diretamente o VictoriaLogs (`-datasource.url=http://victorialogs:9428`), com suporte a HTTP Basic Auth e encaminhamento de alertas para webhook/Alertmanager (`-notifier.url`).
- **Consequências:** Monitoramento ativo 24/7 com consumo inferior a 20 MB de RAM quando ativo, zero overhead para quem roda apenas a stack básica (inativo por padrão), e regras LogsQL prontas para detecção de incidentes críticos.

### 2026-09-10 — Enriquecimento Opcional de Logs com GeoIP para Tráfego Web
- **Contexto:** Tráfego de internet para webservers e proxies reversos (Nginx, Traefik, Caddy) gera logs com endereços IP públicos de clientes. Analisar ataques ou tráfego sem localização geográfica exige consultas manuais lentas. Por outro lado, carregar obrigatoriamente a base MaxMind GeoLite2 City (.mmdb ~70 MB) inflaria a memória do Vector nos perfis padrão de homelab sem exposição web.
- **Decisão:** Criar perfil dedicado `vector/vector.geoip.yaml` selecionável via `STORAGE_PROFILE=geoip` e utilitário `scripts/download-geolite2.sh`. O perfil utiliza o bloco `enrichment_tables` com `type: geoip` nativo do Vector, enriquecendo o evento com `geoip.country_code`, `geoip.country_name`, `geoip.city_name`, `latitude` e `longitude`.
- **Armadilha Evitada:** Esses campos de geolocalização **NUNCA** devem ser inseridos em `VL-Stream-Fields` (isso causaria explosão incontrolável de streams por cidade/país). Eles residem como campos estruturados normais do evento no primeiro nível / objeto `geoip`.
- **Consequências:** Capacidade forense geo-espacial instantânea sem violar os tetos de memória dos usuários que não precisam de GeoIP.

### 2026-09-10 — Painel de Consultas LogsQL Pré-configuradas via Terminal (`logsql-queries.sh`)
- **Contexto:** Operadores no host Proxmox e agentes em sessões de troubleshooting precisavam frequentemente de queries recorrentes (Top erros por serviço, análise de latência `duration_ms:>1000`, distribuição de status HTTP e auditoria de crashes do Docker). Construir chamadas de `curl` longas com URL-encoding e parsing de JSON consumia tempo e gerava erros de sintaxe.
- **Decisão:** Desenvolver `scripts/logsql-queries.sh` com comandos canônicos (`top-errors`, `slow-requests`, `http-status`, `crashes`, `trace <ID>`, `stats-summary`, `raw "<QUERY>"`), com suporte a flags de janela de tempo (`--time 24h`), filtro por serviço (`--service`) e opção `--json` para integração com pipes ou scripts.
- **Consequências:** Visibilidade forense e analítica imediata no shell com tabelas alinhadas para humanos ou JSON estruturado para automações e LLMs.

### 2026-09-10 — Gestão, Auditoria e Purga Emergencial de Partições Físicas (Retenção de 1 Ano)
- **Contexto:** O operador definiu o requisito de governança para manter 1 ano completo de logs (`RETENTION_PERIOD=1y`). A auditoria com dados reais do cluster comprovou que a compressão Zstandard do VictoriaLogs gera apenas ~540 KB comprimidos por dia de operação, totalizando menos de 200 MB por ano (menos de 0.02% do disco de 1 TB). No entanto, fazia-se necessário um utilitário para auditar partições diárias ativas, calcular a capacidade projetada e agir como freio emergencial contra tempestades acidentais de logs.
- **Decisão:** Criar `scripts/manage-partitions.sh` com suporte a:
  1. `list`: Inventaria partições diárias no banco e espaço físico ocupado no volume.
  2. `estimate`: Projeta o consumo para 30d, 90d, 180d e 365d com base na média histórica real.
  3. `purge`: Purga atômica e emergencial via API nativa (`/internal/partition/delete?path=...`) por idade (`--older-than Nd`), data (`--before YYYYMMDD`) ou excedente (`--keep-last N`), com `--dry-run` preventivo e confirmação interativa.
  4. Atualizar `RETENTION_PERIOD=1y` como padrão no `.env.example` e `.env`.
- **Consequências:** Tranquilidade operacional para manter 1 ano de histórico sem qualquer risco de surpresa por falta de espaço em disco no homelab.

### 2026-09-10 — Auditoria e Alerta Periódico de Capacidade de Partições por Cron (`check-disk-growth.sh`)
- **Contexto:** Garantir que o plano de retenção de 1 ano não seja subitamente comprometido por containers desgovernados gerando rajadas de gigabytes de logs ou por esgotamento do disco raiz no host Proxmox/Mini PC.
- **Decisão:** Implementar `scripts/check-disk-growth.sh` com checagem automática de taxa diária de ingestão (`--threshold-daily-mb`, padrão 1000 MB) e porcentagem mínima de disco livre (`--min-free-disk-percent`, padrão 10%). Em caso de violação, o script emite evento de nível `ERROR` para o coletor Vector (porta 8686) e opcionalmente dispara webhook externo, com opções `--install-cron`, `--uninstall-cron` e `--dry-run`.
- **Consequências:** Monitoramento ativo e preventivo de capacidade sem necessidade de agentes externos pesados.

### 2026-09-11 — Dashboard Grafana Oficial Pré-construído (`dashboards/grafana-victorialogs.json`)
- **Contexto:** Visualização em tempo real de throughput de logs, saúde de componentes, erros de pipeline do Vector e concorrência de busca no VictoriaLogs sem esforço de montagem manual de queries PromQL.
- **Decisão:** Criar modelo JSON oficial modular (`dashboards/grafana-victorialogs.json`) com variável dinâmica de data source (`${DS_PROMETHEUS}`), organizado em 3 linhas colapsáveis: 1) Visão Geral & Saúde da Stack (Status Online/Offline, volume total, linhas ingeridas); 2) Vazão e Performance (Logs/s e Bytes/s no VictoriaLogs e Vector); 3) Pipeline Vector & Concorrência (Buscas LogsQL ativas vs capacidade máxima, e contagem de erros de pipeline).
- **Consequências:** Importação em 1 clique em qualquer Grafana existente com visualização rica e zero configuração manual.

### 2026-09-11 — Rotina de Teste Automatizado de Integridade e Snapshot Diário (`run-maintenance-pipeline.sh`)
- **Contexto:** Evitar a dispersão de múltiplas rotinas no crontab e garantir que os 3 pilares de governança (auditoria de disco, backup consistente e validação de buscas LogsQL) rodem de forma coordenada e sequencial.
- **Decisão:** Implementar o orquestrador `scripts/run-maintenance-pipeline.sh` que encadeia `check-disk-growth.sh` -> `backup.sh` -> `test-pipeline.sh`, abortando preventivamente o backup caso o disco esteja em nível crítico, e emitindo evento estruturado de telemetria consolidada para o Vector na porta 8686. O utilitário inclui comandos de instalação no crontab (`--install-cron` às 03:00 UTC) e simulação (`--dry-run`).
- **Consequências:** Operação 100% autônoma e resiliente no homelab com rastreabilidade completa e zero manutenção manual diária.

### 2026-09-11 — Auditoria de Segurança do Host e Isolamento de Containers (`audit-security.sh`)
- **Contexto:** Em servidores homelab e Proxmox, permissões excessivas de arquivos (como `.env` legível por outros usuários do host), montagem com escrita do socket do Docker (`/var/run/docker.sock`) e omissão de limites de memória representam riscos severos de vazamento de credenciais, escape de container e travamento do host por OOM.
- **Decisão:** Desenvolver `scripts/audit-security.sh` inspecionando 4 pilares:
  1. *Host & Filesystem:* Permissões restritas no `.env` (`600`/`400`), ausência no Git e bloqueio de escrita pública em scripts.
  2. *Docker Compose Hardening:* Socket Docker estritamente somente leitura (`:ro`), limites rígidos de RAM (<= 80M e <= 60M), prevenção de loop (`exclude_containers: ["vector"]`) e healthchecks ativos.
  3. *Rede & Autenticação:* Auditoria de portas em `0.0.0.0` vs ativação de HTTP Basic Auth.
  4. *Runtime:* Verificação dos limites efetivamente aplicados no kernel via `docker inspect`.
  O utilitário oferece auto-reparo com `--fix` (`chmod 600 .env`, `chmod 755 scripts/*.sh`), saída `--json` para agentes e código de saída semântico.
- **Consequências:** Postura de segurança do host blindada com capacidade de auditoria e correção em 1 clique.

### 2026-09-11 — Guia Consolidado de Hardening e Boas Práticas no Proxmox VE (`docs/proxmox-hardening.md`)
- **Contexto:** Operadores de homelab frequentemente enfrentavam dúvidas sobre a melhor topologia de execução da stack no Proxmox (VM KVM vs LXC), como evitar travamentos de mmap do VictoriaLogs, como conter o I/O em discos mecânicos compartilhados e como blindar as portas de telemetria sem expô-las a redes não confiáveis.
- **Decisão:** Criar `docs/proxmox-hardening.md` consolidando:
  1. Topologia: recomendação formal de VM KVM (Debian/Ubuntu minimal, 1-2 vCPU, 1-2 GB RAM) para contenção total de kernel e socket Docker isolado; restrições para LXC unprivileged com `nesting=1`.
  2. Kernel: parâmetros recomendados em `/etc/sysctl.d/99-observability.conf` (`vm.max_map_count=262144`, `vm.swappiness=10`, `fs.file-max=2097152`, sockets backlog).
  3. Storage: eliminação de `atime` (`noatime,nodiratime`), elevador `mq-deadline` para HDs e Docker assíncrono `non-blocking`.
  4. Rede: regras de Proxmox Firewall para portas 9428 e 8686 e uso de HTTP Basic Auth.
  5. Governança: integração dos utilitários `audit-security.sh`, `run-maintenance-pipeline.sh` e `install-host-collectors.sh` com checklists pré e pós-deploy.
- **Consequências:** Documentação de referência canônica para provisionamento e auditoria de novos nós no homelab, mantendo alinhamento de segurança entre desenvolvedores humanos e agentes de IA.

### 2026-09-11 — Nomeação Determinística e Rastreabilidade de Containers Efêmeros
- **Contexto:** Como a imagem oficial do VictoriaLogs é distroless pura (`scratch`), scripts como `check-disk-growth.sh` e `manage-partitions.sh` executam `docker run --rm ... alpine` para medir volumes em disco. Sem as flags `--name` e `--label`, o Docker atribuía nomes aleatórios (ex: `friendly_wozniak`), poluindo a telemetria do daemon capturada por `ship-docker-events.sh` e dificultando a identificação de containers caso houvesse terminação anômala.
- **Decisão:** Padronizar todas as invocações de containers utilitários efêmeros com:
  - `--name "<servico>-<funcao>-$$"` (utilizando o PID `$$` do processo para garantir concorrência segura sem colisão de nomes).
  - `--label "app=infra-victoria-logs"` e `--label "component=maintenance"`.
  - Atualizado também o comando de validação do Vector no `AGENTS.md` com `--name vector-config-validator`.
- **Consequências:** Eliminação de eventos com nomes anônimos no stream `service="docker-events"`, rastreabilidade total no `docker ps -a` e capacidade de filtragem de containers utilitários por labels.

### 2026-09-12 — Licença Open-Source Apache 2.0 e Desacoplamento Comunitário
- **Contexto:** Preparação do repositório para abertura pública internacional. A ausência de um arquivo `LICENSE` mantinha o projeto legalmente sob "todos os direitos reservados". Além disso, menções acopladas ao repositório pessoal `yegear1/homelab` no topo do README geravam confusão para usuários externos que rodam a stack de forma independente.
- **Decisão:**
  - Adotar formalmente a licença **Apache License 2.0** no arquivo `LICENSE`. A escolha protege autores contra litígios de garantia, concede direito de uso de patentes e permite ampla adoção e contribuição comunitária e comercial.
  - Substituir o aviso de coabitação privado do topo do README por uma orientação arquitetural neutra e genérica sobre coexistência de portas de rede no Docker (`9428`, `8686`, `5140/udp`, `9598`).
- **Consequências:** Clareza jurídica internacional e stack 100% autossuficiente para qualquer pessoa da comunidade open-source.

### 2026-09-12 — Governança de Recursos: Limite de 150 MB como Salvaguarda para Infraestrutura Limitada
- **Contexto:** Ao abrir o projeto para a comunidade, colaboradores humanos necessitam de diretrizes claras sobre como submeter melhorias e reportar falhas. A infraestrutura onde a stack opera atualmente é modesta e limitada (Mini PCs, nós Proxmox VE), exigindo contenção de consumo para não esgotar recursos da máquina.
- **Decisão:**
  - Esclarecer que o limite padrão de 150 MB de RAM (VictoriaLogs <= 80 MB, Vector <= 60 MB) não é um dogma inalterável, mas sim uma salvaguarda operacional intencional imposta para garantir que a stack não consuma recursos excessivos na infraestrutura limitada e dispute capacidade com outros serviços essenciais do host. Operadores com hardware mais robusto podem dimensionar os limites para cima conforme necessário.
  - Criar `CONTRIBUTING.md` fixando essa salvaguarda como baseline padrão de eficiência para Pull Requests comunitários, com suíte de testes obrigatórios (`test-pipeline.sh`, `audit-security.sh --strict`).
  - Criar `SECURITY.md` estabelecendo o fluxo de reporte responsável via GitHub Security Advisories privados.
  - Criar templates de issue em `.github/ISSUE_TEMPLATE/` (`bug_report.md` e `feature_request.md`) com avaliação de consumo de hardware.
- **Consequências:** Clareza arquitetural para a comunidade: proteção contra consumo excessivo de recursos em hardware limitado, combinada com flexibilidade de dimensionamento para quem possui maior capacidade.

### 2026-09-12 — Internacionalização da Documentação (README.md em Inglês e README.pt-br.md)
- **Contexto:** Com a transição do repositório para o ecossistema open-source global, a documentação principal na raiz precisa ser imediatamente acessível à comunidade internacional em língua inglesa. Ao mesmo tempo, operadores e desenvolvedores lusófonos necessitam de documentação completa e atualizada sem qualquer defasagem técnica.
- **Decisão:**
  - Adotar o `README.md` principal em Inglês técnico idiomático como padrão de entrada do repositório.
  - Portar e manter a documentação completa em Português no arquivo `README.pt-br.md`.
  - Incluir seletores bidirecionais de idioma no topo de ambos os documentos (`[English](README.md) | [Português (Brasil)](README.pt-br.md)`).
  - Estabelecer a regra de sincronização contínua: qualquer alteração de arquitetura, novos scripts ou flags de configuração deve ser refletida com 100% de paridade técnica em ambos os arquivos.
- **Consequências:** Alcance global para a comunidade open-source com preservação da conveniência para a comunidade lusófona, garantindo zero desatualização entre idiomas.

### 2026-09-06 — Issue GitHub como fila; TASK.md como bancada
- **Contexto:** Bugs percebidos em outro app (ex: caller usando a API do WhatsApp) não cabem no `TASK.md` da sessão atual nem como dump de log. Precisam sobreviver até um agente no repo dono investigar.
- **Decisão:** Skill `github-bug-issue` abre issue no GitHub do **repositório dono** com âncoras VictoriaLogs (sintoma, service, janela UTC, request_id/JID, consulta MCP sugerida). Evidência fica no VictoriaLogs; a issue é ponteiro. `.agent/TASK.md` só recebe o item quando o usuário pedir para executar o conserto.
- **Consequências:** Agentes futuros no `whatsapp-api` (ou no caller) abrem a issue, rodam `victorialogs-troubleshooting` e não dependem do chat original.

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

### 2026-09-06 — Fronteira de Repositório e Coabitação de Host com `yegear1/homelab`
- **Contexto:** O repositório de infraestrutura [`yegear1/homelab`](https://github.com/yegear1/homelab) provisiona os demais serviços do mesmo host Docker e declarava um serviço `victorialogs` próprio no seu `compose.yaml.example` e no seu catálogo canônico `SERVICES.md`. As duas declarações divergiam em imagem, limites de memória e caminho de storage, mas coincidiam em `container_name`, volume nomeado e porta `9428` — colisão garantida caso ambas subissem no host.
- **Decisão:** Manter esta stack como repositório independente (ela não é só deploy: entrega o servidor MCP e as SKILLs consumidos por outros repositórios da organização `ye-sandbox`) e desregistrá-la do `homelab`, que passou a reservar os recursos ocupados numa seção de serviços externos em vez de declará-los.
- **Alternativas consideradas:**
  - *Migrar a stack para `homelab/victorialogs/`:* daria fonte única de topologia do host, mas misturaria um artefato distribuível org-wide com infraestrutura pessoal de um único nó, e forçaria os limites de RAM daqui (80 MB / 60 MB) a conviver com o padrão de 512 MB-1 GB daquele repositório.
- **Consequências:** As quatro portas expostas por esta stack (`9428`, `5140/udp`, `8686`, `9598`), os volumes `victorialogs_data` e `vector_data` e os nomes de contêiner `victorialogs` e `vector` viraram contrato entre repositórios. **Qualquer alteração de porta, volume ou nome de contêiner aqui exige atualizar a seção 2 do `.agent/SERVICES.md` do `homelab` no mesmo ciclo**, sob pena de um agente daquele repositório realocar um recurso já ocupado. As redes permanecem isoladas (`logging-network` aqui, `monitoring_internal` lá): serviços do `homelab` que precisarem enviar logs devem usar a ingestão HTTP em `:8686` até que essa reconciliação seja decidida.

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

Aplicações **emitem** NDJSON (um objeto JSON por linha) em stdout ou POST `/logs`. O VictoriaLogs **não** é um dump JSON em disco. Dimensões de stream são só `host,container_name,service,app,env,stream`. Qualquer outro identificador (`userId`, `request_id`, JID, URL) permanece campo do evento.

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
- **MCP apontando para localhost a partir da workstation:**
  - *Armadilha:* O default do servidor MCP (`VICTORIALOGS_URL` → `http://127.0.0.1:9428`) só funciona se o VictoriaLogs estiver no mesmo host do cliente. No Cursor em WSL/Windows contra uma VM, `health_check` falha com conexão recusada.
  - *Mitigação:* Definir `VICTORIALOGS_URL` no `.cursor/mcp.json` local (gitignored) ou no `.env` local com o IP/hostname alcançável da VM. Não versionar esse valor.
- **Alta cardinalidade em VL-Stream-Fields:**
  - *Armadilha:* Promover `userId`, `request_id`, JID ou URL a stream field cria uma stream por valor único e degrada o Mini PC.
  - *Mitigação:* Manter o cabeçalho canônico `VL-Stream-Fields: "host,container_name,service,app,env,stream"`. IDs dinâmicos são campos do evento; o contrato está na skill `victorialogs-integration`.
- **NDJSON vs JSON pretty-printed:**
  - *Armadilha:* Array JSON ou objeto quebrado em várias linhas faz o `parse_json` do Vector falhar; o evento vira texto e o `level` cai na heurística.
  - *Mitigação:* Um objeto por linha (`json.dumps` / pino / slog JSONHandler), com `message` no topo. Pretty-printers (`pino-pretty`) ficam fora de produção.
- **Conscientização de Escopo de Aplicação em Agentes de IA:**
  - *Armadilha:* Modelos de IA tendem a realizar buscas globais sem especificar o container ou aplicação alvo (`service`), sobrecarregando o contexto com logs de múltiplos containers do homelab e dificultando o diagnóstico.
  - *Mitigação:* Adicionado o parâmetro `service` diretamente no schema de `query_logs` (injetando `_stream:{container_name="..."}`) e implementada uma nota proativa de SRE no rodapé (`💡 Dica de SRE`) sempre que uma busca global for executada, listando os containers detectados na amostra para incentivar a IA a afunilar na próxima chamada.
- **QEMU Rotational Default e Duplo Agendamento em VMs:**
  - *Armadilha:* O QEMU/KVM expõe dispositivos de bloco SCSI/SATA com `/sys/block/<dev>/queue/rotational == 1` por padrão caso a flag `ssd=1` não seja explicitamente declarada nas opções do disco no Proxmox. Diagnósticos ingênuos tratam o disco virtual como se fosse um HD mecânico com agulha, recomendando `mq-deadline` (gerando sobrecarga de duplo agendamento de I/O no guest e no host) e comandos `hdparm` que falham com ioctl error.
  - *Mitigação:* `scripts/tune-disk-host.sh` detecta virtualização e classifica dispositivos virtuais como `🖥️  Disco Virtualizado`, forçando recomendação de `none` (passthrough) e suprimindo seções de `hdparm`.
- **Precedência Alfabética de Regras Udev e Aplicação em Runtime:**
  - *Armadilha:* `systemd-udevd` processa arquivos em `/etc/udev/rules.d/` estritamente por ordem lexicográfica. Renomear uma regra (ex: de `60-hdd-scheduler.rules` para `60-disk-scheduler.rules`) sem remover o arquivo antigo faz com que `60-hdd...` execute por último e reverta silenciosamente as configurações de `60-disk...`. Além disso, `udevadm trigger` nem sempre reavalia discos de bloco já montados em tempo de execução sem `--action=change`.
  - *Mitigação:* O script remove preventivamente `60-hdd-scheduler.rules` antes de gravar a nova regra, usa `udevadm trigger --action=change --subsystem-match=block` e escreve diretamente nos nós `/sys/block/<dev>/queue/scheduler` dos discos ativos para efeito imediato.



