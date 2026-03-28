#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] OpenAPI lint"
npx --yes @redocly/cli@2.25.2 lint

echo "[2/3] YAML parse validation"
ruby <<'RUBY'
require "yaml"

openapi_file = "docs/specs/openapi-lampac-v1.yaml"
provider_file = "docs/specs/provider-registry-v1.yaml"

openapi = YAML.safe_load_file(openapi_file, permitted_classes: [], aliases: true)
provider = YAML.safe_load_file(provider_file, permitted_classes: [], aliases: true)
puts "OK #{openapi_file}"
puts "OK #{provider_file}"

errors = []

errors << "info.license is required" unless openapi.dig("info", "license")
errors << "top-level security is required" unless openapi["security"].is_a?(Array) && !openapi["security"].empty?

schemas = openapi.dig("components", "schemas")
unless schemas.is_a?(Hash)
  errors << "components.schemas is required"
end

required_schemas = %w[
  MovieExportResponse
  SeriesExportResponse
  EpisodeExportResponse
  EnrichByTmdbRequest
  EnrichAcceptedResponse
  EnrichJobStatusResponse
  ErrorResponse
]

if schemas.is_a?(Hash)
  missing = required_schemas.reject { |schema| schemas.key?(schema) }
  errors << "missing components.schemas: #{missing.join(', ')}" unless missing.empty?
end

tags = openapi["tags"] || []
if tags.empty? || tags.any? { |tag| tag["description"].to_s.strip.empty? }
  errors << "all tags must have description"
end

server_url = openapi.dig("servers", 0, "url").to_s
if server_url.include?("example.com") || server_url.include?("localhost")
  errors << "servers[0].url must not point to example.com/localhost"
end

paths = openapi["paths"] || {}
paths.each do |path, item|
  next unless item.is_a?(Hash)
  item.each do |method, operation|
    next unless %w[get post put patch delete head options trace].include?(method)
    unless operation.is_a?(Hash) && operation["operationId"].to_s.strip != ""
      errors << "operationId is required for #{method.upcase} #{path}"
    end
  end
end

if errors.any?
  abort("OpenAPI semantic checks failed:\n- #{errors.join("\n- ")}")
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
