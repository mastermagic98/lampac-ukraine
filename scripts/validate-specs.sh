#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] OpenAPI validation"
npx --yes @redocly/cli@2.25.2 lint docs/specs/openapi-lampac-v1.yaml

echo "[2/3] YAML parse validation"
ruby scripts/validate_openapi_semantics.rb
