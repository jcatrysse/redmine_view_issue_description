#!/usr/bin/env bash
set -euo pipefail

REDMINE_DIR="${REDMINE_DIR:-redmine}"
RAILS_ENV=test
MISE_BIN="${MISE_BIN:-mise}"

detect_ruby_version() {
  local version=""

  # The Ruby on PATH is fine when it satisfies Redmine's Gemfile: no mise needed.
  if [ ! -f ".ruby-version" ] && [ -f "Gemfile" ] && command -v ruby >/dev/null 2>&1 &&
     ruby -e 'l = File.read("Gemfile")[/^\s*ruby\s+(.+)$/, 1] or exit 1
              reqs = l.scan(/[\x22\x27]([^\x22\x27]+)[\x22\x27]/).flatten
              exit Gem::Requirement.new(*reqs).satisfied_by?(Gem::Version.new(RUBY_VERSION)) ? 0 : 1'; then
    echo ""
    return
  fi

  if [ -f ".ruby-version" ]; then
    version="$(tr -d '\n' < .ruby-version)"
  elif [ -f "Gemfile" ]; then
    local ruby_line=""
    ruby_line="$(grep -E "^[[:space:]]*ruby " Gemfile | head -n 1 || true)"

    version="$(echo "$ruby_line" | sed -E -n "s/.*ruby[[:space:]]*['\\\"]([0-9]+\\.[0-9]+(\\.[0-9]+)?)[\"'].*$/\\1/p")"
    if [ -z "$version" ]; then
      version="$(echo "$ruby_line" | sed -E -n "s/.*~>[[:space:]]*([0-9]+\\.[0-9]+(\\.[0-9]+)?).*/\\1/p")"
    fi
    if [ -z "$version" ]; then
      local upper=""
      upper="$(echo "$ruby_line" | sed -E -n "s/.*<[[:space:]]*([0-9]+\\.[0-9]+(\\.[0-9]+)?).*/\\1/p")"
      if [ -n "$upper" ]; then
        local major="${upper%%.*}"
        local minor="${upper#*.}"
        minor="${minor%%.*}"
        if [ "$minor" -gt 0 ]; then
          minor=$((minor - 1))
        fi
        version="${major}.${minor}"
      fi
    fi
  fi

  echo "$version"
}

# RMP_DB=postgresql (default) or mariadb (MySQL/MariaDB, adapter mysql2).
RMP_DB="${RMP_DB:-postgresql}"
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"

if [ "$RMP_DB" = mariadb ] || [ "$RMP_DB" = mysql ]; then
  # System deps (Ubuntu/Debian)
  command -v mysqld >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y build-essential libmariadb-dev mariadb-server nodejs; }

  # Start MariaDB (no systemd in containers: fall back to mysqld_safe)
  if ! $SUDO mysql -e 'SELECT 1' >/dev/null 2>&1; then
    $SUDO service mariadb start >/dev/null 2>&1 || ($SUDO mysqld_safe >/dev/null 2>&1 &)
    for _ in $(seq 1 30); do $SUDO mysql -e 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
  fi

  # The database must exist before db:drop: Redmine (and some plugins) touch it while booting.
  $SUDO mysql -e "CREATE DATABASE IF NOT EXISTS \`redmine_test\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS 'redmine'@'localhost' IDENTIFIED BY 'redmine';
    CREATE USER IF NOT EXISTS 'redmine'@'%' IDENTIFIED BY 'redmine';
    GRANT ALL ON \`redmine_test\`.* TO 'redmine'@'localhost';
    GRANT ALL ON \`redmine_test\`.* TO 'redmine'@'%';
    FLUSH PRIVILEGES;"

  cat > "$REDMINE_DIR/config/database.yml" <<'EOF'
test:
  adapter: mysql2
  database: redmine_test
  host: 127.0.0.1
  port: 3306
  username: redmine
  password: redmine
  encoding: utf8mb4
  variables:
    # MariaDB before 11.1 knows tx_isolation only (MySQL 8: transaction_isolation)
    tx_isolation: "READ-COMMITTED"
EOF
else
  # System deps (Ubuntu/Debian)
  command -v psql >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y build-essential libpq-dev nodejs postgresql postgresql-contrib; }

  # Start postgres
  $SUDO service postgresql start

  # Create user/db (idempotent-ish)
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='redmine'" | grep -q 1; then
    sudo -u postgres psql -c "ALTER ROLE redmine WITH LOGIN CREATEDB PASSWORD 'redmine';"
  else
    sudo -u postgres psql -c "CREATE ROLE redmine WITH LOGIN CREATEDB PASSWORD 'redmine';"
  fi
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='redmine_test'" | grep -q 1 || sudo -u postgres createdb -O redmine redmine_test

  cat > "$REDMINE_DIR/config/database.yml" <<'EOF'
test:
  adapter: postgresql
  database: redmine_test
  host: localhost
  username: redmine
  password: redmine
  encoding: unicode
EOF
fi

cd "$REDMINE_DIR"

RUBY_VERSION="$(detect_ruby_version)"
if [ -n "$RUBY_VERSION" ]; then
  if command -v "$MISE_BIN" >/dev/null 2>&1; then
    "$MISE_BIN" install "ruby@$RUBY_VERSION"
    "$MISE_BIN" use -g "ruby@$RUBY_VERSION"
  else
    echo "mise is required to install Ruby $RUBY_VERSION. Please install mise or set PATH to a compatible ruby." >&2
    exit 1
  fi
fi

if ! grep -q "rails-controller-testing" Gemfile; then
  cat <<'EOF' >> Gemfile

group :test do
  gem 'rails-controller-testing'
end
EOF
fi

bundle config set without 'development'
bundle config set path 'vendor/bundle'

if command -v "$MISE_BIN" >/dev/null 2>&1 && [ -n "${RUBY_VERSION:-}" ]; then
  "$MISE_BIN" exec "ruby@$RUBY_VERSION" -- bundle install
  "$MISE_BIN" exec "ruby@$RUBY_VERSION" -- bundle exec rake db:drop db:create db:migrate RAILS_ENV=test
  "$MISE_BIN" exec "ruby@$RUBY_VERSION" -- bundle exec rake redmine:plugins:migrate RAILS_ENV=test
else
  bundle install
  bundle exec rake db:drop db:create db:migrate RAILS_ENV=test
  bundle exec rake redmine:plugins:migrate RAILS_ENV=test
fi
