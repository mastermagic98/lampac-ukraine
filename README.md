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

У CI додатково запускаються API unit-тести (`pytest`) для `app.py`.

## API MVP (runtime)

Мінімальна реалізація API знаходиться у `app.py` і використовує SQL-функції з
`docs/specs/lampac-export-queries-v1.sql`.

### Швидкий старт

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

Перед запуском потрібно застосувати:
1. `docs/specs/db-mapping-v1.sql`
2. `docs/specs/lampac-export-queries-v1.sql`

та виставити `DATABASE_URL` (або використовувати дефолт з `app.py`).

### Тести API (без реальної БД)

```bash
pip install -r requirements-dev.txt
pytest -q
