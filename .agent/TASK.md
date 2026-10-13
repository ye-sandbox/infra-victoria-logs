# TASK.md — Current Infrastructure Task and Roadmap

> Defines WHAT needs to be done in infrastructure. Detailed history lives in `git log` and `.agent/ARCHIVE.md`.
> User requests during conversation take precedence — report discrepancies before acting.

---

## Active Task

### 📌 Task [52.0]: Align Infrastructure Governance and Topology with template-agent:infra

- **Description:** Complete alignment of repository governance, service topology catalog, and documentation taxonomy with the latest `ye-sandbox/template-agent:infra` specification.
- **Systems Involved:** Governance (`.agent/`, `AGENTS.md`), Topology (`.agent/SERVICES.md`), Documentation (`docs/`, `README.md`, `README.pt-br.md`).
- **Action Type:**
  - [x] Read-only / Documentation
  - [x] Source code / Structure changes
- **Status:** RUNNING

### Acceptance Criteria
- [x] `.agent/SERVICES.md` created as canonical source of truth for ports, volumes, and networks.
- [x] Historical tasks (00.1 to 51.0) archived into `.agent/ARCHIVE.md`.
- [x] `AGENTS.md` updated with Rule Precedence Hierarchy, Modular Context Triggers, Fail-Stop structured YAML block, and Contrast Pairs.
- [x] `docs/` taxonomy established (`docs/README.md`, `docs/architecture/000-template.md`, `docs/incidents/README.md`, `docs/incidents/000-template.md`).
- [x] YAML Frontmatter added to `docs/proxmox-hardening.md`.
- [x] `.agent/NOTES.md` synchronized with `SERVICES.md` and incidents hub.
- [x] `README.md` and `README.pt-br.md` updated with revised structure.
- [x] `docker compose config` syntax verification passes.

---

## Completed Tasks Log

| Task | Title | Commit(s) | Date |
|---|---|---|---|
| `[v1.0.0]` | Consolidated historical tasks 00.1 through 51.0 | See `ARCHIVE.md` | 2026-09-21 |

---

## Backlog (Upcoming, in priority order)

- [ ] **[53.0]** Native VRL Regression Tests (`vector test`) for canonical logging templates (Loguru, Pino, Slog), correlation fields, and severity detection.

---

## Release / Cycle Wrap-up (Not the next task)

- [ ] **[99.1]** Audit open ports and secrets scrubbing
- [ ] **[99.2]** Release version bump and tag