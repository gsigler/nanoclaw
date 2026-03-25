#!/usr/bin/env bash
set -euo pipefail

# NanoClaw restore script
# Restores from a backup commit in eos-backup repo

NANOCLAW_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_REPO="${NANOCLAW_DIR}/backups/eos-backup"
REMOTE_URL="https://github.com/gsigler/eos-backup.git"

DB_PATH="${NANOCLAW_DIR}/store/messages.db"
GROUPS_DIR="${NANOCLAW_DIR}/groups"
SESSIONS_DIR="${NANOCLAW_DIR}/data/sessions"
CONFIG_DIR="${HOME}/.config/nanoclaw"
CLAUDE_DIR="${NANOCLAW_DIR}/.claude"

log() { echo "[restore] $(date +%H:%M:%S) $*"; }

# --- Ensure backup repo exists ---
if [ ! -d "${BACKUP_REPO}/.git" ]; then
    log "Cloning backup repo..."
    mkdir -p "$(dirname "$BACKUP_REPO")"
    git clone "$REMOTE_URL" "$BACKUP_REPO"
fi

cd "$BACKUP_REPO"
git fetch origin

# --- List available backups ---
if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
    echo "Available backups:"
    echo ""
    git log --oneline --format="%h  %s  (%cr)" origin/main | head -30
    exit 0
fi

# --- Pick a commit ---
COMMIT="${1:-}"
if [ -z "$COMMIT" ]; then
    echo "Usage:"
    echo "  $0 --list              # show available backups"
    echo "  $0 <commit-hash>       # restore specific backup"
    echo "  $0 latest              # restore most recent backup"
    exit 1
fi

if [ "$COMMIT" = "latest" ]; then
    COMMIT="origin/main"
fi

# Show what we're restoring
log "Restoring from: $(git log --oneline -1 "$COMMIT")"
echo ""
read -p "This will overwrite current data. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Aborted."
    exit 1
fi

# Checkout the target commit
git checkout "$COMMIT" -- .

# --- Stop nanoclaw ---
log "Stopping nanoclaw..."
systemctl --user stop nanoclaw 2>/dev/null || true
sleep 2

# --- Restore database ---
if [ -f db/messages.db ]; then
    log "Restoring database..."
    cp "$DB_PATH" "${DB_PATH}.pre-restore.$(date +%s)" 2>/dev/null || true
    cp db/messages.db "$DB_PATH"
fi

# --- Restore groups ---
if [ -d groups ]; then
    log "Restoring agent memory..."
    rsync -a --delete groups/ "${GROUPS_DIR}/"
fi

# --- Restore sessions ---
if [ -d sessions ]; then
    log "Restoring sessions..."
    mkdir -p "$SESSIONS_DIR"
    rsync -a --delete sessions/ "${SESSIONS_DIR}/"
fi

# --- Restore config ---
if [ -d config/nanoclaw ]; then
    log "Restoring nanoclaw config..."
    mkdir -p "$CONFIG_DIR"
    rsync -a --delete config/nanoclaw/ "${CONFIG_DIR}/"
fi
if [ -d config/claude ]; then
    log "Restoring claude config..."
    rsync -a --delete \
        --exclude='worktrees' \
        config/claude/ "${CLAUDE_DIR}/"
fi

# --- Restart ---
log "Starting nanoclaw..."
systemctl --user start nanoclaw 2>/dev/null || true

log "Restore complete. Previous DB saved as ${DB_PATH}.pre-restore.*"

# Go back to main
git checkout main -- . 2>/dev/null || true
