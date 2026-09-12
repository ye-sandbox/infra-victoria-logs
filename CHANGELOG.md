# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Open-Source Community Governance:** Formal adoption of Apache License 2.0 (`LICENSE`), comprehensive contributor guide (`CONTRIBUTING.md`) strictly enforcing the non-negotiable 150 MB RAM ceiling, and responsible vulnerability disclosure policy (`SECURITY.md`).
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
