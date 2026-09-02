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
  - Migrar compressão no sink do Vector de `gzip` para `zstd` com `batch.max_bytes: 1048576` (1 MB) e `batch.timeout_secs: 1`.
  - Fixar `concurrency: 1` no Vector para evitar contenção de CPU no host.
  - Habilitar `-search.maxQueryDuration=30s` e `-search.maxConcurrentRequests=4` no VictoriaLogs para impedir travamentos por consultas mal formuladas.
  - Adicionar `ulimits: nofile: 65536` e `stop_grace_period: 30s` para assegurar flush atômico de índices em memória no desligamento.
- **Alternativas consideradas:**
  - *Manter gzip padrão sem batching:* Gera milhares de conexões HTTP e eleva uso de CPU do Go e Rust desnecessariamente.
- **Consequências:** Menor utilização de CPU por MB ingerido, menor latência de I/O em disco e imunidade contra OOM originado de queries longas.

---

## Contratos de Dados Vigentes

### Schema Canônico de Evento de Log

Todo log processado pelo Vector e ingerido no VictoriaLogs segue a seguinte estrutura canônica:

| Campo | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `timestamp` | `string (ISO8601)` | Timestamp da ocorrência do log | `2026-09-02T17:00:00.000Z` |
| `message` | `string` | Mensagem do log (texto principal) | `Server started on port 8080` |
| `level` | `string` | Nível do log (`error`, `warn`, `info`, `debug`) | `info` |
| `host` | `string` | Identificador do host/nó físico ou virtual | `mini-pc-proxmox` |
| `service` | `string` | Nome do serviço ou aplicação | `api-gateway` |
| `container_name`| `string` | Nome do container Docker ou fonte | `api-gateway` |
| `stream` | `string` | Canal de origem (`stdout`, `stderr`, `syslog`, `http`) | `stdout` |
| `structured` | `object (opcional)`| Objeto com chaves extras caso a mensagem seja JSON | `{"userId": 123}` |

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
