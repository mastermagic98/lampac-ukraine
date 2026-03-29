"""Lampac API MVP runtime.

This module exposes read-only Lampac export endpoints and minimal enrichment job
endpoints backed by PostgreSQL SQL functions/tables described in docs/specs.
"""

from contextlib import contextmanager
from types import GeneratorType
from datetime import datetime, timezone
from typing import Any

import psycopg
from fastapi import FastAPI, Path
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
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


@contextmanager
class ApiError(Exception):

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
    with _open_conn() as conn:
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
    with _open_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT lampac_export_movie_by_tmdb(c.tmdb_id, %s)
                FROM content c
                WHERE c.imdb_id = %s
                  AND c.content_type = 'movie'
                  AND c.tmdb_id IS NOT NULL
                LIMIT 1
                """,
                (include_inactive, imdb_id),
            )
            return _export_or_404(cur.fetchone(), "CONTENT_NOT_FOUND")


@app.get("/api/lampac/series/{tmdb_id}")
def series_by_tmdb(tmdb_id: int, include_inactive: bool = False) -> Any:
    with _open_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT lampac_export_series_by_tmdb(%s, %s)",
                (tmdb_id, include_inactive),
            )
            return _export_or_404(cur.fetchone(), "CONTENT_NOT_FOUND")


@app.get("/api/lampac/series/{tmdb_id}/season/{season}/episode/{episode}")
def episode_by_tmdb(
    tmdb_id: int,
    season: int,
    episode: int,
    include_inactive: bool = False,
) -> Any:
    with _open_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT lampac_export_episode_by_tmdb(%s, %s, %s, %s)",
                (tmdb_id, season, episode, include_inactive),
            )
            return _export_or_404(cur.fetchone(), "EPISODE_NOT_FOUND")


@app.post("/api/lampac/enrich/by-tmdb", status_code=202)
def enrich_by_tmdb(payload: EnrichByTmdbRequest) -> dict[str, Any]:
    if payload.content_type not in {"movie", "series"}:
        raise ApiError(
            status_code=400,
            code="INVALID_CONTENT_TYPE",
            message="content_type must be movie or series",
        )

    with _open_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO enrichment_job
                  (trigger_type, status, tmdb_id, imdb_id, requested_by, request_payload)
                VALUES
                  ('manual', 'queued', %s, %s, %s, %s::jsonb)
                RETURNING id
                """,
                (
                    payload.tmdb_id,
                    payload.imdb_id,
                    payload.requested_by,
                    payload.model_dump_json(),
                ),
            )
            job_id = cur.fetchone()[0]
        conn.commit()

    return {"status": "accepted", "job_id": job_id}


@app.get("/api/lampac/enrich/jobs/{job_id}")
def enrich_job_status(job_id: int) -> dict[str, Any]:
    with _open_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, status::text, started_at, finished_at, error_message
                FROM enrichment_job
                WHERE id = %s
                """,
                (job_id,),
            )
            row = cur.fetchone()
            if not row:
                raise ApiError(
                    status_code=404,
                    code="JOB_NOT_FOUND",
                    message="Job not found",
                )

    started_at = row[2].astimezone(timezone.utc).isoformat() if row[2] else None
    finished_at = row[3].astimezone(timezone.utc).isoformat() if row[3] else None

    return {
        "job_id": row[0],
        "status": row[1],
        "started_at": started_at,
        "finished_at": finished_at,
        "message": row[4],
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
