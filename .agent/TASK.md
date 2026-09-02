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

### 📌 Tarefa 03.0: Implementação de Perfis de Armazenamento Dinâmicos (HDD vs SSD)

- **Descrição:** Implementar suporte nativo a perfis de armazenamento via variável `STORAGE_PROFILE` (hdd / ssd). O modo HDD foca em poupar IOPS com buffer em memória RAM, escrita sequencial (2MB/2s), descarte de healthchecks e menos buscas paralelas. O modo SSD foca em menor latência de busca e persistência em buffer de disco.
- **Sistema(s) Envolvido(s):** `vector`, `docker-compose`, `.env.example`, `documentação`
- **Tipo de Ação:**
  - [x] Somente leitura / Documentação
  - [x] Escrita de código-fonte
- **Status:** EM EXECUÇÃO
  *(Fluxo: Definido como `PRONTO PARA PLANEJAMENTO` -> Agente assume como `EM PLANEJAMENTO` ao apresentar plano -> Usuário aprova -> Agente altera para `EM EXECUÇÃO` ao codificar)*

### Critérios de Aceite
- [x] `vector/vector.hdd.yaml` criado e otimizado para HD mecânico (buffer em memória, lotes 2MB/2s, descarte de pings).
- [x] `vector/vector.ssd.yaml` criado e otimizado para SSD (buffer em disco de 256MB, lotes 1MB/1s).
- [x] `docker-compose.yml` parametrizado com `./vector/vector.${STORAGE_PROFILE:-hdd}.yaml` e variáveis de busca.
- [x] `.env.example` atualizado com a documentação clara dos perfis `STORAGE_PROFILE=hdd` e `STORAGE_PROFILE=ssd`.
- [x] `README.md` e `.agent/NOTES.md` atualizados com o guia de escolha e justificativa arquitetural dos perfis.
- [x] Validação de sintaxe dos arquivos YAML aprovada com 100% de sucesso.

---

## Log de Tarefas Concluídas

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
| 00.1 | Setup inicial da arquitetura e template do repositório | `67ed939` | 2026-09-01 |
| 01.0 | Setup da Stack de Observabilidade Minimalista (VictoriaLogs + Vector) | `dba7608` | 2026-09-02 |
| 02.0 | Otimizações de Performance (Zstandard, Batching, Ulimits e Proteções de Busca) | `a6890e0` | 2026-09-02 |

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