---
title: "[ARCH-000] [Architecture Document Title]"
author_type: "agent"           # "agent" | "human" | "agent-assisted"
author: "Antigravity"          # Author name / agent identifier
reviewed_by: "pending"         # Human reviewer username, or "pending"
date: YYYY-MM-DD
status: "draft"                # "draft" | "under-review" | "approved" | "deprecated"
type: "architecture"           # "architecture" | "incident-rca" | "host-runbook" | "guide"
---

# [ARCH-000] [Architecture Document Title]

## 1. Context & Motivation
[Describe the engineering context, constraints, and problem statement motivating this architecture or topological design.]

---

## 2. High-Level Architecture & Topology

```text
[Insert ASCII / Mermaid diagram representing traffic flow, service boundaries, ports, and network segregation]
```

### Component Breakdown
- **Component / Service A:** [Role, network boundary, exposed ports]
- **Component / Service B:** [Role, internal dependencies, volume mounts]

---

## 3. Network & Storage Specifications

### Network Boundaries
- `logging-network`: Isolated telemetry network for log ingestion and alerts

### Persistent Storage & Volumes
- `named_volume`: Rationale for named volume vs bind mount, backup strategy, and UID requirements.

---

## 4. Operational Invariants & Security
- Resource limits (CPU/Memory)
- Healthcheck endpoints and criteria
- Secrets handling via `.env.example`

---

## 5. References & Related Links
- Services Registry: [`.agent/SERVICES.md`](../../.agent/SERVICES.md)
- Decisions & Gotchas: [`.agent/NOTES.md`](../../.agent/NOTES.md)
