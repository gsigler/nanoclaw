#!/usr/bin/env bash
set -euo pipefail

# NanoClaw backup script
# Backs up: SQLite DB, agent memory, sessions, config
# Pushes to a private GitHub repo with timestamped commits

NANOCLAW_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_REPO="${NANOCLAW_DIR}/backups/eos-backup"
REMOTE_URL="https://github.com/gsigler/eos-backup.git"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
DATE_LABEL="$(date +%Y-%m-%d)"

# Paths to back up
DB_PATH="${NANOCLAW_DIR}/store/messages.db"
GROUPS_DIR="${NANOCLAW_DIR}/groups"
SESSIONS_DIR="${NANOCLAW_DIR}/data/sessions"
CONFIG_DIR="${HOME}/.config/nanoclaw"
CLAUDE_DIR="${NANOCLAW_DIR}/.claude"

log() { echo "[backup] $(date +%H:%M:%S) $*"; }

# --- Clone or update backup repo ---
if [ ! -d "${BACKUP_REPO}/.git" ]; then
    log "Cloning backup repo..."
    mkdir -p "$(dirname "$BACKUP_REPO")"
    git clone "$REMOTE_URL" "$BACKUP_REPO" 2>/dev/null || {
        log "Repo empty or not found, initializing..."
        mkdir -p "$BACKUP_REPO"
        cd "$BACKUP_REPO"
        git init
        git remote add origin "$REMOTE_URL"
        git checkout -b main
    }
fi

cd "$BACKUP_REPO"
git pull origin main 2>/dev/null || true

# --- 1. SQLite safe dump ---
log "Dumping SQLite database..."
mkdir -p db
node -e "
const Database = require('better-sqlite3');
const fs = require('fs');
const db = new Database('${DB_PATH}', { readonly: true });
const dump = db.pragma('integrity_check');
if (dump[0].integrity_check !== 'ok') {
    console.error('WARNING: database integrity check failed');
}
// Use backup API for safe copy
db.backup('${BACKUP_REPO}/db/messages.db')
  .then(() => { console.log('Database backup complete'); db.close(); })
  .catch(err => { console.error('Backup failed:', err); process.exit(1); });
"

# --- 2. Agent memory files (CLAUDE.md + small config, exclude node_modules/build artifacts) ---
log "Backing up agent memory..."
mkdir -p groups
rsync -a --delete \
    --exclude='node_modules' \
    --exclude='.pnpm-store' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='.next' \
    --exclude='__pycache__' \
    --exclude='.venv' \
    --exclude='.turbo' \
    --exclude='*.tgz' \
    --exclude='*.tar.gz' \
    "${GROUPS_DIR}/" groups/

# --- 3. Session transcripts ---
log "Backing up sessions..."
mkdir -p sessions
if [ -d "$SESSIONS_DIR" ]; then
    rsync -a --delete "${SESSIONS_DIR}/" sessions/
fi

# --- 4. Config ---
log "Backing up config..."
mkdir -p config/nanoclaw config/claude
if [ -d "$CONFIG_DIR" ]; then
    rsync -a --delete "${CONFIG_DIR}/" config/nanoclaw/
fi
# Back up .claude settings (not worktrees)
rsync -a --delete \
    --exclude='worktrees' \
    "${CLAUDE_DIR}/" config/claude/

# --- 5. Commit and push ---
log "Committing..."
git add -A
if git diff --cached --quiet; then
    log "No changes since last backup."
else
    git commit -m "backup ${TIMESTAMP}"
    log "Pushing to remote..."
    git push -u origin main
    log "Backup complete: ${TIMESTAMP}"
fi
