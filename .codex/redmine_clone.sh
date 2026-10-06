#!/usr/bin/env bash
set -euo pipefail

# Branches: 7.0-stable-GEOxyz (what GEOxyz runs), 7.0-stable, 6.1-stable, 5.1-stable.
# The GEOxyz fork carries the upstream stable branches as well.
REDMINE_VERSION="${1:-7.0-stable-GEOxyz}"
REDMINE_DIR="${REDMINE_DIR:-redmine}"
REDMINE_REPO_URL="${REDMINE_REPO_URL:-https://github.com/jcatrysse/redmine.git}"
# Other plugins to install next to this one (space separated checkout paths),
# e.g. RMP_EXTRA_PLUGINS="../redmine_contacts ../redmine_contacts_helpdesk".
# The directory name of each path must be the plugin id.
RMP_EXTRA_PLUGINS="${RMP_EXTRA_PLUGINS:-}"

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

for extra in $RMP_EXTRA_PLUGINS; do
  extra_name="$(basename "$extra")"
  mkdir -p "$REDMINE_DIR/plugins/$extra_name"
  rsync -a --delete --exclude .git/ "$extra/" "$REDMINE_DIR/plugins/$extra_name/"
done
