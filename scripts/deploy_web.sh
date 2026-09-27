#!/usr/bin/env bash
# Builds the Flutter web app and deploys it to the VPS gateway (nginx on :8000).
#
# Beaver is served under /beaver/ on the same gateway as priority-lists, so the
# build needs --base-href and the static files live in their own directory:
# /opt/beaver/web — outside supabase/, so the CI `rsync --delete` of that
# directory never touches them.
#
# The nginx `location /beaver/` block and the compose mount live in the
# priority-lists repository; see docs/deploy.md. This script only ships the build.
set -euo pipefail

cd "$(dirname "$0")/.."

VPS="${VPS:-root@65.21.0.66}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/priority-deploy}"
REMOTE_WEB_DIR="${REMOTE_WEB_DIR:-/opt/beaver/web}"

if [[ ! -f .env.json ]]; then
  echo "Нет .env.json — скопируйте .env.json.example и заполните ключ" >&2
  exit 1
fi

flutter build web --release \
  --base-href /beaver/ \
  --dart-define-from-file=.env.json

ssh -i "$SSH_KEY" "$VPS" "mkdir -p $REMOTE_WEB_DIR"
rsync -avz --delete -e "ssh -i $SSH_KEY" build/web/ "$VPS:$REMOTE_WEB_DIR/"

echo "Готово: http://65.21.0.66:8000/beaver/"
