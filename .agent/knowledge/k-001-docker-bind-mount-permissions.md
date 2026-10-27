---
id: "k-001"
title: "UID/GID Ownership Alignment for Non-Root Docker Bind Mounts"
date: 2026-10-19
tags:
  - "docker"
  - "compose"
  - "permissions"
  - "bind-mount"
  - "linux"
severity: "high"
affected_components:
  - "compose.yaml.example"
  - ".env.example"
symptoms:
  - "Permission denied (EACCES) in container"
  - "touch: cannot touch ...: Permission denied"
  - "mkdir: cannot create directory ...: Permission denied"
  - "fatal: could not create work tree dir ... Permission denied"
---

# [k-001] UID/GID Ownership Alignment for Non-Root Docker Bind Mounts

## Problem / Symptom

When mounting a host directory into a Docker container running as a non-root user (e.g., `node`, `appuser`, UID `1000:1000`), the container processes fail with `EACCES` or `Permission denied` errors if the host directory is owned by `root` or a different UID/GID.

Common symptom during container initialization or file write:

```text
mkdir: cannot create directory '/app/data/logs': Permission denied
touch: cannot touch '/app/data/app.db': Permission denied
fatal: could not open database file: sqlite error code 14 (unable to open database file)
```

## Approved Solution

Ensure directory ownership and user mapping align before or during container execution:

1. **Host-Side Pre-Seeding (Recommended):**
   Explicitly create required host directories with the target user ownership before mounting:

   ```bash
   mkdir -p ./data ./logs
   # INVARIANT: Set ownership to matching service UID:GID (e.g. 1000:1000)
   chown -R 1000:1000 ./data ./logs
   ```

2. **Compose User Parameterization:**
   Map host user directly in `compose.yaml` using parameterized environment variables:

   ```yaml
   services:
     app:
       image: node:20-alpine
       user: "${UID:-1000}:${GID:-1000}"
       volumes:
         - ./data:/app/data
   ```

   And define defaults in `.env.example`:

   ```env
   UID=1000
   GID=1000
   ```

3. **Ephemeral Init Container:**
   For multi-user stacks, use an ephemeral `init` container to fix directory ownership prior to launching service containers:

   ```yaml
   services:
     init-volume:
       image: busybox:musl
       command: chown -R 1000:1000 /target
       volumes:
         - ./data:/target
   ```

**Root Cause:** The Linux kernel enforces host file permission checks based on numeric UID/GID values. When a container namespace does not use user remapping (userns), UID 1000 inside the container is checked directly against UID 1000 on the host filesystem.

## What NEVER to Do

- ❌ **Anti-Pattern:** Running `chmod 777 -R ./data` across host volumes.
  - *Why:* Unrestricted permissions allow any process on the host or inside any container to read, modify, or delete sensitive application data, violating least-privilege security.
- ❌ **Anti-Pattern:** Forcing containers to run as `root` (`user: "0:0"`) merely to bypass permission issues.
  - *Why:* Running container processes as root increases vulnerability blast radius, enabling container breakout exploits to achieve host root execution.

## Verification

Verify write capability from within the container context without root privileges:

```bash
docker compose run --rm --no-deps app touch /app/data/.healthcheck-write-test
docker compose run --rm --no-deps app rm /app/data/.healthcheck-write-test
```

## References
- [Docker Documentation: Understand how UID and GID work in containers](https://docs.docker.com/engine/security/userns-remap/)
