# Security Remediation Plan

Deep security review of NanoClaw completed 2025-03-25. Findings consolidated below with actionable steps ordered by severity.

## Review Summary

**Overall assessment:** Strong security architecture. OS-level container isolation, credential proxying, per-group filesystem separation, parameterized SQL, and path traversal protection are all well-implemented. No critical exploitable vulnerabilities found in the current single-user deployment model. The items below are hardening opportunities.

---

## Critical

### 1. ~~Credential proxy bind address fallback to 0.0.0.0~~ DONE

**File:** `src/container-runtime.ts` (detectProxyBindHost)

**Fixed:** Added `docker network inspect bridge` fallback to discover the gateway IP when docker0 interface isn't found. Only falls back to `0.0.0.0` as last resort with a prominent `logger.warn` telling the user to set `CREDENTIAL_PROXY_HOST`.

---

### 2. ~~Docker socket mount grants container escape~~ ACCEPTED

Docker socket is only enabled on the workshop group, which builds and runs apps that require Docker. Intentional trust decision — accepted risk for that group's use case.

---

## High

### 3. ~~GitHub and Notion tokens passed directly to containers~~ DONE

**Files:** `src/credential-proxy.ts`, `src/container-runner.ts`

**Fixed:** Extended credential proxy with `/_cred/*` endpoints. Containers now fetch tokens on-demand via wrapper scripts in `/workspace/ipc/bin/`:
- `gh` wrapper fetches GH_TOKEN per-invocation (shadows `/usr/bin/gh` via PATH)
- Git credential helper fetches token per push/clone operation
- MCP servers (Notion, Tendy, YNAB) use wrapper commands that fetch tokens at startup
- No tokens in env vars, no tokens in mcp.json — only in proxy memory on the host

---

### 4. ~~No rate limiting on message processing or container spawning~~ DONE

**Files:** `src/index.ts`, `src/config.ts`

**Fixed:** Added per-group sliding window rate limiter (default 10 invocations/minute, configurable via `RATE_LIMIT_MAX` env var). Logs warning when rate limit is hit, consumes messages to prevent infinite retry loops.

---

### 5. Remote control sessions have no TTL — SKIPPED

Accepted risk — feature is rarely used and restricted to main group.

---

## Medium

### 6. Database file permissions — DONE (encryption skipped)

**Fixed:** Database file permissions set to 0o600 (owner-only) on init. Encryption skipped per user decision.

---

### 7. Backup encryption — SKIPPED

Accepted risk per user decision.

---

### 8. ~~NPM packages unpinned in container Dockerfile~~ DONE

**File:** `container/Dockerfile`

**Fixed:** All global npm packages pinned: agent-browser@0.22.3, claude-code@2.1.83, notion-mcp-server@2.2.1, google-calendar-mcp@2.6.1, mcp-remote@0.1.38.

---

### 9. ~~Mount allowlist not hot-reloaded~~ DONE

**File:** `src/mount-security.ts`

**Fixed:** Allowlist checks file mtime on each load and reloads automatically when changed. No restart needed.

---

### 10. ~~IPC messages lack schema validation~~ DONE

**File:** `src/ipc.ts`

**Fixed:** Added Zod schemas for IPC message and task types. Files failing validation are logged and discarded.

---

## Low

### 11. ~~Image filenames use Math.random()~~ DONE

**File:** `src/image.ts` — replaced with `crypto.randomBytes(4).toString('hex')`.

---

### 12. ~~Telegram callback queries lack HMAC verification~~ DONE

**File:** `src/channels/telegram.ts` — callback data HMAC-signed (SHA-256, 32-bit truncated, per-process key).

---

### 13. ~~escapeXml() doesn't cover all contexts~~ DONE

**File:** `src/router.ts` — added `&apos;` escaping.

---

### 14. Database row-level isolation — SKIPPED

All existing queries correctly filter by chat_jid/group_folder. Acceptable for single-user deployment.

---

## Documentation

### 15. Write SECURITY.md

Create a `SECURITY.md` documenting:
- The trust model (host trusted, containers untrusted, main group privileged)
- Why Anthropic credentials are proxied but GH/Notion are exposed
- Container isolation guarantees and limitations
- Network access model (containers have full outbound access by design)
- Backup contents and sensitivity
- Required host-level security (full-disk encryption, file permissions)

---

## Positive Findings (no action needed)

These are well-implemented and worth preserving:

- **Credential proxy pattern** — Containers never see real tokens (Anthropic, GitHub, Notion, Tendy, YNAB)
- **.env shadowed with /dev/null** — Explicit secret blocking in container mounts
- **Path traversal protection** — Multi-layer validation (regex, resolve, bounds check, symlink resolution)
- **Parameterized SQL everywhere** — No SQL injection vectors found
- **Per-group filesystem isolation** — Sessions, IPC, memory all separated
- **Non-root containers** — uid 1000, no setuid, no capabilities
- **Read-only project mounts** — Agents cannot modify host application code
- **Safe subprocess handling** — spawn() with array args, no shell interpolation
- **IPC authorization gates** — Well-tested, non-main groups restricted to own scope
- **Mount allowlist outside project root** — Agents cannot modify security policy
