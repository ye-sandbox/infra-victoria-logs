# TASK.md — Current Infrastructure Task and Roadmap

> Defines WHAT needs to be done in infrastructure. Detailed history lives in `git log` and `.agent/ARCHIVE.md`.
> User requests during conversation take precedence — report discrepancies before acting.

---

## Active Task

### 📌 No active task at the moment (Awaiting next user instruction or backlog definition)

- **Description:** Task 58.0 completed successfully. Waiting for user authorization or backlog definition for the next task.
- **Systems Involved:** N/A
- **Action Type:** N/A
- **Status:** AWAITING TASK

---

## Completed Tasks Log

| Task | Title | Commit(s) | Date |
|---|---|---|---|
| `58.0` | Harmonize Infrastructure Governance and Contracts with template-agent:infra | `badbd1d` | 2026-10-27 |
| `57.0` | Canonical Healthcheck Probe Discarding in Vector VRL (plaintext and structured JSON) | `dcc1c0c` | 2026-10-27 |
| `56.0` | Evolução do Servidor MCP (Timeout por Chamada + Modo Transporte SSE) | `cf3b5a6` | 2026-10-13 |
| `55.0` | Off-Site Backup Resilience in backup.sh (3-2-1 Rule: rclone, rsync, S3, dry-run) | `3aaaae8` | 2026-10-13 |
| `54.0` | Lightweight Notification Channel for vmalert (alert-bridge: ntfy / Telegram / Webhook) | `33ac397` | 2026-10-13 |
| `53.0` | Native VRL Regression Tests (vector test) | `495a564` | 2026-10-12 |
| `52.0` | Align Infrastructure Governance and Topology with template-agent:infra | `68462e2` | 2026-10-12 |
| `[v1.0.0]` | Consolidated historical tasks 00.1 through 51.0 | See `ARCHIVE.md` | 2026-09-21 |

---

## Backlog (Upcoming, in priority order)

- [ ] [Awaiting next task definitions]

---

## Release / Cycle Wrap-up (Not the next task)

- [ ] **[99.1]** Audit open ports and secrets scrubbing
- [ ] **[99.2]** Release version bump and tag