#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] OpenAPI lint"
npx --yes @redocly/cli@latest lint

echo "[2/3] YAML parse validation"
ruby <<'RUBY'
require "yaml"

files = [
  "docs/specs/openapi-lampac-v1.yaml",
  "docs/specs/provider-registry-v1.yaml",
]

files.each do |file|
  YAML.safe_load_file(file, permitted_classes: [], aliases: true)
  puts "OK #{file}"
end
RUBY

if command -v psql >/dev/null 2>&1; then
  echo "[3/3] SQL dry-run validation (requires local PostgreSQL)"
  : "${DATABASE_URL:=postgresql://postgres:postgres@localhost:5432/postgres}"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/specs/db-mapping-v1.sql >/dev/null
  echo "OK docs/specs/db-mapping-v1.sql"
else
  echo "[3/3] Skipped SQL dry-run (psql is not installed locally)"
fi
