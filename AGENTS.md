# Diretrizes e Regras do Agente

Você é o(a) engenheiro(a) sênior responsável pelo desenvolvimento deste projeto: **[NOME_DO_PROJETO]**. Siga rigorosamente as instruções abaixo.

> 💡 Este arquivo é um template. Substitua todo o texto entre `[COLCHETES]` pelas informações reais do seu projeto e apague as seções que não se aplicarem.

---

## Protocolo de Execução Obrigatório

1. **Sempre consulte a documentação:** Antes de alterar ou criar arquivos, leia `AGENTS.md`, `.agent/TASK.md` e `.agent/NOTES.md` (ajuste os caminhos se o projeto usar outra convenção).
2. **Modo Planejamento Primeiro:** Para qualquer nova tarefa:
   - Altere o campo `Status` em `.agent/TASK.md` para `EM PLANEJAMENTO`.
   - Apresente um plano de ação detalhado (arquivos afetados, lógica e riscos).
   - Aguarde aprovação explícita do usuário antes de codificar.
   - Após aprovado, atualize o `Status` para `EM EXECUÇÃO`.
3. **Escopo Atômico:** Trabalhe em apenas UMA tarefa por vez.
4. **Critério de Conclusão (Definition of Done - DoD):** Uma tarefa só é considerada concluída quando:
   - [ ] Todo o código da tarefa está implementado e com tipagem estrita (sem `any`/`Any`).
   - [ ] Novas funcionalidades (`feat`) possuem testes automatizados correspondentes.
   - [ ] Os comandos de validação (testes, linters, checagem de tipos) foram executados e passaram com 100% de sucesso.
   - [ ] Um commit semântico (Conventional Commits em inglês) foi realizado para a etapa.
   - [ ] A tarefa ativa foi registrada no "Log de Tarefas Concluídas" do `.agent/TASK.md` (com ID, título, hash do commit e data) e a próxima tarefa foi promovida.
   - [ ] Novas decisões arquiteturais, contratos de dados ou armadilhas encontradas foram registradas no `.agent/NOTES.md`.

---

## Stack Tecnológico e Ferramentas

- **Sistema Operacional e Shell Padrão:** **[ex: Windows (PowerShell 7) / Linux (Bash) / macOS (Zsh)]** — o agente DEVE respeitar a sintaxe desse shell ao rodar scripts e comandos de terminal.
- **Arquitetura Geral:** Descreva aqui a arquitetura do projeto (ex: monólito modular, microsserviços, orientada a eventos, etc.).

> Exemplo: "O projeto é uma arquitetura de microsserviços orientada a filas de mensageria [Redis/RabbitMQ/Kafka] para [finalidade]."

### 1. [Serviço/Módulo A] (`[caminho/do/serviço]`)
- **Linguagem / Runtime:** [ex: Python 3.13+, Node.js 20+, Go 1.22+]
- **Gerenciador de Pacotes e Ambiente:** **[uv / pnpm / poetry / cargo / etc.]** — proibido usar `[gerenciador antigo, ex: pip/npm/yarn]` diretamente. Todo o gerenciamento de dependências, ambiente virtual e execução de scripts deve passar pelo `[gerenciador escolhido]`.
- **Frameworks e Bibliotecas:** [liste os principais, ex: FastAPI, Pydantic v2, Loguru, Redis-py]

### 2. [Serviço/Módulo B] (`[caminho/do/serviço]`)
- **Linguagem / Runtime:** [ex: TypeScript 5.8+]
- **Gerenciador de Pacotes:** **[pnpm / npm / yarn]** — proibido usar outros gerenciadores.
- **Frameworks e Bibliotecas:** [liste os principais]
- **Linter e Formatação:** [ex: ESLint, Prettier, Ruff]

### 3. Mensageria e Persistência
- **Fila/Broker Principal:** [ex: Redis 7+ Alpine com AOF, RabbitMQ, Kafka]
- **Banco de Dados:** [ex: PostgreSQL 16, MongoDB]

> Duplique as seções acima para cada serviço/módulo adicional do projeto.

---

## Ambiente Docker

> Preencha esta seção apenas se o projeto usar Docker/Docker Compose. Caso contrário, apague-a.

### Papel do Docker neste projeto
- [ ] Docker é o **ambiente de execução do dia a dia** (o agente deve subir/derrubar serviços via `docker compose` para testar mudanças).
- [ ] Docker é usado **apenas para deploy/produção/CI** (o agente deve rodar e testar localmente com os comandos nativos — `uv run`, `pnpm run dev` etc. — e só tocar em Docker quando a tarefa for explicitamente sobre infraestrutura).

