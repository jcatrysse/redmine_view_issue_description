#!/usr/bin/env bash
set -euo pipefail

REDMINE_VERSION="${1:-5.1-stable}"   # 5.1-stable, 6.0-stable, 6.1-stable
REDMINE_DIR="${REDMINE_DIR:-redmine}"
REDMINE_REPO_URL="https://github.com/redmine/redmine.git"

if ! git ls-remote --heads "$REDMINE_REPO_URL" "$REDMINE_VERSION" | grep -q "$REDMINE_VERSION"; then
  echo "ERROR: Redmine branch '$REDMINE_VERSION' not found on $REDMINE_REPO_URL" >&2
  exit 1
fi

if [ ! -d "$REDMINE_DIR/.git" ]; then
  git clone --depth 1 --branch "$REDMINE_VERSION" "$REDMINE_REPO_URL" "$REDMINE_DIR"
else
  (
    cd "$REDMINE_DIR"
    git fetch --depth 1 origin "$REDMINE_VERSION:refs/remotes/origin/$REDMINE_VERSION"
    git checkout -B "$REDMINE_VERSION" "origin/$REDMINE_VERSION"
  )
fi

PLUGIN_NAME="$(basename "$(pwd)")"
mkdir -p "$REDMINE_DIR/plugins/$PLUGIN_NAME"
rsync -a --delete --exclude "$REDMINE_DIR/" --exclude .git/ ./ "$REDMINE_DIR/plugins/$PLUGIN_NAME/"
