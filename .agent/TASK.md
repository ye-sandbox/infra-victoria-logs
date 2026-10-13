# TASK.md — Current Infrastructure Task and Roadmap

> Defines WHAT needs to be done in infrastructure. Detailed history lives in `git log` and `.agent/ARCHIVE.md`.
> User requests during conversation take precedence — report discrepancies before acting.

---

## Active Task

### 📌 Task [53.0]: Native VRL Regression Tests (vector test)

- **Description:** Implement native unit testing suite for Vector using `vector test`, covering JSON parsing for official templates (Loguru, Pino, Slog), correlation fields promotion (`trace_id`, `request_id`, `http_status`, `duration_ms`), probe dropping/retention (`/metrics`, `/health`, `scrape`), 8 KB clamping behavior with `.truncated = true` vs stack trace preservation, and Syslog normalization (RFC5424 / RFC3164) with severity detection.
- **Systems Involved:** Vector transforms (`vector/*.yaml`), Test suite (`tests/vector/`), Automation (`scripts/test-vector.sh`), Documentation (`README.md`, `README.pt-br.md`, `.agent/NOTES.md`).
- **Action Type:**
  - [x] Read-only / Documentation
  - [x] Source code / Tests
- **Status:** READY FOR PLANNING

### Acceptance Criteria
- [ ] Test cases authored for Loguru, Pino, and Slog canonical JSON formats.
- [ ] Test assertions verify promotion of `trace_id`, `request_id`, and `http_status`.
- [ ] Clamping tests assert 8 KB truncations with `.truncated = true`.
- [ ] Syslog tests assert RFC5424 and RFC3164 parsing.
- [ ] CI/test script runs `vector test` and exits with code 0.

---

## Completed Tasks Log

| Task | Title | Commit(s) | Date |
|---|---|---|---|
| `52.0` | Align Infrastructure Governance and Topology with template-agent:infra | `68462e2` | 2026-10-12 |
| `[v1.0.0]` | Consolidated historical tasks 00.1 through 51.0 | See `ARCHIVE.md` | 2026-09-21 |

---

## Backlog (Upcoming, in priority order)

- [ ] [Awaiting next task definitions]

---

## Release / Cycle Wrap-up (Not the next task)

- [ ] **[99.1]** Audit open ports and secrets scrubbing
- [ ] **[99.2]** Release version bump and tag