#!/usr/bin/env bash
# Applies a Beaver migration to the self-hosted Supabase Postgres on the VPS.
#
# The database is not exposed to the internet, so the file is copied over and fed
# to psql inside the `db` container. Every migration is idempotent, so re-running
# one is safe.
#
# Usage: scripts/apply_migration.sh [supabase/migrations/001_beaver_schema.sql]
set -euo pipefail

cd "$(dirname "$0")/.."

MIGRATION="${1:-supabase/migrations/001_beaver_schema.sql}"
VPS="${VPS:-root@65.21.0.66}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/priority-deploy}"
# The supabase compose project lives in the priority-lists deployment; Beaver
# shares that database rather than running a second one.
REMOTE_SUPABASE_DIR="${REMOTE_SUPABASE_DIR:-/opt/priority-lists/supabase}"

if [[ ! -f "$MIGRATION" ]]; then
  echo "Не найден файл миграции: $MIGRATION" >&2
  exit 1
fi

REMOTE_PATH="/tmp/$(basename "$MIGRATION")"

echo "==> Копирую $MIGRATION на $VPS"
scp -i "$SSH_KEY" "$MIGRATION" "$VPS:$REMOTE_PATH"

echo "==> Применяю миграцию"
# ON_ERROR_STOP makes a failing statement abort the whole run with a non-zero
# exit code instead of ploughing on through the rest of the file.
ssh -i "$SSH_KEY" "$VPS" "
  set -euo pipefail
  cd $REMOTE_SUPABASE_DIR
  docker compose exec -T db psql -v ON_ERROR_STOP=1 -U postgres -d postgres < $REMOTE_PATH
  rm -f $REMOTE_PATH
"

echo "==> Готово: $(basename "$MIGRATION") применена"
