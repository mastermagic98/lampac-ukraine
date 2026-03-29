# lampac-ukraine

Документаційний репозиторій специфікацій для інтеграції з Lampac:

- схема БД v1 (`docs/specs/db-mapping-v1.sql`)
- контракт експорту (`docs/specs/lampac-export-contract-v1.md`)
- OpenAPI (`docs/specs/openapi-lampac-v1.yaml`)
- OpenAPI schemas (`docs/specs/openapi-lampac-schemas-v1.yaml`)
- реєстр провайдерів (`docs/specs/provider-registry-v1.yaml`)
- план міграції (`docs/specs/migration-plan-v1.md`)
- референсні SQL-експорти для API (`docs/specs/lampac-export-queries-v1.sql`)

## Локальна перевірка специфікацій

```bash
bash scripts/validate-specs.sh
```

Що перевіряється:
1. OpenAPI validation (`@redocly/cli@2.25.2`)
2. Валідність YAML-спек (`provider-registry-v1.yaml`, `openapi-lampac-v1.yaml`, `openapi-lampac-schemas-v1.yaml`) + семантичні guard-checks для OpenAPI (`security`, `license`, `operationId`, `tag.description`, `server url`)
3. SQL dry-run міграції `db-mapping-v1.sql` на тимчасовій PostgreSQL БД

### Troubleshooting

- Якщо бачиш помилки `No such file or directory ... openapi-lampac-schemas-v1.yaml`, перевір що файл `docs/specs/openapi-lampac-schemas-v1.yaml` присутній у репозиторії.
