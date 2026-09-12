# Política de Segurança (Security Policy)

A segurança e a integridade da stack **VictoriaLogs + Vector** e dos nós de homelab onde ela opera são prioridades absolutas.

---

## 🛡️ Versões Suportadas

Atualmente fornecemos correções de segurança ativas para as seguintes versões:

| Versão | Suportada | Notas |
|---|---|---|
| `v1.x` | :white_check_mark: | Versão estável corrente |
| `< v1.0` | :x: | Versões legadas de desenvolvimento |

---

## 🚨 Reportando uma Vulnerabilidade

Se você descobrir uma vulnerabilidade de segurança neste repositório, **por favor, não abra uma Issue pública** (para evitar a exposição antecipada de potenciais explorações a ambientes de produção).

Em vez disso, utilize o canal oficial de reporte responsável:
1. Utilize a funcionalidade nativa do GitHub: **[Report a vulnerability](https://github.com/ye-sandbox/infra-victoria-logs/security/advisories/new)** no painel de Segurança do repositório.
2. Caso prefira e-mail, entre em contato diretamente com os mantenedores da organização `ye-sandbox`.

Por favor, inclua no seu reporte:
- Uma descrição clara da vulnerabilidade.
- Passos detalhados ou script de prova de conceito (PoC) para reproduzir o problema.
- O impacto potencial no host ou nos containers (ex: escalonamento de privilégio, vazamento de logs, negação de serviço).

Nos comprometemos a confirmar o recebimento do reporte em até **48 horas** e fornecer atualizações regulares sobre o processo de correção e liberação de patch.

---

## 🔒 Boas Práticas Recomendadas para Operadores

Para proteger o seu servidor e os logs da sua infraestrutura:

1. **Permissões do Arquivo `.env`:** Garanta que o arquivo `.env` contenha permissões restritas (`chmod 600 .env`) para que outros usuários do host não tenham acesso a senhas ou parâmetros sensíveis.
2. **Isolamento do Docker Socket:** Nunca monte `/var/run/docker.sock` com permissão de escrita (`:rw`). A stack já vem pré-configurada com `:ro` (somente leitura).
3. **Autenticação em Redes Abertas:** Se a porta `9428` for exposta fora de `127.0.0.1` em redes sem firewall, ative obrigatoriamente `VICTORIALOGS_AUTH_USERNAME` e `VICTORIALOGS_AUTH_PASSWORD`.
4. **Auditoria Automatizada:** Execute regularmente `./scripts/audit-security.sh --strict` para certificar que as permissões e limites de memória continuam em conformidade.
