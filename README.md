# lampac-ukraine

Документаційний репозиторій специфікацій для інтеграції з Lampac:

- схема БД v1 (`docs/specs/db-mapping-v1.sql`)
- контракт експорту (`docs/specs/lampac-export-contract-v1.md`)
- OpenAPI (`docs/specs/openapi-lampac-v1.yaml`)
- реєстр провайдерів (`docs/specs/provider-registry-v1.yaml`)
- план міграції (`docs/specs/migration-plan-v1.md`)

## Локальна перевірка специфікацій

```bash
bash scripts/validate-specs.sh
```

Що перевіряється:
1. OpenAPI lint (`@redocly/cli@2.25.2`, правила в `redocly.yaml`)
2. Валідність YAML-спек (`provider-registry-v1.yaml`, `openapi-lampac-v1.yaml`)
3. SQL dry-run міграції `db-mapping-v1.sql` на тимчасовій PostgreSQL БД
