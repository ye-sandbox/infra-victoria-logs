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

### 📌 Tarefa 06.0: Servidor MCP para VictoriaLogs (Integração Direta com Agentes de IA)

- **Descrição:** Desenvolver um servidor MCP (Model Context Protocol) leve para permitir que assistentes e agentes de IA (Claude Code, Antigravity, Cursor, Roo Code) consultem, filtrem e investiguem logs no VictoriaLogs nativamente através de ferramentas estruturadas (`query_logs`, `get_errors`, `top_containers`, `list_streams`), economizando tokens e eliminando comandos manuais de terminal.
- **Sistema(s) Envolvido(s):** `mcp`, `python / node`, `victorialogs`, `documentação`
- **Tipo de Ação:**
  - [x] Somente leitura / Documentação
  - [x] Escrita de código-fonte
- **Status:** EM EXECUÇÃO
  *(Fluxo: Definido como `PRONTO PARA PLANEJAMENTO` -> Agente assume como `EM PLANEJAMENTO` ao apresentar plano -> Usuário aprova -> Agente altera para `EM EXECUÇÃO` ao codificar)*

### Critérios de Aceite
- [x] Servidor MCP implementado com suporte a protocolo stdio para fácil conexão em clientes de IA.
- [x] Ferramentas MCP expostas: `query_logs` (LogsQL filtrado e paginado), `get_service_errors` (resumo de erros recentes) e `list_streams` (containers e hosts ativos).
- [x] Formatação compacta de respostas (Markdown e JSON limpo) para economia máxima de tokens de contexto.
- [x] Documentação de instalação e configuração nos clientes de IA no `README.md`.
- [x] Testes automatizados da integração MCP.

---

## Log de Tarefas Concluídas

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
| 00.1 | Setup inicial da arquitetura e template do repositório | `67ed939` | 2026-09-01 |
| 01.0 | Setup da Stack de Observabilidade Minimalista (VictoriaLogs + Vector) | `dba7608` | 2026-09-02 |
| 02.0 | Otimizações de Performance (Zstandard, Batching, Ulimits e Proteções de Busca) | `a6890e0` | 2026-09-02 |
| 03.0 | Implementação de Perfis Dinâmicos de Armazenamento (HDD vs SSD) | `ae1e305` | 2026-09-02 |
| 04.0 | Agregação Multilinha, Scripts (Backup/Smoke Test) e Autenticação Opcional | `4d05f68` | 2026-09-02 |
| 04.1 | Correção da tag padrão da imagem do VictoriaLogs para 'latest' | `f76b515` | 2026-09-03 |
| 01.1 | Validação de deploy em ambiente real no Proxmox e teste de ingestão de logs | `2f64d14` | 2026-09-03 |
| 05.0 | Dashboard CLI de Saúde e Telemetria do Homelab (VictoriaLogs /hits e /metrics) | `bc748f1` | 2026-09-03 |
| 06.0 | Servidor MCP Nativo para VictoriaLogs (Integração Direta com Agentes de IA) | `9657ddd` | 2026-09-03 |

---

## Backlog (Próximas, em ordem)

- [ ] **[07.0]** Coletor de Consumo de Recursos Docker (`docker stats` periódico para o Vector) — `scripts / cron / docker`

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