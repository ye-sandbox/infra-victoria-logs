# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-09-26

### Added
- **Container hardening:** Immutable root filesystem (`read_only`), ephemeral `/tmp` via `tmpfs`, and `no-new-privileges: true` on VictoriaLogs, Vector, and vmalert, with matching checks in `scripts/audit-security.sh`.
- **MCP token controls:** Optional `fields` projection, consecutive-repeat collapse, ANSI stripping, `max_buckets` with an explicit truncation notice on `get_log_hits`, and application scoping via `service` on `field_names`.
- **Default telemetry noise filter:** Global MCP queries exclude `docker-stats` and `cadvisor` unless those services are requested explicitly.
- **Vector ingestion guards:** Drop successful `/metrics` scrapes and clamp non-error messages at 8 KB across Docker, HTTP, and syslog profiles.
- **Virtualization-aware disk tuning:** `scripts/tune-disk-host.sh` detects QEMU/KVM guests, recommends the `none` scheduler, and skips `hdparm` inside VMs.
- **SRE token budget:** Three-phase triage funnel (`get_log_hits` → `get_errors` → `get_context_logs`) documented in the agent skills and `AGENTS.md`.

### Fixed
- **vmalert healthcheck:** Probe `wget /health` on port 8880 instead of only checking that the binary starts.
- **Retention fallback:** Compose default is `1y` when `RETENTION_PERIOD` is unset, matching the one-year partition policy.
- **Udev scheduler rules:** Remove the conflicting legacy rule and apply the scheduler immediately on live block devices.

### Changed
- **English agent surface:** `AGENTS.md`, the MCP server messages, and the canonical skills are in technical English. Tool names and parameter keys are unchanged.

## [1.1.0] - 2026-09-12

### Added
- **Open-Source Community Governance:** Formal adoption of Apache License 2.0 (`LICENSE`), comprehensive contributor guide (`CONTRIBUTING.md`) establishing the default 150 MB RAM safeguard for resource-constrained local infrastructure, and responsible vulnerability disclosure policy (`SECURITY.md`).
- **GitHub Issue Templates:** Standardized templates for bug reporting (`bug_report.md`) with hardware environment specifications (HDD vs SSD) and feature requests (`feature_request.md`) requiring memory/CPU footprint impact assessments.
- **Bilingual Documentation:** Full internationalization with the primary `README.md` rewritten in idiomatic English and the complete Portuguese documentation preserved as `README.pt-br.md`, featuring header language selectors and complete technical parity.
- **Decoupled Architecture Guidance:** Replaced private host assumptions with universal Docker host port coexistence guidance.

## [1.0.0] - 2026-09-11

### Added
- **Core Minimalist Observability Stack:** VictoriaLogs + Vector pipeline running strictly under 150 MB total RAM footprint.
- **Dynamic Storage Profiles:** Automated tuning via `STORAGE_PROFILE=hdd` (RAM buffer, 15s batching, ping filtering) and `STORAGE_PROFILE=ssd` (persistent disk buffer, low latency).
- **Native AI Agent MCP Server:** Pure Python 3 JSON-RPC stdio server (`mcp/server.py`) with deduplicated error signatures, contextual LogsQL tips, and 9 forensic tools.
- **Canonical Agent Skills:** Plug-and-play skills for AI agents (`victorialogs-integration`, `victorialogs-troubleshooting`, `github-bug-issue`) with code templates for Python (Loguru/stdlib), Node.js (Pino), and Go (slog).
- **Telemetry & Continuous Monitoring:** Daemonized background collectors for Docker CPU/RAM stats (`ship-docker-stats.sh`) and daemon lifecycle events (`ship-docker-events.sh`).
- **Partition & 1-Year Retention Governance:** CLI suite for daily partition inspection, capacity estimation, and emergency purges (`manage-partitions.sh`) supporting 1-year log retention (< 200 MB/year).
- **Automated Daily Maintenance Pipeline:** Unified orchestrator (`run-maintenance-pipeline.sh`) coordinating disk growth audits, atomic snapshots, and end-to-end LogsQL smoke tests.
- **Host & Container Security Audit:** Hardening CLI (`audit-security.sh`) verifying restricted file permissions, read-only Docker socket mounts (`:ro`), memory caps, and auto-repair (`--fix`).
- **Official Grafana Dashboard:** Pre-built JSON model (`dashboards/grafana-victorialogs.json`) with live throughput, pipeline errors, and query concurrency.
- **Proxmox VE Hardening Guide:** Comprehensive architecture and operating manual (`docs/proxmox-hardening.md`) covering kernel sysctl (`vm.max_map_count`), `noatime`, scheduler selection, and firewall rules.
