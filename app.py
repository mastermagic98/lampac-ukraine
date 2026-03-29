"""Lampac API MVP runtime.

This module exposes read-only Lampac export endpoints and minimal enrichment job
endpoints backed by PostgreSQL SQL functions/tables described in docs/specs.
"""

from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any

import psycopg
from fastapi import FastAPI, Path
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings loaded from environment variables/.env."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str = Field(
        default="postgresql://postgres:postgres@localhost:5432/postgres",
        alias="DATABASE_URL",
    )


settings = Settings()


@contextmanager
def get_conn():
    """Create PostgreSQL connection scoped to request handler execution."""
    with psycopg.connect(settings.database_url) as conn:
        yield conn


app = FastAPI(title="Lampac API MVP", version="0.1.0")


class ApiError(Exception):
    """Structured API exception for consistent error payloads."""

    def __init__(self, status_code: int, code: str, message: str):
        self.status_code = status_code
        self.code = code
        self.message = message


@app.exception_handler(ApiError)
def api_error_handler(_, exc: ApiError):
    """Map ApiError to {'code','message'} payload."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"code": exc.code, "message": exc.message},
    )


class EnrichByTmdbRequest(BaseModel):
    """Payload for manual enrichment requests."""

    tmdb_id: int
    imdb_id: str | None = None
    content_type: str
    requested_by: str | None = None
    force: bool = False

    @field_validator("imdb_id")
    @classmethod
    def validate_imdb_id(cls, value: str | None):
        if value is None:
            return value
        if not value.startswith("tt") or not value[2:].isdigit():
            raise ValueError("imdb_id must be in format tt1234567")
        return value


def _export_or_404(row: tuple[Any] | None, code: str) -> Any:
    """Return JSON payload from one-column SQL result or raise 404 ApiError."""
    if not row or row[0] is None:
        raise ApiError(status_code=404, code=code, message=code)
    return row[0]


@app.get("/healthz")
def healthcheck() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/lampac/movie/{tmdb_id}")
def movie_by_tmdb(tmdb_id: int, include_inactive: bool = False) -> Any:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT lampac_export_movie_by_tmdb(%s, %s)",
                (tmdb_id, include_inactive),
            )
            return _export_or_404(cur.fetchone(), "CONTENT_NOT_FOUND")


@app.get("/api/lampac/movie/imdb/{imdb_id}")
def movie_by_imdb(
    imdb_id: str = Path(pattern=r"^tt[0-9]{6,12}$"),
    include_inactive: bool = False,
) -> Any:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT lampac_export_movie_by_tmdb(c.tmdb_id, %s)
                FROM content c
                WHERE c.imdb_id = %s
                  AND c.content_type = 'movie'
                  AND c.tmdb_id IS NOT NULL
