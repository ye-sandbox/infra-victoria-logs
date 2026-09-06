---
name: github-bug-issue
description: Opens a GitHub issue to park a bug for a later agent, with VictoriaLogs evidence pointers instead of log dumps. Use when the user notices a problem in another app (WhatsApp API, caller service, homelab), wants to annotate context for later, or asks to file/create a GitHub issue rather than fix it now. Do not use TASK.md as a bug queue.
---

# Capturar bug para depois (GitHub Issue + VictoriaLogs)

Quando o usuário **percebe um problema** (em outro app, na API do WhatsApp, num caller) e quer **anotar o contexto** para um agente analisar depois: abra uma **issue no GitHub do repositório dono**. Não use `.agent/TASK.md` como fila.

| Artefato | Papel |
|---|---|
| **GitHub Issue** | Caixa de entrada. Persistente, numerada, linkável a PR. |
| **VictoriaLogs** | Armário de evidência. A issue aponta; o MCP reconstruí o incidente. |
| **`.agent/TASK.md`** | Bancada. Uma tarefa ativa. Só entra quando o usuário for **executar** o conserto. |

Fonte canônica: `ye-sandbox/infra-victoria-logs/skills/github-bug-issue`. Investigação ao executar: `victorialogs-troubleshooting`. Emissão de logs: `victorialogs-integration`.

---

## Quando usar / quando não usar

**Usar:** “anota isso”, “abre uma issue”, “depois a gente vê”, problema visto num chat que não é o repo dono, bug que não deve atropelar a tarefa ativa.

**Não usar:** o usuário pediu para **corrigir agora** — aí planeje no `TASK.md` do repo dono (e cite a issue se já existir). Não abra issue em `infra-victoria-logs` só porque você olhou log: esse repo é a stack; bug de produto mora no app (`whatsapp-api`, `solar-energy`, …).

---

## Protocolo

### 1. Confirmar que é “para depois”
Se o usuário não deixou claro, uma pergunta basta. Se for “conserta agora”, saia desta skill.

### 2. Escolher o repositório dono
- Falha na API / gateway / worker do WhatsApp → `whatsapp-api` (ajuste o `owner/repo` com `git remote -v` ou `gh repo view`).
- Falha só no caller (timeout local, payload errado) → repo do caller.
- Ambíguo → issue no serviço de **calha** (API) e um comentário de uma linha no caller, com o URL.

Nunca abra a issue no workspace atual só porque o Cursor está aberto nele.

### 3. Âncoras de evidência (ponteiro, não dump)
Colete o mínimo. Prefira MCP (`list_streams`, `get_errors`, `query_logs`) a colar 200 linhas.

Obrigatório na issue:

1. **Sintoma** — o que a outra app fez e o que quebrou.
2. **Dono** — repo + `service` / `container_name`.
3. **Âncora temporal** — UTC aproximado e janela (`2026-09-06T20:04Z`, `30m`). Sem tempo vira arqueologia.
4. **Identidade** — `request_id`, JID, `message_id`, `status` se existirem. São **campos de evento**, não stream fields.
5. **Consulta sugerida** — uma linha para o agente futuro, por exemplo `get_errors(service="whatsapp-gateway", time_range="1h")`.

Não cole stack trace enorme. Não cole JSON pretty-printed de 50 eventos. O VictoriaLogs já tem o corpo.

### 4. Abrir a issue com `gh`
Use o `gh` (não a API crua). Corpo via HEREDOC. Rode no clone do **repo dono**, ou passe `--repo owner/name`.

```bash
gh issue create --repo <owner>/<name> --title "<sintoma curto em inglês ou pt, uma linha>" --label "bug" --body "$(cat <<'EOF'
## Sintoma
<o que a outra app fez e o que quebrou>

## Dono
- repo: <owner/name>
- service / container: `<nome>`

## Evidência (VictoriaLogs)
- janela: <ISO-8601 UTC> / <ex: 30m>
- request_id / JID / message_id: `<se houver>`
- começar com: `get_errors(service="<nome>", time_range="1h")`

## Esperado vs atual
- Esperado:
- Atual:

## Notas
- visto a partir de: <repo ou app caller>
EOF
)"
```

Devolva o **URL** da issue ao usuário. Não faça push, não mude `TASK.md`, não comece o fix.

### 5. Promover a tarefa ativa (só se o usuário pedir para executar)
No **repo dono**: a issue vira a tarefa ativa do `.agent/TASK.md` (status `EM PLANEJAMENTO`, número da issue no texto). Aí siga `victorialogs-troubleshooting` + o `AGENTS.md` daquele repo.

---

## Exemplo

Título: `gateway returns 502 on POST /messages; sticker never reaches group`

Corpo:

```text
## Sintoma
O solar-energy recebeu 502 ao POST /messages às ~20:04 UTC; o grupo não recebeu a figurinha.

## Dono
- repo: ye-sandbox/whatsapp-api
- service / container: `whatsapp-gateway`

## Evidência (VictoriaLogs)
- janela: 2026-09-06T20:00Z / 30m
- request_id: abc123
- começar com: `get_errors(service="whatsapp-gateway", time_range="1h")`

## Esperado vs atual
- Esperado: 200 e envio da figurinha
- Atual: 502, sem retry visível no caller

## Notas
- visto a partir de: solar-energy
```
