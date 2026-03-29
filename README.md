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
```

## Docker запуск (API + PostgreSQL)

```bash
docker compose up -d --build
```

Після старту застосуй схему і SQL-функції:

```bash
cat docs/specs/db-mapping-v1.sql | docker compose exec -T db psql -U postgres -d postgres
cat docs/specs/lampac-export-queries-v1.sql | docker compose exec -T db psql -U postgres -d postgres
```

API буде доступне на `http://localhost:8000`, healthcheck: `GET /healthz`.
