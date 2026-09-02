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

### 📌 Tarefa [XX.Y]: [Título curto e descritivo]

- **Descrição:** [O que precisa ser implementado, em 2-4 linhas. Detalhe o suficiente
  para o agente montar um plano, sem reescrever a especificação inteira aqui.]
- **Sistema(s) Envolvido(s):** [ex: `servico-api`, `servico-worker`, `frontend`]
- **Tipo de Ação:**
  - [ ] Somente leitura / Documentação
  - [ ] Escrita de código-fonte
- **Status:** [PRONTO PARA PLANEJAMENTO / EM PLANEJAMENTO / APROVADO / EM EXECUÇÃO]
  *(Fluxo: Definido como `PRONTO PARA PLANEJAMENTO` -> Agente assume como `EM PLANEJAMENTO` ao apresentar plano -> Usuário aprova -> Agente altera para `EM EXECUÇÃO` ao codificar)*

### Critérios de Aceite
- [ ] [Critério objetivo e verificável 1]
- [ ] [Critério objetivo e verificável 2]
- [ ] [Critério objetivo e verificável 3]

---

## Log de Tarefas Concluídas

> Uma linha por tarefa. Nada de "critérios verificados" repetidos aqui — isso já está
> no commit. Use `git log --oneline --grep="Tarefa XX"` ou `git show <hash>` para
> recuperar o detalhe quando precisar.

| Tarefa | Título | Commit(s) | Data |
|---|---|---|---|
| [00.1] | [Setup inicial da arquitetura e template do repositório] | [`0000000`] | [AAAA-MM-DD] |

> Quando esta tabela passar de ~15-20 linhas, mova as mais antigas para
> `.agent/ARCHIVE.md` (ou simplesmente apague — o Git já é a fonte da verdade).

---

## Backlog (Próximas, em ordem)

> Uma linha por item. Só vira uma seção detalhada com "Descrição" e "Critérios de
> Aceite" completos quando se tornar a Tarefa Ativa.

- [ ] **[01.1]** [Título curto da próxima tarefa] — `[sistema envolvido]`
- [ ] **[01.2]** [Título curto da tarefa subsequente] — `[sistema envolvido]`

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