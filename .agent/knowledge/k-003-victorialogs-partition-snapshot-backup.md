---
id: "k-003"
title: "VictoriaLogs Partition Snapshot API and Backup Extraction"
date: 2026-10-27
tags:
  - "victorialogs"
  - "backup"
  - "storage"
  - "snapshots"
  - "docker"
severity: "high"
affected_components:
  - "scripts/backup.sh"
  - "compose.yaml"
symptoms:
  - "VictoriaLogs returns 404 / unsupported path requested on /snapshot/create"
  - "Cannot execute tar inside victorialogs container (distroless scratch image)"
---

# [k-003] VictoriaLogs Partition Snapshot API and Backup Extraction

## Problem / Symptom

VictoriaLogs organizes indexed data into immutable daily partitions. Unlike VictoriaMetrics (TSDB), VictoriaLogs does not support the global `/snapshot/create` endpoint. Calling `POST http://localhost:9428/snapshot/create` fails with:

```text
HTTP 404: unsupported path requested: /snapshot/create
```

Furthermore, the official container image `victoriametrics/victoria-logs` is distroless (scratch-based) without `/bin/sh` or `/bin/tar`, preventing in-container archiving commands (`docker exec victorialogs tar ...`).

---

## Approved Solution

Use VictoriaLogs internal partition snapshot endpoints and stream data externally via `docker cp`:

1. **Create Partition Snapshot:**
   ```bash
   SNAPSHOT_RESP=$(curl -s -f -X POST "http://localhost:9428/internal/partition/snapshot/create")
   SNAPSHOT_PATH=$(echo "${SNAPSHOT_RESP}" | grep -oE '/[^"]+')
   ```

2. **Stream Partition Files with Docker Copy:**
   Extract snapshot directly to host without entering the container:
   ```bash
   docker cp "victorialogs:${SNAPSHOT_PATH}" "${HOST_BACKUP_DIR}/"
   ```

3. **Delete Snapshot Immediately After Copy:**
   Always clean up partition snapshot references to free disk space:
   ```bash
   curl -s -f -X POST "http://localhost:9428/internal/partition/snapshot/delete?path=${SNAPSHOT_PATH}"
   ```

**Root Cause:** VictoriaLogs stores partitioned data in discrete epoch folders. Snapshots must be requested through partition APIs rather than TSDB snapshot APIs, and distroless packaging requires extraction through Docker engine APIs.

---

## What NEVER to Do
- ❌ **Anti-Pattern:** Attempting `docker exec victorialogs tar -czf ...`
  - *Why:* The container contains only `/victoria-logs-prod`; attempting to run `tar` or `sh` fails with OCI runtime errors.
- ❌ **Anti-Pattern:** Directly archiving active live storage directories while the engine is running without taking a partition snapshot.
  - *Why:* Live files undergo concurrent compaction and journal writes, causing corrupted backup archives.

---

## Verification
```bash
bash scripts/backup.sh --dry-run
```

---

## References
- [VictoriaLogs Backup & Restore Documentation](https://docs.victoriametrics.com/victorialogs/)
