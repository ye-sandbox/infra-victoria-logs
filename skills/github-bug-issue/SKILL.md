---
name: github-bug-issue
description: Opens a GitHub issue to park a bug for a later agent, with VictoriaLogs evidence pointers instead of log dumps. Use when the user notices a problem in another app (WhatsApp API, caller service, homelab), wants to annotate context for later, or asks to file/create a GitHub issue rather than fix it now. Do not use TASK.md as a bug queue.
---

# Capture Bug for Later (GitHub Issue + VictoriaLogs)

When the user **notices an issue** (in another app, WhatsApp API, a caller service) and wants to **record context** for an agent to investigate later: open an **issue on GitHub in the owning repository**. Do not use `.agent/TASK.md` as a bug queue.

| Artifact | Role |
|---|---|
| **GitHub Issue** | Inbox. Persistent, numbered, linkable to PRs. |
| **VictoriaLogs** | Evidence locker. The issue points; MCP reconstructs the incident. |
| **`.agent/TASK.md`** | Workbench. Exactly one active task. Only entered when the user is ready to **execute** the fix. |

Canonical source: `ye-sandbox/infra-victoria-logs/skills/github-bug-issue`. Investigation during execution: `victorialogs-troubleshooting`. Log emission: `victorialogs-integration`.

---

## When to use / When not to use

**Use:** "take note of this", "open an issue", "we'll look at it later", problem observed in a chat that is not the owning repo, bug that should not interrupt the active task.

**Do not use:** the user asked to **fix it now** — in that case, plan in `TASK.md` of the owning repo (and cite the issue if one already exists). Do not open an issue in `infra-victoria-logs` just because you inspected logs: this repo is the stack; product bugs live in the application (`whatsapp-api`, `solar-energy`, …).

---

## Protocol

### 1. Confirm that it is "for later"
If the user did not make it clear, a single question suffices. If it is "fix now", exit this skill.

### 2. Choose the owning repository
- Failure in the WhatsApp API / gateway / worker → `whatsapp-api` (inspect `owner/repo` using `git remote -v` or `gh repo view`).
- Failure only in the caller (local timeout, bad payload) → caller repository.
- Ambiguous → open issue in the downstream **sink** service (API) and add a one-line comment in the caller with the URL.

Never open the issue in the current workspace just because Cursor or the agent is opened in it.

### 3. Evidence anchors (pointers, not dumps)
Collect the minimum necessary. Prefer MCP (`list_streams`, `get_errors`, `query_logs`) over pasting 200 lines.

Mandatory in the issue:

1. **Symptom** — what the other app did and what broke.
2. **Owner** — repo + `service` / `container_name`.
3. **Time anchor** — approximate UTC timestamp and window (`2026-09-06T20:04Z`, `30m`). Without time, it becomes archaeology.
4. **Identity** — `request_id`, JID, `message_id`, `status` if present. These are **event fields**, not stream fields.
5. **Suggested query** — a single line for the future agent, e.g. `get_errors(service="whatsapp-gateway", time_range="1h")`.

Do not paste massive stack traces. Do not paste pretty-printed JSON of 50 events. VictoriaLogs already holds the body.

### 4. Open the issue with `gh`
Use `gh` (not raw API calls). Provide the body via HEREDOC. Run in the clone of the **owning repo**, or pass `--repo owner/name`.

```bash
gh issue create --repo <owner>/<name> --title "<concise one-line symptom in English or Portuguese>" --label "bug" --body "$(cat <<'EOF'
## Symptom
<what the other app did and what broke>

## Owner
- repo: <owner/name>
- service / container: `<name>`

## Evidence (VictoriaLogs)
- window: <ISO-8601 UTC> / <e.g. 30m>
- request_id / JID / message_id: `<if available>`
- start with: `get_errors(service="<name>", time_range="1h")`

## Expected vs Actual
- Expected:
- Actual:

## Notes
- observed from: <caller repo or app>
EOF
)"
```

Return the issue **URL** to the user. Do not git push, do not modify `TASK.md`, do not begin fixing.

### 5. Promote to active task (only when user asks to execute)
In the **owning repo**: the issue becomes the active task in `.agent/TASK.md` (status `EM PLANEJAMENTO`, issue number noted). Then follow `victorialogs-troubleshooting` + the `AGENTS.md` of that repository.

---

## Example

Title: `gateway returns 502 on POST /messages; sticker never reaches group`

Body:

```text
## Symptom
solar-energy received 502 upon POST /messages at ~20:04 UTC; the group never received the sticker.

## Owner
- repo: ye-sandbox/whatsapp-api
- service / container: `whatsapp-gateway`

## Evidence (VictoriaLogs)
- window: 2026-09-06T20:00Z / 30m
- request_id: abc123
- start with: `get_errors(service="whatsapp-gateway", time_range="1h")`

## Expected vs Actual
- Expected: 200 and sticker delivered
- Actual: 502, no retry visible in caller

## Notes
- observed from: solar-energy
```
