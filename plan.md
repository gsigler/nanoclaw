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

### 2. Docker socket mount grants container escape

**File:** `src/container-runner.ts` (applyContainerConfig, lines 357-370)

**Issue:** When `containerConfig.dockerSocket` is true, `/var/run/docker.sock` is mounted into the container. The agent can spawn sibling containers with arbitrary mounts (including `/`, `~/.ssh`, `.env`), effectively escaping all isolation.

**Fix:**
- Restrict docker socket access to main group only, with an explicit allowlist check
- Log every container run where docker socket is mounted
- Document the risk clearly in group config and CLAUDE.md
- Consider using a Docker API proxy (like Tecnativa/docker-socket-proxy) that restricts allowed Docker API calls

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

### 4. No rate limiting on message processing or container spawning

**Files:** `src/index.ts`, `src/container-runner.ts`

**Issue:** No per-group or per-sender rate limiting exists. A flood of messages (from a compromised channel or misconfigured bot) could spawn containers up to `MAX_CONCURRENT_CONTAINERS` continuously, exhausting API quota and compute resources.

**Fix:**
- Add per-group message throttle (e.g., max 10 messages/minute, configurable)
- Add per-sender cooldown for non-main groups
- Log and alert when rate limits are hit
- Consider exponential backoff on repeated invocations from same source

---

### 5. Remote control sessions have no TTL

**File:** `src/remote-control.ts`

**Issue:** Remote control sessions are persisted to `data/remote-control.json` and restored on restart with no expiration. If the session URL is leaked (sent over chat in plaintext), it grants indefinite access.

**Fix:**
- Add configurable TTL (default 24h) to remote control sessions
- Require re-authentication after TTL expires
- Log all remote control session creation and usage
- Consider adding an IP allowlist or one-time token pattern

---

## Medium

### 6. Database stores all messages unencrypted

**File:** `src/db.ts`, `store/messages.db`

**Issue:** All conversation messages, task results, and scheduled task data stored in plaintext SQLite. If the host filesystem is accessed, full conversation history is exposed.

**Fix:**
- Evaluate SQLCipher or similar at-rest encryption for the database
- Or rely on OS-level full-disk encryption (document this as a requirement)
- At minimum, ensure database file permissions are 600

---

### 7. Backups are unencrypted

**File:** `scripts/backup.sh`

**Issue:** Backups include conversation history, group memory, and session transcripts pushed to a private GitHub repo without encryption. If the repo is compromised or made public accidentally, all data is exposed.

**Fix:**
- Add optional GPG encryption before pushing to remote
- Or use `git-crypt` for transparent encryption of sensitive paths
- Document that backups contain conversation history and PII

---

### 8. NPM packages unpinned in container Dockerfile

**File:** `container/Dockerfile` (line 73)

**Issue:** MCP server packages installed via `npm install -g` without version pinning. A rebuild could pull a compromised version.

**Fix:**
- Pin all global npm packages to exact versions in Dockerfile
- Consider using a lockfile or `npm ci` pattern for reproducible builds
- Add a comment documenting when versions were last audited

---

### 9. Mount allowlist not hot-reloaded

**File:** `src/mount-security.ts` (line 23)

**Issue:** Mount allowlist is cached in memory at startup. Security policy changes require a full process restart to take effect.

**Fix:**
- Watch the allowlist file for changes and reload on modification
- Or re-read the allowlist on each container spawn (file is small, cost is negligible)

---

### 10. IPC messages lack schema validation

**File:** `src/ipc.ts`

**Issue:** IPC JSON files are parsed and type-asserted without runtime schema validation. Malformed IPC files could cause unexpected behavior in switch cases.

**Fix:**
- Add Zod or similar runtime schema validation for all IPC message types
- Reject and log messages that don't conform to expected schema
- Move errored files to the existing `errors/` directory (already done, but add schema detail to error log)

---

## Low

### 11. Image filenames use Math.random()

**File:** `src/image.ts` (line 36)

**Issue:** `Math.random()` is not cryptographically secure. Filenames are predictable if timing is known.

**Fix:**
- Replace with `crypto.randomUUID()` or `crypto.randomBytes(8).toString('hex')`
- Low actual risk since filenames aren't user-accessible URLs

---

### 12. Telegram callback queries lack HMAC verification

**File:** `src/channels/telegram.ts` (lines 286-308)

**Issue:** Inline button callback data (e.g., `task_done:{id}`) has no signature. A forged callback could trigger task actions.

**Fix:**
- Sign callback data with a host-side HMAC secret
- Verify signature before processing callback
- Low risk since Telegram enforces that callbacks come from real button presses

---

### 13. escapeXml() doesn't cover all contexts

**File:** `src/router.ts` (lines 4-11)

**Issue:** Only escapes `&`, `<`, `>`, `"`. Single quotes and backticks not escaped. If agent output is rendered in contexts beyond XML tags, injection is possible.

**Fix:**
- Add single quote escaping (`'` → `&apos;`)
- Document that escapeXml is for XML attribute/content context only
- Low risk since messages go through channel-specific formatting before delivery

---

### 14. Database row-level isolation is query-based only

**File:** `src/db.ts`

**Issue:** All groups share a single SQLite file. Isolation relies on WHERE clauses filtering by `group_folder`. A missed filter in a new query could leak cross-group data.

**Fix:**
- Add a helper that automatically appends group_folder filter to all group-scoped queries
- Or use SQLite ATTACH with separate per-group database files
- Add tests that verify no query returns cross-group data

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

- **Credential proxy pattern** — Containers never see real Anthropic tokens
- **.env shadowed with /dev/null** — Explicit secret blocking in container mounts
- **Path traversal protection** — Multi-layer validation (regex, resolve, bounds check, symlink resolution)
- **Parameterized SQL everywhere** — No SQL injection vectors found
- **Per-group filesystem isolation** — Sessions, IPC, memory all separated
- **Non-root containers** — uid 1000, no setuid, no capabilities
- **Read-only project mounts** — Agents cannot modify host application code
- **Safe subprocess handling** — spawn() with array args, no shell interpolation
- **IPC authorization gates** — Well-tested, non-main groups restricted to own scope
- **Mount allowlist outside project root** — Agents cannot modify security policy
