# TASK.md — Tarefa Atual e Roadmap do Projeto

> Define O QUE precisa ser feito. Reescrito/atualizado no início de cada nova tarefa.
> Se o pedido do usuário na conversa conflitar com este arquivo, o pedido do usuário
> tem precedência — mas o agente deve reportar a divergência antes de agir.
>
> **Regra de ouro deste arquivo:** ele guarda O QUE FAZER, não O QUE JÁ FOI FEITO.
> Detalhes de implementação de tarefas concluídas vivem no `git log`, não aqui.
> Ver seção "Como manter este arquivo enxuto" no final.

---

## Tarefa Ativa

### 📌 Nenhuma tarefa ativa no momento (Aguardando definição do usuário ou backlog)

- **Descrição:** Tarefa 46.0 concluída com sucesso. Aguardando autorização para iniciar a próxima tarefa do backlog (47.0).
- **Sistema(s) Envolvido(s):** N/A
- **Tipo de Ação:** N/A
- **Status:** AGUARDANDO TAREFA

---

## Backlog (Próximas, em ordem)

- [ ] **47.0** — Parâmetro `max_buckets` e Aviso de Truncamento em `get_log_hits` no Servidor MCP
- [ ] **48.0** — Parâmetro `service` em `field_names` para Escopo por Aplicação no Servidor MCP
- [ ] **49.0** — Hardening de Containers: `read_only: true` + `tmpfs` para VictoriaLogs e Vector
- [ ] **50.0** — Correção do Healthcheck HTTP Real do vmalert (`wget /health` na porta 8880)
- [ ] **51.0** — Adição de `no-new-privileges: true` em Todos os Containers

---

