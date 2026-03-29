#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

openapi_file = "docs/specs/openapi-lampac-v1.yaml"
provider_file = "docs/specs/provider-registry-v1.yaml"
schemas_file = "docs/specs/openapi-lampac-schemas-v1.yaml"

openapi = YAML.safe_load_file(openapi_file, permitted_classes: [], aliases: true)
YAML.safe_load_file(provider_file, permitted_classes: [], aliases: true)
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
    next if operation.is_a?(Hash) && !operation["operationId"].to_s.strip.empty?

    errors << "operationId is required for #{method.upcase} #{path}"
  end
end

abort("OpenAPI semantic checks failed:\n- #{errors.join("\n- ")}") if errors.any?
