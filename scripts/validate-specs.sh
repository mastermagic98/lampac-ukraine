#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[0/4] Merge marker validation"
if rg -n "^(<<<<<<<|=======|>>>>>>>)" --glob "*.py" --glob "*.sh" --glob "*.yaml" --glob "*.yml" .; then
  echo "ERROR: merge conflict markers detected" >&2
  exit 1
fi

echo "[1/4] OpenAPI validation"
npx --yes @redocly/cli@2.25.2 lint docs/specs/openapi-lampac-v1.yaml

echo "[2/4] YAML parse validation"
ruby scripts/validate_openapi_semantics.rb

if command -v psql >/dev/null 2>&1; then
  echo "[3/4] SQL dry-run validation (requires local PostgreSQL)"
  : "${DATABASE_URL:=postgresql://postgres:postgres@localhost:5432/postgres}"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/specs/db-mapping-v1.sql >/dev/null
  echo "OK docs/specs/db-mapping-v1.sql"
else
  echo "[3/4] Skipped SQL dry-run (psql is not installed locally)"
fi
