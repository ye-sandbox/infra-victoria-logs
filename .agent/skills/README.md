# Standard Operating Procedures (Infrastructure Skills)

This directory contains step-by-step procedures instructing AI agents on safely provisioning, updating, and operating services.

---

## Active Skills

| Skill | Location | Primary Purpose |
| :--- | :--- | :--- |
| **`compose-service`** | [`compose-service/SKILL.md`](./compose-service/SKILL.md) | Add or update services in Docker Compose with port isolation, storage persistence, healthchecks, and resource limits. |

> 💡 **Note on Repository Skills (`skills/` at root):**
> Canonical skills designed to be distributed org-wide (such as `victorialogs-troubleshooting` and `victorialogs-integration`) live in the root [`skills/`](../../skills/) directory and are installed globally into agent environments via [`scripts/install-agent-skills.sh`](../../scripts/install-agent-skills.sh). Local agent SOPs live here under `.agent/skills/`.

---

## How to Create a New Infrastructure Skill

1. Copy [`000-template.md`](./000-template.md) to `.agent/skills/<skill-name>/SKILL.md`.
2. Fill the YAML frontmatter (`name` and `description`).
3. Detail prerequisites, operational steps, and validation checks.
4. Add the new skill to the table above and to `AGENTS.md`.