## Log de Tarefas Concluídas

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
| 46.0 | Clamping Preventivo de 8 KB no `remap_syslog` (Paridade com Docker e HTTP) | `70b05ae` | 2026-09-21 |
| 45.0 | Alinhamento do Fallback de Retenção Padrão (`30d` → `1y`) no `docker-compose.yml` | `b352a3f` | 2026-09-21 |
| 43.0 | Governança de Orçamento de Tokens nas SKILLs e Playbook de SRE | `45b6bc0` | 2026-09-21 |
| 42.0 | Economia de Tokens no Servidor MCP (Colapso Consecutivo, Limpeza ANSI e Projeção `fields`) | `cc78e9f` | 2026-09-21 |
| 41.0 | Otimização de Ingestão no Vector (Descarte de Scrapes /metrics e Teto Preventivo de Tamanho) | `9692f62` | 2026-09-21 |
| 40.0 | Supressão Padrão de Ruído de Telemetria (docker-stats e cadvisor) em Buscas Globais no MCP | `913d0cb` | 2026-09-21 |
| 39.0 | Tradução de AGENTS.md, Servidor MCP e Guias Correlacionados para Inglês Técnico | `6da715e` | 2026-09-15 |
| 38.0 | Tradução 1:1 das SKILLs para Inglês com Foco em Economia de Tokens e Entendimento de Agentes | `093602d` | 2026-09-15 |
| 37.0 | Alinhamento das Diretrizes de MCP no `AGENTS.md` e Sincronização da SKILL | `57076a8` | 2026-09-13 |
| 36.1 | Correção de Conflito Udev e Aplicação Imediata de Scheduler em `tune-disk-host.sh` | `64e4ca0` | 2026-09-12 |
| 36.0 | Refatoração de `tune-disk-host.sh` com Consciência de Ambientes Virtualizados (VMs / QEMU / KVM / Proxmox) | `6414e65` | 2026-09-12 |
| 35.0 | Calibração da Governança de Recursos: Limite de 150 MB como Salvaguarda para Infraestrutura Limitada | `d6a5d25` | 2026-09-12 |
| 34.0 | Validação de Conformidade Open-Source e Smoke Test Final da Release | `96dbe6a` | 2026-09-12 |
| 33.0 | Internacionalização da Documentação (`README.md` em Inglês como Padrão e `README.pt-br.md`) | `c59c793` | 2026-09-12 |
| 32.0 | Governança de Comunidade Open-Source (`CONTRIBUTING.md`, `SECURITY.md` e Templates de Issues) | `f705cde` | 2026-09-12 |
| 31.0 | Licença Open-Source (LICENSE Apache 2.0) e Desacoplamento de Referências Pessoais do Host | `28c9ccf` | 2026-09-12 |
| 30.0 | Padronização e Nomeação Determinística de Containers Efêmeros nos Scripts de Manutenção | `277834c` | 2026-09-11 |
| 29.0 | Guia Consolidado de Hardening e Boas Práticas Operacionais do Host Proxmox (`docs/proxmox-hardening.md`) | `b6d8fb3` | 2026-09-11 |
| 28.0 | Script de Auditoria de Segurança e Permissões de Arquivos no Host (`scripts/audit-security.sh`) | `3920bfb` | 2026-09-11 |
| 27.0 | Rotina de Teste Automatizado de Integridade e Snapshot Diário (`run-maintenance-pipeline.sh`) | `5381a9e` | 2026-09-11 |
| 26.0 | Dashboard Grafana Pré-construído (`dashboards/grafana-victorialogs.json`) | `4693fc7` | 2026-09-11 |
| 25.0 | Auditoria e Alerta Periódico de Capacidade de Partições por Cron (`check-disk-growth.sh`) | `e31be5c` | 2026-09-10 |
| 24.0 | Gestão, Auditoria e Purga Emergencial de Partições Físicas (Retenção de 1 Ano) | `b2c6538` | 2026-09-10 |
| 23.0 | Painéis de Consulta LogsQL Salvos para Terminal (`scripts/logsql-queries.sh`) | `d9290d5` | 2026-09-10 |
| 22.0 | Enriquecimento Opcional de Logs com GeoIP para Tráfego Web (`vector.geoip.yaml`) | `6e2dae1` | 2026-09-10 |
| 21.0 | Suporte a Alertas Nativos via vmalert Conectado ao VictoriaLogs | `d44393b` | 2026-09-10 |
| 20.0 | Templates de Logging Canônico Plug-and-Play (Loguru, Stdlib, Pino, Slog) | `5c2b1c6` | 2026-09-10 |
| 19.0 | Serviço Daemon e Automação no Host dos Coletores de Recursos e Eventos (`install-host-collectors.sh`) | `addaa90` | 2026-09-10 |
| 18.0 | Script de Instalação e Sincronização Global de SKILLs (`scripts/install-agent-skills.sh`) | `a801909` | 2026-09-10 |
| 17.0 | Nova Ferramenta MCP `get_context_logs` (Logs de Contexto Vizinhos ao Erro) | `d6f32db` | 2026-09-10 |
| 16.0 | Promoção de Campos Canônicos de Correlação no VRL (`trace_id`, `request_id`, `http_status`) | `1134593` | 2026-09-10 |
| 15.0 | Captura de Eventos do Daemon Docker (Crashes, Restarts, OOMKilled) | `10d3ffd` | 2026-09-10 |
| 09.0 | Coletor de Consumo de Recursos Docker (`docker stats` periódico para o Vector) | `6d74351` | 2026-09-10 |
| 14.0 | Multiline Vector: `continue_through` para não colar NDJSON ([#1](https://github.com/ye-sandbox/infra-victoria-logs/issues/1)) | `a84aa11` | 2026-09-07 |
| 00.1 | Setup inicial da arquitetura e template do repositório | `67ed939` | 2026-09-01 |
| 01.0 | Setup da Stack de Observabilidade Minimalista (VictoriaLogs + Vector) | `dba7608` | 2026-09-02 |
| 02.0 | Otimizações de Performance (Zstandard, Batching, Ulimits e Proteções de Busca) | `a6890e0` | 2026-09-02 |
| 03.0 | Implementação de Perfis Dinâmicos de Armazenamento (HDD vs SSD) | `ae1e305` | 2026-09-02 |
| 04.0 | Agregação Multilinha, Scripts (Backup/Smoke Test) e Autenticação Opcional | `4d05f68` | 2026-09-02 |
| 04.1 | Correção da tag padrão da imagem do VictoriaLogs para 'latest' | `f76b515` | 2026-09-03 |
| 01.1 | Validação de deploy em ambiente real no Proxmox e teste de ingestão de logs | `2f64d14` | 2026-09-03 |
| 05.0 | Telemetria e Monitoramento da Stack (Dashboard CLI e Vector Prometheus Exporter) | `bc748f1`, `a868811` | 2026-09-03 |
| 06.0 | Servidor MCP Nativo para VictoriaLogs (Integração Direta com Agentes de IA) | `9657ddd` | 2026-09-03 |
| 07.0 | Criação da Skill 'victorialogs-integration' e Setup do MCP Oficial (Go) | `836634a`, `f3c134e` | 2026-09-03 |
| 08.0 | Criação da Skill 'victorialogs-troubleshooting' (Playbook de SRE) e Governança | `c55176f`, `6abe39c` | 2026-09-03 |
| 10.0 | Otimização Extrema do MCP Python (Deduplicação, Keep, Docs, 8 Tools) | `8a86ef8` | 2026-09-04 |
| 10.1 | Dicas Contextuais e Tratamento Defensivo de Sintaxe LogsQL no MCP | `199eb56` | 2026-09-04 |
| 10.2 | Conscientização e Escopo de Aplicação (service) no MCP e SKILLs | `6c2a6b3` | 2026-09-04 |
| 11.0 | Otimização de Lote no Vector para HD Único (batch 15s) | `dd22816` | 2026-09-05 |
| 11.1 | Calibração de Flush em Memória do VictoriaLogs (15s) | `11205b5` | 2026-09-05 |
| 11.2 | Docker Daemon em Modo Non-Blocking no Host | `be9870e` | 2026-09-05 |
| 11.3 | Otimização do Host (noatime, mq-deadline e APM) | `c8bc25d` | 2026-09-05 |
| 12.0 | Contrato JSON na skill de integração e descoberta Cursor | `3a69f85` | 2026-09-06 |
| 13.0 | Skill github-bug-issue (fila GitHub + ponteiro VictoriaLogs) | `62e9535` | 2026-09-06 |

---

## Backlog Futuro / Ideias (não priorizadas)

> Itens de escopo maior ou ainda não maduros o suficiente para entrar no backlog
> ordenado. Uma linha cada — se crescer detalhe aqui, é sinal de que deveria virar
> uma issue no tracker do projeto (GitHub Issues, Linear, etc.) em vez de inchar
> este arquivo.

- [ ] [Ideia / feature futura a ser definida]

---

## Como manter este arquivo enxuto

1. **Detalhe vive na tarefa ativa, não no histórico.** Assim que uma tarefa é concluída,
   reduza-a a uma linha na tabela de log (título + hash do commit) e promova a próxima
   do backlog para "Tarefa Ativa" com o detalhe completo.
2. **Backlog é lista de títulos, não de specs.** Escreva a especificação completa só
   quando o item vira a tarefa ativa — evita manter duas fontes de verdade desatualizadas.
3. **Prefira issues/tracker externo para escopo grande.** Se uma ideia do "Backlog Futuro"
   cresce e ganha critérios de aceite, sub-tarefas etc., mova para o sistema de issues do
   projeto e deixe aqui só um link/referência.
4. **Arquive, não acumule.** Ao ultrapassar ~15-20 linhas no log de concluídas, corte o
   mais antigo para `.agent/ARCHIVE.md` ou remova — o `git log` já preserva tudo.
5. **Nunca duplique o commit message aqui.** Se a mensagem de commit já segue Conventional
   Commits (`feat(module): ...`), ela já documenta o que mudou. Este arquivo só precisa
   apontar pra ela.
6. **Instrua o agente a consultar o Git quando precisar de contexto histórico**, em vez de
   reler um TASK.md longo. Ex: "para entender decisões passadas, rode `git log --oneline`
   ou consulte `.agent/NOTES.md` para decisões arquiteturais que não são óbvias a partir
   do diff."