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

### 📌 Tarefa 17.0: Nova Ferramenta MCP `get_context_logs` (Logs de Contexto Vizinhos ao Erro)

- **Descrição:** Implementar uma 9ª ferramenta no servidor MCP (`mcp/server.py`): `get_context_logs(service, target_timestamp, window_seconds=10, limit=20)`. Ela busca automaticamente os eventos imediatamente anteriores e posteriores a um determinado timestamp/erro (incluindo logs de `info` e `debug`), permitindo que a IA entenda exatamente o que o usuário ou sistema estava fazendo nos segundos que antecederam um crash, sem a IA precisar calcular timestamps manuais com regex ou queries LogsQL complexas.
- **Sistema(s) Envolvido(s):** `mcp`, `skills`, `tests`
- **Tipo de Ação:**
  - [x] Somente leitura / Documentação
  - [x] Escrita de código-fonte
- **Status:** PRONTO PARA PLANEJAMENTO
  *(Fluxo: Definido como `PRONTO PARA PLANEJAMENTO` -> Agente assume como `EM PLANEJAMENTO` ao apresentar plano -> Usuário aprova -> Agente altera para `EM EXECUÇÃO` ao codificar)*

### Critérios de Aceite
- [ ] Ferramenta `get_context_logs` implementada no MCP com schema JSON-RPC documentado.
- [ ] Tratamento inteligente de janelas de tempo UTC em torno de `target_timestamp` (± `window_seconds`).
- [ ] Destaque visual no output Markdown do log alvo (o ponto central do incidente).
- [ ] Atualização do catálogo de ferramentas em `skills/victorialogs-troubleshooting/SKILL.md` e no `README.md`.
- [ ] Testes automatizados adicionados em `scripts/test-mcp.sh` e executados com 100% de sucesso.

---

## Log de Tarefas Concluídas

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
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

## Backlog (Próximas, em ordem)

- [ ] Suporte a alertas nativos via vmalert
- [ ] Enriquecimento de logs com GeoIP para tráfego web Nginx/Traefik

---

## Backlog Futuro / Ideias (não priorizadas)

- [ ] Suporte a alertas nativos via vmalert
- [ ] Enriquecimento de logs com GeoIP para tráfego web Nginx/Traefik

---

## Backlog Futuro / Ideias (não priorizadas)

> Itens de escopo maior ou ainda não maduros o suficiente para entrar no backlog
> ordenado. Uma linha cada — se crescer detalhe aqui, é sinal de que deveria virar
> uma issue no tracker do projeto (GitHub Issues, Linear, etc.) em vez de inchar
> este arquivo.

- [ ] [Ideia / feature futura 1]
- [ ] [Ideia / feature futura 2]

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