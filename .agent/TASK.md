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

### 📌 Tarefa 01.0: Setup da Stack de Observabilidade Minimalista (VictoriaLogs + Vector)

- **Descrição:** Criação da estrutura completa pronta para produção de uma stack leve de centralização de logs para homelabs (Mini PC no Proxmox com Docker). Composta por VictoriaLogs e Vector, com foco em footprint mínimo (< 150 MB RAM total) e facilidade de consulta para desenvolvedores e agentes de IA via LogsQL.
- **Sistema(s) Envolvido(s):** `docker-compose`, `vector`, `documentação / .agent`
- **Tipo de Ação:**
  - [x] Somente leitura / Documentação
  - [x] Escrita de código-fonte
- **Status:** EM EXECUÇÃO
  *(Fluxo: Definido como `PRONTO PARA PLANEJAMENTO` -> Agente assume como `EM PLANEJAMENTO` ao apresentar plano -> Usuário aprova -> Agente altera para `EM EXECUÇÃO` ao codificar)*

### Critérios de Aceite
- [x] `docker-compose.yml` funcional com VictoriaLogs e Vector configurados com limits rígidos de memória (< 150 MB somados).
- [x] `vector/vector.yaml` configurado para capturar logs do Docker via socket, enriquecer metadados, tratar loops e enviar via HTTP/jsonline para o VictoriaLogs com `VL-Stream-Fields`.
- [x] `.env.example` com todas as variáveis (portas, retenção, limites de memória, tags de imagem).
- [x] `.gitignore` atualizado para ignorar dados locais e volumes de desenvolvimento.
- [x] `README.md` completo com guia de deploy, arquitetura, consultas LogsQL (exemplos para agentes de IA) e integração com Proxmox.
- [x] `AGENTS.md` e `.agent/NOTES.md` devidamente preenchidos com o contexto real de DevOps e decisões de arquitetura da stack.

---

## Log de Tarefas Concluídas

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
| 00.1 | Setup inicial da arquitetura e template do repositório | `67ed939` | 2026-09-01 |
| 01.0 | Setup da Stack de Observabilidade Minimalista (VictoriaLogs + Vector) | `dba7608` | 2026-09-02 |

---

## Backlog (Próximas, em ordem)

- [ ] **[01.1]** Validação de deploy em ambiente real no Proxmox e teste de ingestão de logs — `docker-compose / vector`
- [ ] **[01.2]** Automação de rotação de logs e script de backup de volumes — `scripts / devops`

---

## Backlog Futuro / Ideias (não priorizadas)

- [ ] Painel Grafana ou Dashboard leve alternativo para métricas combinadas (se VictoriaMetrics for adicionado no futuro)
- [ ] Agente MCP dedicado para consulta direta de VictoriaLogs por assistentes de IA

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