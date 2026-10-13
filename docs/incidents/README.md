---
title: "Incident Postmortems & Root Cause Analysis (RCA) Hub"
author_type: "agent-assisted"
author: "Antigravity"
reviewed_by: "pending"
date: 2026-10-12
status: "approved"
type: "guide"
---

# 🚨 Incident Postmortems & Root Cause Analysis (RCA) Hub

This directory archives structured Root Cause Analysis (RCA) narratives, postmortems, and preventive action trackers for operational failures and outages across the VictoriaLogs + Vector observability stack.

---

## 🧭 Incident Graduation & Severity Tiers

To prevent operational overhead while guaranteeing deep accountability for critical issues, categorize events into three tiers before authoring documentation:

| Tier | Category | Operational Impact | Where to Document? | Expected Detail |
| :---: | :--- | :--- | :--- | :--- |
| **Tier 1** | **Gotchas & Transient Glitches** | No data loss, quick configuration fix, trivial port/memory limit adjustment resolved in minutes. | [`.agent/NOTES.md`](../../.agent/NOTES.md) (*Gotchas and Quirks*) | 3 to 5 lines explaining the quirk and avoidance rule. |
| **Tier 2** | **Recurring Operational Issues** | Known failure mode requiring rapid triage (e.g. partition purge, disk growth alert). | [`docs/`](../) or dedicated scripts/runbooks | Step-by-step mitigation commands and health verification. |
| **Tier 3** | **Critical Incidents & Outages (RCA)** | Service outage, log data loss, complex root causes, or architectural breakdowns. | **`docs/incidents/YYYY-MM-DD-<slug>.md`** | Full postmortem using [`000-template.md`](./000-template.md) (Timeline, Cause, Reasoning, Solution, Prevention). |

---

## 🗂️ File Naming Convention

All Tier 3 incident files MUST use chronological ISO date prefixes:
```text
docs/incidents/YYYY-MM-DD-<service-or-symptom-slug>.md
```
*Examples:*
- `docs/incidents/2026-09-17-hdd-io-wait-apps-worker.md`
- `docs/incidents/2026-09-25-vector-disk-buffer-overflow.md`

---

## 📋 Historical Incident Index

| Date (UTC) | Incident Title | Severity | Impacted Services | Primary Root Cause | Postmortem Link |
|---|---|---|---|---|---|
| `YYYY-MM-DD` | *[Example] Vector OOM during log storm* | *High* | `vector`, `victorialogs` | *Uncapped batching and lack of memory limit margin* | [Postmortem](./000-template.md) |

---

## 🛡️ Preventive Action Items Tracker

A postmortem is only as effective as the systemic prevention it delivers. All action items from Tier 3 RCAs must be logged and tracked below until permanently resolved:

| ID | Action Item Description | Incident Source | Category | Owner | Target Date | Status |
| :---: | :--- | :--- | :--- | :--- | :---: | :---: |
| `ACT-01` | *[Example] Add clamping preventive filter to Vector VRL* | *Vector OOM* | Preventive | *Engineer* | *YYYY-MM-DD* | *Closed* |

---

## 🔗 Related Resources
- **Starter RCA Template:** [`docs/incidents/000-template.md`](./000-template.md)
- **Service Port & Topology Registry:** [`.agent/SERVICES.md`](../../.agent/SERVICES.md)
- **Decisions & Gotchas:** [`.agent/NOTES.md`](../../.agent/NOTES.md)
