# Guia de Contribuição (Contributing Guide)

Agradecemos o seu interesse em contribuir para o **VictoriaLogs + Vector Homelab Observability Stack**! Este projeto é aberto à comunidade e mantido com padrões rigorosos de engenharia, eficiência e estabilidade para ambientes de homelab.

---

## 🛑 Princípio Fundamental: Salvaguarda de Memória (Limite Padrão de 150 MB)

> [!IMPORTANT]
> **Atenção:** Este projeto foi concebido para rodar em **infraestrutura local e limitada** (Mini PCs, Intel NUCs, nós Proxmox VE, servidores caseiros com recursos modestos).
> 
> Para **garantir que a stack não consuma recursos excessivos** nem dispute capacidade com outras aplicações do host, foi imposto um **teto padrão de 150 MB de RAM total**:
> - **VictoriaLogs:** `<= 80 MB` (`deploy.resources.limits.memory: 80M` e `-memory.allowedPercent=60`)
> - **Vector:** `<= 60 MB` (`deploy.resources.limits.memory: 60M`)
> - **Total Combinado:** `<= 140 MB` (operando com folga confortável dentro da salvaguarda de 150 MB)
> 
> Esse limite não é um dogma inalterável, mas uma salvaguarda intencional imposta para o dimensionamento seguro em hardware modesto. Embora operadores individuais possam ajustar e aumentar os limites no `docker-compose.yml` e `.env` caso disponham de mais recursos no seu host (ex: elevando VictoriaLogs para `120M` em caso de alto tráfego), Pull Requests submetidos à comunidade devem respeitar essa salvaguarda por padrão para evitar consumo excessivo de recursos e preservar o propósito em infraestruturas restritas.

---

## 🚀 Como Começar (Setup Local)

### 1. Clonar e Configurar
```bash
git clone https://github.com/ye-sandbox/infra-victoria-logs.git
cd infra-victoria-logs

# Copiar variáveis de ambiente de exemplo
cp .env.example .env
chmod 600 .env

# Subir a stack local
docker compose up -d
```

### 2. Validar Execução
```bash
# Smoke test imediato de ingestão e LogsQL
./scripts/test-pipeline.sh

# Auditoria de postura de segurança e permissões
./scripts/audit-security.sh
```

---

## 🛠️ Suíte de Validações Obrigatórias

Antes de abrir um Pull Request, certifique-se de executar e obter 100% de aprovação em todos os testes abaixo:

1. **Sintaxe do Docker Compose:**
   ```bash
   docker compose config --quiet
   ```
2. **Validação das Configurações do Vector (VRL e YAML):**
   ```bash
   docker run --rm --name vector-config-validator \
     -v $(pwd)/vector/vector.yaml:/etc/vector/vector.yaml:ro \
     timberio/vector:0.45.0-alpine validate --config-yaml /etc/vector/vector.yaml
   ```
3. **Validação de Sintaxe de Todos os Scripts Bash:**
   ```bash
   bash -n scripts/*.sh
   ```
4. **Auditoria Estrita de Segurança e Permissões:**
   ```bash
   ./scripts/audit-security.sh --strict
   ```
5. **Smoke Test Ponta a Ponta:**
   ```bash
   ./scripts/test-pipeline.sh
   ```

---

## 📝 Padrões de Commit e Mensagens

Seguimos a convenção [Conventional Commits](https://www.conventionalcommits.org/) estritamente em **inglês**:

- `feat(storage): add partition cleanup policy`
- `fix(vector): prevent multiline aggregation race condition`
- `docs(readme): add troubleshooting section for proxmox`
- `chore(deps): bump victoria-logs to latest stable`
- `refactor(mcp): optimize JSON projection in query_logs`

---

## 🔄 Fluxo de Pull Requests

1. Crie uma branch a partir da `main`:
   ```bash
   git checkout -b feat/sua-melhoria-ou-correcao
   ```
2. Faça commits atômicos e bem explicados.
3. Se você adicionar novos scripts ou parâmetros ao `.env.example`, **atualize imediatamente o `README.md`** e inclua uma entrada em `CHANGELOG.md` na seção `[Unreleased]`.
4. Abra o Pull Request descrevendo a motivação, o impacto no consumo de recursos (RAM/CPU) e como foi validado no seu ambiente.

Dúvidas ou sugestões podem ser discutidas abrindo uma **Issue** no repositório. Obrigado por colaborar com a comunidade!
