"""Lampac API MVP runtime."""

from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any

import psycopg
from fastapi import FastAPI, Path
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    database_url: str = Field(
        default="postgresql://postgres:postgres@localhost:5432/postgres",
        alias="DATABASE_URL",
    )


settings = Settings()


@contextmanager
def get_conn():
