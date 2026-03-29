from contextlib import contextmanager
from pathlib import Path
import sys

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import app as app_module


class FakeCursor:
    def __init__(self):
        self._row = None

    def execute(self, query, params=None):
        if "lampac_export_movie_by_tmdb" in query:
            if params[0] == 404:
                self._row = (None,)
            else:
                self._row = ({"content": {"tmdb_id": params[0]}, "sources": []},)
            return

        if "lampac_export_series_by_tmdb" in query:
            self._row = ({"content": {"tmdb_id": params[0]}, "seasons": []},)
            return

        if "lampac_export_episode_by_tmdb" in query:
            self._row = (
                {
                    "content": {"tmdb_id": params[0]},
                    "episode": {"season_number": params[1], "episode_number": params[2]},
                    "sources": [],
                },
            )
            return

        if "INSERT INTO enrichment_job" in query:
            self._row = (777,)
            return

        if "FROM enrichment_job" in query:
            if params[0] == 404:
                self._row = None
            else:
                self._row = (params[0], "queued", None, None, None)
            return

        raise AssertionError(f"Unexpected query: {query}")

    def fetchone(self):
        return self._row

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class FakeConn:
    def cursor(self):
        return FakeCursor()

    def commit(self):
        return None


@contextmanager
def fake_get_conn():
    yield FakeConn()


def test_healthcheck():
    client = TestClient(app_module.app)
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_movie_found(monkeypatch):
    monkeypatch.setattr(app_module, "get_conn", fake_get_conn)
    client = TestClient(app_module.app)
    r = client.get("/api/lampac/movie/100")
    assert r.status_code == 200
    assert r.json()["content"]["tmdb_id"] == 100


def test_movie_not_found(monkeypatch):
    monkeypatch.setattr(app_module, "get_conn", fake_get_conn)
    client = TestClient(app_module.app)
    r = client.get("/api/lampac/movie/404")
    assert r.status_code == 404


def test_episode_export(monkeypatch):
    monkeypatch.setattr(app_module, "get_conn", fake_get_conn)
    client = TestClient(app_module.app)
    r = client.get("/api/lampac/series/10/season/2/episode/3")
    assert r.status_code == 200
    assert r.json()["episode"]["season_number"] == 2
    assert r.json()["episode"]["episode_number"] == 3


def test_enqueue_enrichment(monkeypatch):
    monkeypatch.setattr(app_module, "get_conn", fake_get_conn)
    client = TestClient(app_module.app)
    r = client.post(
        "/api/lampac/enrich/by-tmdb",
        json={"tmdb_id": 10, "content_type": "movie"},
    )
    assert r.status_code == 202
    assert r.json() == {"status": "accepted", "job_id": 777}


def test_enrichment_job_not_found(monkeypatch):
    monkeypatch.setattr(app_module, "get_conn", fake_get_conn)
    client = TestClient(app_module.app)
    r = client.get("/api/lampac/enrich/jobs/404")
    assert r.status_code == 404
