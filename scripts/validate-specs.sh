#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] OpenAPI validation"
npx --yes @apidevtools/swagger-cli@4.0.4 validate docs/specs/openapi-lampac-v1.yaml

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
  errors << "components.schemas is required in #{openapi_file}"
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