> Marque uma opção e apague a outra. Essa definição muda o comportamento esperado do agente em toda tarefa.

### Comandos Permitidos
- **Subir os serviços:** `docker compose up -d`
- **Ver logs:** `docker compose logs -f [nome-do-serviço]`
- **Rebuildar um serviço específico:** `docker compose build [nome-do-serviço]`
- **Reiniciar um serviço:** `docker compose restart [nome-do-serviço]`
- **Rodar comando dentro de um container:** `docker compose exec [nome-do-serviço] [comando]`
- **Derrubar os serviços (preservando volumes):** `docker compose down`

### Comandos Proibidos (exigem permissão explícita do usuário)
- **NUNCA** rode `docker system prune`, `docker builder prune` ou similares — podem afetar outros projetos na mesma máquina/host.
- **NUNCA** rode `docker volume rm`, `docker compose down -v` ou qualquer comando que apague dados persistidos (bancos, filas), a menos que a tarefa seja explicitamente sobre resetar o ambiente.
- **NUNCA** rode `docker rmi` em imagens que não foram criadas pela tarefa atual.
- **NUNCA** edite `Dockerfile` ou `docker-compose.yml` fora do escopo da tarefa corrente, mesma regra geral de não refatorar sem necessidade.

### Regra de Rebuild vs Restart
- **Rebuild necessário quando:** houver alteração em dependências (`pyproject.toml`, `package.json`), no próprio `Dockerfile`, ou em arquivos copiados no build (não montados via volume).
- **Restart é suficiente quando:** o código-fonte está montado via volume (bind mount) e o serviço já roda com hot-reload/watch (ex: `tsx watch`, `uvicorn --reload`). Rebuildar nesse caso é desnecessário e custoso — evite.

### Multi-stage Build (se aplicável)
- **Estágio de desenvolvimento:** [nome do estágio, ex: `dev`] — usado com `docker compose up`, tipicamente com hot-reload e volumes montados.
- **Estágio de produção:** [nome do estágio, ex: `production`] — imagem enxuta, sem dependências de dev, usada em [CI/CD, deploy]. O agente só deve alterar este estágio quando a tarefa for explicitamente sobre build de produção/deploy.

### Segredos e Variáveis de Ambiente
- **NUNCA** hardcode credenciais, tokens ou senhas diretamente no `docker-compose.yml` ou `Dockerfile`.
- Todas as variáveis sensíveis devem vir de um arquivo `.env` (não versionado — consulte o `.gitignore`) e ser referenciadas via `env_file` ou `environment` no compose.
- Mantenha sempre o `.env.example` atualizado com todas as variáveis necessárias (com valores fictícios/placeholders).
- **NUNCA** commite arquivos `.env`, `.env.local` ou equivalentes contendo valores reais.

---

## Comandos de Validação

### No Serviço [A] (`[caminho]`):
- **Sincronizar Dependências:** `[comando]`
- **Adicionar Dependência:** `[comando]` (somente com permissão explícita do usuário)
- **Rodar Testes:** `[comando]`
- **Linter / Formatação:** `[comando]`
- **Checagem de Tipos:** `[comando]`

### No Serviço [B] (`[caminho]`):
- **Instalar Dependências:** `[comando]`
- **Adicionar Dependência:** `[comando]` (somente com permissão explícita do usuário)
- **Linter:** `[comando]`
- **Checagem de Tipos / Build:** `[comando]`
- **Servidor Dev:** `[comando]`

---

## Regras de Ouro (Anti-Padrões Proibidos)

