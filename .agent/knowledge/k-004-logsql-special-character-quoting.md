---
id: "k-004"
title: "Mandatory Double Quotes on Special Characters in LogsQL Queries"
date: 2026-10-27
tags:
  - "logsql"
  - "victorialogs"
  - "mcp"
  - "query-syntax"
severity: "medium"
affected_components:
  - "mcp/server.py"
  - "skills/victorialogs-troubleshooting/SKILL.md"
symptoms:
  - "HTTP 400 Bad Request: probably, the whole string must be put into quotes"
  - "LogsQL parse error on WhatsApp JIDs, email addresses, URLs, or hyphenated identifiers"
---

# [k-004] Mandatory Double Quotes on Special Characters in LogsQL Queries

## Problem / Symptom

The LogsQL parser treats unquoted tokens containing punctuation characters (`@`, `:`, `/`, `-`, `.`, spaces, or parentheses) as syntax delimiters or key-value separators. For example, querying an unquoted WhatsApp JID or URL:

```text
120363421617257978@g.us
https://example.com/api/v1
```

Fails immediately with HTTP 400 from VictoriaLogs:

```text
HTTP 400: parsing error: unexpected char '@'; probably, the whole string must be put into quotes: "120363421617257978@g.us"
```

---

## Approved Solution

Always enclose any token containing punctuation or non-alphanumeric characters in double quotes:

1. **Exact Word Match:**
   ```logsql
   "120363421617257978@g.us"
   ```

2. **Substring Match:**
   ```logsql
   _msg:~"120363421617257978@g.us"
   ```

3. **Field Value Match:**
   ```logsql
   container_name:"api-gateway"
   ```

**Root Cause:** LogsQL uses `:`, `~`, and whitespace as operators. Without quotes, the lexer splits the identifier into invalid syntax tokens.

---

## What NEVER to Do
- ❌ **Anti-Pattern:** Leaving email addresses, URLs, or WhatsApp JIDs unquoted in `query_logs` or `get_errors` MCP calls.
  - *Why:* Results in immediate HTTP 400 failures, wasting context tokens and halting automated triage.
- ❌ **Anti-Pattern:** Escaping with backslashes instead of wrapping in double quotes (e.g. `120363421617257978\@g.us`).
  - *Why:* Backslash escaping is not valid LogsQL token syntax for unquoted literals.

---

## Verification
```bash
curl -s -G "http://localhost:9428/select/logsql/query" --data-urlencode 'query="test@domain.com"'
```

---

## References
- [VictoriaLogs LogsQL Syntax Reference](https://docs.victoriametrics.com/victorialogs/logsql/)
