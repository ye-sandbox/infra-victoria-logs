---
title: "[INCIDENT-000] [Descriptive Incident Title]"
author_type: "agent"           # "agent" | "human" | "agent-assisted"
author: "Antigravity"          # Author name / agent identifier
reviewed_by: "pending"         # Human reviewer username, or "pending"
date: YYYY-MM-DD
status: "draft"                # "draft" | "under-review" | "approved" | "deprecated"
type: "incident-rca"           # Canonical type for postmortems and troubleshooting narratives
---

# [INCIDENT-000] [Descriptive Incident Title]

## 1. Executive Summary & Impact

- **Incident Date & Duration:** [YYYY-MM-DD HH:MM to HH:MM UTC (~XX minutes/hours)]
- **Severity / Impact Level:** [Critical / High / Medium / Low]
- **Services Affected:** [e.g. VictoriaLogs, Vector, vmalert]
- **User Impact:** [Summary of degraded capabilities, dropped logs, or data risks]

---

## 2. Timeline of Events

| Timestamp (UTC) | Event / Symptom | Detected By |
|---|---|---|
| `HH:MM` | First failure or alert triggered | [Monitoring / User] |
| `HH:MM` | Initial triage started | [Engineer / Agent] |
| `HH:MM` | Root cause identified | [Agent / Engineer] |
| `HH:MM` | Temporary workaround / patch applied | [Agent / Engineer] |
| `HH:MM` | Full recovery confirmed via healthchecks | [Monitoring] |

---

## 3. Root Cause Analysis (Causa Raiz)

### Primary Root Cause
[Concise and precise explanation of the underlying failure mechanism. Example: Port collision on 9428, volume permissions mismatch with host UID 1000, unindexed query timeout, or disk partition exhaustion.]

### Contributing Factors
- [Trigger or secondary condition 1]
- [Trigger or secondary condition 2]

---

## 4. Investigation & Line of Reasoning (Linha de Raciocínio)

Document the diagnostic thought process, evidence gathered, and hypotheses evaluated during triage:

### Hypothesis 1: [Initial Assumption / Suspected Cause]
- **Reasoning:** [Why this was initially suspected]
- **VictoriaLogs / LogsQL Query:**
  ```text
  _stream:{service="<service_name>"} AND (level:error OR "fatal" OR "panic")
  timerange: YYYY-MM-DDTHH:MM:00Z to YYYY-MM-DDTHH:MM:00Z
  hits: XX
  ```
- **Evidence / Logs Gathered:**
  ```text
  [Relevant log excerpts, command outputs (e.g. ss -tuln, dmesg, journalctl, docker compose logs)]
  ```
- **Outcome:** [Confirmed / Disproved] — [Explanation of why this hypothesis was retained or discarded]

### Hypothesis 2: [Subsequent Assumption]
- **Reasoning:** [Why this avenue was explored]
- **VictoriaLogs / LogsQL Query:**
  ```text
  _stream:{host="<host_name>"} AND "<keyword>"
  ```
- **Evidence Gathered:**
  ```text
  [Evidence]
  ```
- **Outcome:** [Confirmed / Disproved]

---

## 5. Remediation & Solution (Solução Aplicada)

### Immediate Mitigation (Workaround)
[Steps executed to restore service immediately, even if temporary.]
```bash
# Exact commands executed
docker compose restart <service>
```

### Permanent Fix
[Architectural or configuration change implemented to resolve the defect permanently.]
- **Pull Request / Commit:** [`commit-hash`]
- **Configuration Delta:** [Summary of changes in compose.yaml, vector.yaml, or host scripts]

---

## 6. Prevention & Action Items (Prevenção e Lições Aprendidas)

| Action Item | Type | Owner | Status |
|---|---|---|---|
| [Add healthcheck interval adjustment to prevent premature kill] | Preventive | [Engineer] | [Open] |
| [Update SERVICES.md port registry to prevent future collisions] | Documentation | [Agent] | [Done] |
| [Implement automated alert rule in vmalert] | Monitoring | [Engineer] | [Open] |

---

## 7. References and Evidence Anchors

- VictoriaLogs Query / Stream: `_stream:{service="vector"} AND level:error`
- Related Task: `[XX.Y]` in [`.agent/TASK.md`](../../.agent/TASK.md)
- Architectural Gotcha: [`.agent/NOTES.md`](../../.agent/NOTES.md)