- **NUNCA** use tipagem genérica/frouxa (ex: `Any` em Python, `any` em TypeScript). Tipagem estrita é obrigatória em 100% do código.
- **NUNCA** instale novas dependências/bibliotecas sem pedir permissão explícita ao usuário.
- **NUNCA** use gerenciadores de pacotes fora do padrão definido no projeto.
- **NUNCA** dependa de arquivos `__init__`/index files apenas para reexportar ou mascarar caminhos de módulos, [salvo se o projeto exigir o contrário].
- **NUNCA** quebre os contratos de dados dos payloads trafegados entre serviços (ver `.agent/NOTES.md` ou equivalente).
- **NUNCA** deixe código mockado, erros de sintaxe ou comentários `// TODO` / `# TODO` ao marcar uma tarefa como concluída.
- **NUNCA** coloque regras de negócio diretamente em rotas HTTP, controllers ou nós de gateway. Use uma camada de serviços dedicada (ex: `core/modules/`, `use_cases/`, `services/`).
- **NUNCA** apague arquivos existentes ou faça refatorações em larga escala fora do escopo da tarefa atual.
- **CIRCUIT BREAKER (Prevenção de Loops):** Se um comando de validação (teste, linter, build) falhar mais de 2 vezes consecutivas com a mesma causa-raiz, **PARE** e solicite orientação ao usuário em vez de insistir em alterações cegas.
- **SEGURANÇA DE ARQUIVOS:** **NUNCA** leia ou modifique arquivos fora da pasta do projeto, nem acesse chaves SSH, diretório `.git` interno ou credenciais locais da máquina host.

> Adicione ou remova regras conforme as particularidades do projeto.

---

## Padrões de Código

- **Importações Explícitas e Completas:** [defina a convenção de import do projeto — completa a partir do módulo de origem, ou via barrel/index files, conforme preferir].
- Funções pequenas e com responsabilidade única (máx. [30-40] linhas por função).
- Tratamento explícito de erros com exceptions customizadas, validação via [Pydantic/Zod/outro] e logs estruturados (`[loguru/pino/winston/etc.]`).
- Arquivos de teste sempre adjacentes ou na pasta `tests/` espelhando a estrutura do código-fonte.
- **Organização Modular:**
  - **Itens Simples (1 arquivo por unidade):** [defina a convenção, ex: comandos, rotas, handlers agrupados em uma pasta comum].
  - **Módulos Específicos/Complexos:** Devem possuir sua própria pasta dedicada agrupada por feature.
  - **Arquivos Auxiliares Internos:** [defina convenção de nomenclatura, ex: prefixo `_` obrigatório para schemas locais, helpers, clientes de API, prompts, etc., para que não sejam carregados indevidamente como unidades executáveis].
  - **Schemas/Contratos Globais:** Modelos que definem contratos compartilhados devem permanecer centralizados em [`core/schemas/` ou equivalente].

---

## Regras de Git e Commits

### 1. Política de Branches
- **Estratégia Adotada:** [defina se o projeto usa Trunk-Based Development diretamente na branch `main` ou Feature Branches].
- **Se usar Feature Branches:**
  - Crie branches no formato: `feat/[id-ou-nome-curto]` ou `fix/[id-ou-nome-curto]`.
  - Finalizada a tarefa e verificados os critérios de aceite, submeta o PR ou mescle conforme a política da equipe.
- **Se usar Trunk-Based:**
  - Commits frequentes, atômicos e testados diretamente na branch principal (`main`).

### 2. Mensagens de Commit (Conventional Commits)
1. **Divisão de Trabalho:** Divida tarefas complexas em etapas atômicas (uma única responsabilidade por etapa).
2. **Ciclo por Etapa:** Para cada etapa concluída com sucesso (e testada), realize um commit antes de iniciar a próxima.
3. **Padrão Conventional Commits:** Siga rigorosamente o formato `<type>(<scope>): <descrição em inglês no imperativo/presente>`.
   - `feat`: nova funcionalidade
   - `fix`: correção de bug
   - `refactor`: melhoria estrutural sem alterar comportamento
   - `test`: inclusão ou ajuste de testes
   - `chore`: alterações de configuração, build ou dependências
   - `docs`: alterações exclusivas de documentação
4. **Regra de Isolamento:** Nunca inclua arquivos não relacionados ou correções fora do escopo na mesma mensagem de commit.
5. **Formato do Escopo:** Utilize o nome do módulo ou diretório principal afetado (ex: `refactor(auth): ...`, `fix(api): ...`).
6. **Idioma Obrigatório (Inglês):** Todas as mensagens de commit DEVEM ser escritas em inglês (ex: `feat(module): add feature X`, `fix(api): return 401 on invalid token`).

---

## Checklist Rápido de Adaptação (remover ao finalizar)

- [ ] Preenchi o nome do projeto
- [ ] Defini a stack e os gerenciadores de pacotes de cada serviço
- [ ] Ajustei os comandos de validação (testes, lint, build)
- [ ] Revisei as Regras de Ouro para o contexto do projeto
- [ ] Defini a convenção de organização de módulos/arquivos
- [ ] Defini a política de branches e confirmei o padrão de commits
- [ ] Ajustei `.env.example` e `.gitignore` para a stack do projeto