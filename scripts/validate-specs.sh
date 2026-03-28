#!/usr/bin/env bash
 set -euo pipefail
 
 ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
 cd "$ROOT_DIR"
 
 echo "[1/3] OpenAPI lint"
 npx --yes @redocly/cli@1.22.0 lint --config redocly.yaml docs/specs/openapi-lampac-v1.yaml
 
 echo "[2/3] YAML parse validation"
 ruby <<'RUBY'
 require "yaml"
 
 openapi_file = "docs/specs/openapi-lampac-v1.yaml"
 provider_file = "docs/specs/provider-registry-v1.yaml"
 schemas_file = "docs/specs/openapi-lampac-schemas-v1.yaml"
 
 openapi = YAML.safe_load_file(openapi_file, permitted_classes: [], aliases: true)
 provider = YAML.safe_load_file(provider_file, permitted_classes: [], aliases: true)
 schemas_doc = YAML.safe_load_file(schemas_file, permitted_classes: [], aliases: true)
 puts "OK #{openapi_file}"
 puts "OK #{provider_file}"
 puts "OK #{schemas_file}"
 
 errors = []
 
 errors << "info.license is required" unless openapi.dig("info", "license")
 errors << "top-level security is required" unless openapi["security"].is_a?(Array) && !openapi["security"].empty?
 
 schemas = schemas_doc.dig("components", "schemas")
 unless schemas.is_a?(Hash)
   errors << "components.schemas is required in #{schemas_file}"
 end
